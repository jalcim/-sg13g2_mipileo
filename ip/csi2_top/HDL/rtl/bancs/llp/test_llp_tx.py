"""Banc de llp_tx (top tb_llp_tx, INIT_CYCLES réduit) contre mipi_csi2.

Le banc joue l'application (requêtes et charge) et le Lane Management (i_tx_ready). À chaque cycle, il lit les
sorties de llp_tx au front descendant (elles sortent de bascules), pose ses entrées pour le front montant suivant
et note le cycle en TxCycle. La trace, prise dès le reset, passe par tx_link.check_tx_link ; les paquets rendus
sont comparés octet pour octet à build_long_packet et build_short_packet.

Pauses : cycles à o_tx_valid = 0 entre le premier et le dernier battement pris d'un paquet (spec §4.5).
Trous : cycles à o_pay_ready = 1 où l'application ne présente pas le mot suivant d'une charge déjà commencée.
llp_tx n'ajoute aucune pause : sans trou, 0 pause par paquet ; avec trous, pauses <= trous, et pauses = trous
quand le LM prend tout et que chaque paquet part d'un llp_tx vide.
"""
import random
from dataclasses import dataclass, field

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, ReadOnly

import modele_llp  # noqa: F401  (met mipi_csi2 dans sys.path)
from mipi_csi2.packet import build_long_packet, build_short_packet, is_short_packet_type
from mipi_csi2.tx_link import INIT_CYCLES, PAUSE_BUDGET, TxCycle, check_tx_link

PERIODE_NS = 8
CYCLES_RESET = 4
CYCLES_FIN = 8
TYPES_LONGS = (0x2A, 0x2B, 0x12)
WC_PETIT_MAX = 700
SORTIES = ("o_tx_valid", "o_tx_data", "o_tx_nb", "o_tx_last", "o_tx_total", "o_tx_init",
           "o_req_ready", "o_pay_ready", "o_init_done")
ENTREES = ("rst_n", "i_req_valid", "i_req_vc", "i_req_dt", "i_req_wc", "i_pay_valid", "i_pay_data", "i_pay_nb",
           "i_tx_ready")


@dataclass(frozen=True)
class Paquet:
    vc: int
    dt: int
    wc: int                             # WC du paquet long, champ de données du paquet court
    charge: bytes = b""

    @property
    def court(self):
        return is_short_packet_type(self.dt)

    def octets(self):
        if self.court:
            return build_short_packet(self.vc, self.dt, self.wc)
        return build_long_packet(self.vc, self.dt, self.charge)

    def mots(self):
        """Mots présentés par l'application : 4 octets, le dernier de 1 à 4, octets au-delà de nb tirés au hasard."""
        mots = []
        for debut in range(0, len(self.charge), 4):
            morceau = self.charge[debut:debut + 4]
            mots.append((int.from_bytes(morceau + random.randbytes(4 - len(morceau)), "little"), len(morceau)))
        return mots


def court(dt=None, vc=None, champ=None):
    return Paquet(random.randrange(4) if vc is None else vc, random.randrange(16) if dt is None else dt,
                  random.getrandbits(16) if champ is None else champ)


def long(wc, dt=None, vc=None):
    return Paquet(random.randrange(4) if vc is None else vc, random.choice(TYPES_LONGS) if dt is None else dt,
                  wc, random.randbytes(wc))


def melange(nb, wc_max=WC_PETIT_MAX, part_courts=0.2):
    return [court() if random.random() < part_courts else long(random.randint(0, wc_max)) for _ in range(nb)]


def trame(vc, lignes, wc, dt=0x2B):
    """FS, puis LS, ligne, LE pour chaque ligne, puis FE : ce que produit un capteur."""
    numero = random.getrandbits(16)
    paquets = [court(0x00, vc, numero)]
    for ligne in range(1, lignes + 1):
        paquets += [court(0x02, vc, ligne), long(wc, dt, vc), court(0x03, vc, ligne)]
    return paquets + [court(0x01, vc, numero)]


class LmAleatoire:
    """tx_in_ready à 0 avec une probabilité tirée entre p_min et p_max, de nouveau à chaque paquet."""

    def __init__(self, p_min=0.0, p_max=0.6):
        self.p_min, self.p_max = p_min, p_max
        self.p0 = random.uniform(p_min, p_max)

    def ready(self):
        return random.random() >= self.p0

    def front(self, pris, last):
        if pris and last:
            self.p0 = random.uniform(self.p_min, self.p_max)


class LmRealiste:
    """LM à N lanes (spec §4.2, chronogramme 5.5) : après le premier battement d'un paquet il en prend un de plus,
    puis tient tx_in_ready à 0 pendant N + 2 cycles (6 à N = 4) pour écrire ses mots de taille. Il prend sinon
    un battement tous les 4 / N cycles : un crédit de N octets par cycle, un battement coûte 4."""

    def __init__(self, lanes):
        self.lanes = lanes
        self.credit = lanes + 3
        self.arme = False
        self.bloque = 0
        self.dans_paquet = False

    def ready(self):
        return self.bloque == 0 and self.credit >= 4

    def front(self, pris, last):
        if self.bloque:
            self.bloque -= 1
        if self.arme:
            self.arme = False
            self.bloque = self.lanes + 2
        if pris:
            self.credit -= 4
            self.arme = not self.dans_paquet
            self.dans_paquet = not last
        self.credit = min(self.credit + self.lanes, self.lanes + 3)


class Application:
    """Présente les requêtes dans l'ordre et la charge en un flot de mots, tenus jusqu'à leur prise."""

    def __init__(self, paquets, trous=0.0, attendre=False):
        self.paquets = paquets
        self.trous = trous
        self.attendre = attendre        # requête suivante seulement quand le paquet précédent est sorti
        self.mots = [(data, nb, idx) for idx, p in enumerate(paquets) if not p.court for data, nb in p.mots()]
        self.i_req = 0
        self.i_mot = 0
        self.req_valid = False
        self.pay_valid = False
        self.sortis = 0
        self.trous_vus = [0] * len(paquets)

    def dans_charge(self):
        """Le mot suivant suit un mot déjà pris du même paquet : llp_tx attend la suite de cette charge."""
        return 0 < self.i_mot < len(self.mots) and self.mots[self.i_mot - 1][2] == self.mots[self.i_mot][2]

    def decide(self, pay_ready):
        if not self.req_valid and self.i_req < len(self.paquets) and (not self.attendre or self.sortis == self.i_req):
            self.req_valid = True
        if not self.pay_valid and self.i_mot < len(self.mots):
            if random.random() >= self.trous:
                self.pay_valid = True
            elif pay_ready and self.dans_charge():
                self.trous_vus[self.mots[self.i_mot][2]] += 1

    def front(self, req_pris, pay_pris):
        if req_pris:
            self.i_req += 1
            self.req_valid = False
        if pay_pris:
            self.i_mot += 1
            self.pay_valid = False


@dataclass
class Resultat:
    cycles: int
    battements: int
    pauses: list = field(default_factory=list)
    ecarts: list = field(default_factory=list)     # cycles vides entre deux paquets
    trous: list = field(default_factory=list)


def mesure(trace):
    """Pauses de chaque paquet (comme check_tx_link) et cycles vides entre deux paquets, dans l'ordre."""
    pauses, ecarts = [], []
    dans, pause, fin, battements = False, 0, None, 0
    for cycle, now in enumerate(trace):
        if dans and not now.valid:
            pause += 1
        if now.valid and not dans and fin is not None:
            ecarts.append(cycle - fin - 1)
            fin = None
        if now.valid and now.ready:
            battements += 1
            if not dans:
                dans, pause = True, 0
            if now.last:
                pauses.append(pause)
                dans, fin = False, cycle
    return pauses, ecarts, battements


class Llp:
    def __init__(self, dut):
        self.dut = dut
        self.init_cycles = int(dut.INIT_CYCLES.value)
        self.sorties = [getattr(dut, nom) for nom in SORTIES]
        for nom in ENTREES:
            getattr(dut, nom).value = 0
        Clock(dut.clk, PERIODE_NS, unit="ns").start()

    def lit(self):
        return tuple(int(handle.value) for handle in self.sorties)

    def pose(self, rst_n, app, ready):
        dut = self.dut
        dut.rst_n.value = rst_n
        dut.i_tx_ready.value = ready
        dut.i_req_valid.value = app.req_valid
        if app.req_valid:
            paquet = app.paquets[app.i_req]
            dut.i_req_vc.value = paquet.vc
            dut.i_req_dt.value = paquet.dt
            dut.i_req_wc.value = paquet.wc
        dut.i_pay_valid.value = app.pay_valid
        if app.pay_valid:
            data, nb, _ = app.mots[app.i_mot]
            dut.i_pay_data.value = data
            dut.i_pay_nb.value = nb

    async def joue(self, paquets, lm, trous=0.0, attendre=False, comb=False):
        """Reset, puis émission de paquets. Rend un Resultat ; lève une AssertionError au premier écart."""
        app = Application(paquets, trous, attendre)
        self.pose(0, app, 0)
        await FallingEdge(self.dut.clk)
        attendus = [p.octets() for p in paquets]
        limite = CYCLES_RESET + self.init_cycles + 20 * sum(len(o) // 4 + 2 for o in attendus) + 2000
        trace, chute, fin, cycle = [], None, 0, 0
        while app.sortis < len(paquets) or fin < CYCLES_FIN:
            await FallingEdge(self.dut.clk)
            assert cycle < limite, f"cycle {cycle} : {app.sortis}/{len(paquets)} paquets sortis, blocage"
            valid, data, nb, last, total, tx_init, req_ready, pay_ready, init_done = self.lit()
            en_reset = cycle <= CYCLES_RESET
            if en_reset:
                assert (valid, tx_init, req_ready, pay_ready, init_done) == (0, 1, 0, 0, 0), f"cycle {cycle} : reset"
            if tx_init:
                assert chute is None, f"cycle {cycle} : tx_init remonte"
            elif chute is None:
                chute = cycle
            attente = chute is None or cycle - chute < self.init_cycles
            assert init_done == (not attente), f"cycle {cycle} : o_init_done {init_done}, chute au cycle {chute}"
            assert not (attente and req_ready), f"cycle {cycle} : o_req_ready pendant l'attente de tx_init"
            app.decide(pay_ready)
            ready = lm.ready()
            self.pose(int(cycle >= CYCLES_RESET), app, int(ready))
            if comb:
                await ReadOnly()
                assert self.lit() == (valid, data, nb, last, total, tx_init, req_ready, pay_ready, init_done), \
                    f"cycle {cycle} : une sortie a suivi les entrées dans le cycle"
            pris = bool(valid and ready)
            trace.append(TxCycle(bool(valid), ready, data if valid else 0, nb if valid else 0, bool(valid and last),
                                 total if valid else 0, bool(tx_init)))
            lm.front(pris, bool(last))
            app.front(app.req_valid and req_ready, app.pay_valid and pay_ready)
            app.sortis += pris and bool(last)
            fin += app.sortis == len(paquets)
            cycle += 1
        budget = PAUSE_BUDGET if trous == 0 else 10 ** 9
        # INIT_CYCLES réel : le init_cycles par défaut du modèle ; réduit : le même que le RTL
        init = {} if self.init_cycles == INIT_CYCLES else {"init_cycles": self.init_cycles}
        recus = check_tx_link(trace, pause_budget=budget, **init)
        assert len(recus) == len(attendus), f"{len(recus)} paquets reçus, {len(attendus)} attendus"
        for rang, (recu, attendu) in enumerate(zip(recus, attendus)):
            assert recu == attendu, f"paquet {rang} ({paquets[rang].dt:#04x}, WC {paquets[rang].wc}) : " \
                                    f"{recu[:16].hex()}..., attendu {attendu[:16].hex()}..."
        pauses, ecarts, battements = mesure(trace)
        assert len(pauses) == len(paquets)
        res = Resultat(cycle, battements, pauses, ecarts, app.trous_vus)
        if trous == 0:
            assert not any(pauses), f"pauses sans trou de l'application : {[(r, p) for r, p in enumerate(pauses) if p]}"
        else:
            trop = [(r, p, t) for r, (p, t) in enumerate(zip(pauses, app.trous_vus)) if p > t]
            assert not trop, f"pauses au-delà des trous (paquet, pauses, trous) : {trop[:10]}"
            if attendre and isinstance(lm, LmAleatoire) and lm.p_max == 0:
                ecart = [(r, p, t) for r, (p, t) in enumerate(zip(pauses, app.trous_vus)) if p != t]
                assert not ecart, f"pauses différentes des trous (paquet, pauses, trous) : {ecart[:10]}"
        return res


def bilan(dut, nom, paquets, res):
    longs = [p.wc for p in paquets if not p.court]
    dut._log.info("%s : %d paquets (%d courts, WC %d à %d), %d battements en %d cycles, pauses %d, trous %d, "
                  "écart entre paquets %s", nom, len(paquets), len(paquets) - len(longs), min(longs, default=0),
                  max(longs, default=0), res.battements, res.cycles, sum(res.pauses), sum(res.trous),
                  f"{min(res.ecarts)} à {max(res.ecarts)}" if res.ecarts else "-")


@cocotb.test()
async def test_courts_et_trames(dut):
    """Les 16 types courts sous les 4 VC, puis des trames FS, LS, ligne, LE, FE : LM aléatoire, sans trou."""
    llp = Llp(dut)
    paquets = [court(dt, vc) for vc in range(4) for dt in range(16)]
    for vc in range(4):
        paquets += trame(vc, 4, random.randint(1, 120), random.choice(TYPES_LONGS))
    bilan(dut, "courts et trames", paquets, await llp.joue(paquets, LmAleatoire()))


@cocotb.test()
async def test_wc_0_a_700(dut):
    """Tous les WC de 0 à 700, donc tous les restes modulo 4, types 0x2A, 0x2B, 0x12 : LM aléatoire, sans trou."""
    llp = Llp(dut)
    paquets = [long(wc) for wc in range(WC_PETIT_MAX + 1)]
    random.shuffle(paquets)
    bilan(dut, "WC 0 à 700", paquets, await llp.joue(paquets, LmAleatoire()))


@cocotb.test()
async def test_lm_realiste(dut):
    """LM à N = 1, 2, 3, 4 lanes : ready bas N + 2 cycles en début de paquet, un battement tous les 4 / N cycles."""
    llp = Llp(dut)
    for lanes in (1, 2, 3, 4):
        paquets = melange(250)
        bilan(dut, f"LM réaliste N = {lanes}", paquets, await llp.joue(paquets, LmRealiste(lanes)))


@cocotb.test()
async def test_grands_wc(dut):
    """WC de 4 000 à 65 535, dont 65 535, entre des paquets courts : LM aléatoire puis réaliste à N = 4."""
    llp = Llp(dut)
    wcs = [65535, 65534, 4000, 4001, 4002, 4003] + [random.randint(4000, 65535) for _ in range(2)]
    paquets = [paquet for wc in wcs for paquet in (court(), long(wc))]
    bilan(dut, "grands WC, LM aléatoire", paquets, await llp.joue(paquets, LmAleatoire()))
    paquets = [court(0x02), long(65535), court(0x03), long(random.randint(4000, 65535))]
    bilan(dut, "grands WC, LM réaliste", paquets, await llp.joue(paquets, LmRealiste(4)))


@cocotb.test()
async def test_trous_exacts(dut):
    """Trous aléatoires dans la charge, LM toujours prêt, paquet suivant demandé une fois le précédent sorti :
    les pauses mesurées égalent exactement les trous de l'application."""
    llp = Llp(dut)
    for trous in (0.05, 0.3):
        paquets = melange(300)
        res = await llp.joue(paquets, LmAleatoire(0.0, 0.0), trous=trous, attendre=True)
        assert sum(res.trous) > 0
        bilan(dut, f"trous {trous}, LM toujours prêt", paquets, res)


@cocotb.test()
async def test_trous_lm_aleatoire(dut):
    """Trous aléatoires dans la charge, LM aléatoire, paquets enchaînés : les pauses ne dépassent pas les trous."""
    llp = Llp(dut)
    for trous in (0.1, 0.4):
        paquets = melange(300)
        bilan(dut, f"trous {trous}, LM aléatoire", paquets, await llp.joue(paquets, LmAleatoire(), trous=trous))


@cocotb.test()
async def test_dos_a_dos(dut):
    """LM toujours prêt, application sans trou : après un paquet long de WC 3 ou plus, le paquet suivant part au
    cycle qui suit son dernier battement. Ailleurs (après un court ou un long de WC 0 à 2), 2 cycles vides au plus."""
    llp = Llp(dut)
    paquets = melange(400, part_courts=0.3) + [long(wc) for wc in (0, 1, 2, 3, 4) for _ in range(4)]
    paquets += [court(), long(1), long(2), court(), court(), long(0), long(3), court()] * 4
    res = await llp.joue(paquets, LmAleatoire(0.0, 0.0))
    par_type = {}
    for rang, ecart in enumerate(res.ecarts):
        avant, apres = paquets[rang], paquets[rang + 1]
        plein = not avant.court and avant.wc >= 3
        contexte = [("court" if p.court else "long", p.wc) for p in paquets[max(rang - 2, 0):rang + 2]]
        assert ecart <= (0 if plein else 2), f"paquets {rang} et {rang + 1} : {ecart} cycles vides, " \
                                             f"(type, WC) depuis {max(rang - 2, 0)} : {contexte}"
        cle = ("long de WC 3 ou plus" if plein else "court" if avant.court else "long de WC 0 à 2") + " puis " + \
              ("court" if apres.court else "long")
        par_type.setdefault(cle, []).append(ecart)
    for cle, ecarts in sorted(par_type.items()):
        dut._log.info("%s : %d cas, écart de %d à %d cycles", cle, len(ecarts), min(ecarts), max(ecarts))
    bilan(dut, "dos à dos", paquets, res)


@cocotb.test()
async def test_sans_chemin_combinatoire(dut):
    """Les sorties ne bougent pas quand le banc change les entrées au milieu du cycle."""
    llp = Llp(dut)
    paquets = melange(200)
    bilan(dut, "sans chemin combinatoire", paquets,
          await llp.joue(paquets, LmAleatoire(), trous=0.2, comb=True))
