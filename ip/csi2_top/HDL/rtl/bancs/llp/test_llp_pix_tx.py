"""Banc de llp_pix_tx devant llp_tx (top tb_llp_pix_tx, INIT_CYCLES réduit) contre mipi_csi2.

Le banc joue l'application (requêtes vc, dt, largeur, puis battements de pixels) et le Lane Management
(i_tx_ready, LmAleatoire et LmRealiste de test_llp_tx). La trace des battements du LM passe par
tx_link.check_tx_link ; chaque paquet rendu est comparé à build_long_packet(vc, dt, pack(format, pixels)), à
build_long_packet(vc, dt, octets) pour un type brut, à build_short_packet pour un paquet court.
Une largeur refusée ne donne aucun paquet et une impulsion o_evt_width. Un i_pix_nb faux donne un o_evt_nb.
Pauses (spec §4.5) : sans trou de l'application, aucune. Trou : cycle à o_pix_ready = 1 où l'application ne
présente pas le battement suivant d'un paquet déjà commencé.
Les bits d'une case au-dessus de la largeur du pixel, et les cases au-delà des pixels du battement, sont tirés au
hasard : llp_pix_tx ne doit pas les lire.
"""
import random
from dataclasses import dataclass

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, ReadOnly

import modele_llp  # noqa: F401  (met mipi_csi2 dans sys.path)
from mipi_csi2.formats import PACKERS, pack
from mipi_csi2.packet import build_long_packet, build_short_packet, is_short_packet_type
from mipi_csi2.tx_link import INIT_CYCLES, PAUSE_BUDGET, TxCycle, check_tx_link
from test_llp_tx import CYCLES_FIN, CYCLES_RESET, PERIODE_NS, LmAleatoire, LmRealiste, mesure

if not {"RAW12", "RAW14"} <= set(PACKERS):
    raise RuntimeError("modèle mipi_csi2 sans RAW12 ni RAW14 : il faut mipi-csi feat/raw12-raw14 d829010 ou plus récent")

FORMATS = {0x28: "RAW6", 0x2A: "RAW8", 0x2B: "RAW10", 0x2C: "RAW12", 0x2D: "RAW14"}
BITS = {"RAW6": 6, "RAW8": 8, "RAW10": 10, "RAW12": 12, "RAW14": 14, None: 8}
PAR_BATTEMENT = {"RAW6": 8, "RAW8": 4, "RAW10": 4, "RAW12": 4, "RAW14": 4, None: 4}
DT = {"RAW6": 0x28, "RAW8": 0x2A, "RAW10": 0x2B, "RAW12": 0x2C, "RAW14": 0x2D}
PAS = {"RAW6": 4, "RAW8": 1, "RAW10": 4, "RAW12": 2, "RAW14": 4}           # pixels d'un groupe
OCTETS_GROUPE = {"RAW6": 3, "RAW8": 1, "RAW10": 5, "RAW12": 3, "RAW14": 7}
CASE = 14                               # largeur d'une case de pixel
BRUTS = (0x12, 0x10, 0x30)
RESERVES = set(range(0x04, 0x08)) | set(range(0x13, 0x18)) | {0x1B} | set(range(0x25, 0x28)) | {0x2E, 0x2F} \
    | set(range(0x38, 0x40))
SORTIES = ("o_tx_valid", "o_tx_data", "o_tx_nb", "o_tx_last", "o_tx_total", "o_tx_init",
           "o_req_ready", "o_pix_ready", "o_init_done", "o_evt_width", "o_evt_nb")
ENTREES = ("rst_n", "i_req_valid", "i_req_vc", "i_req_dt", "i_req_width", "i_pix_valid", "i_pix_data", "i_pix_nb",
           "i_tx_ready")


@dataclass(frozen=True)
class Paquet:
    vc: int
    dt: int
    largeur: int                        # pixels, octets en brut, champ de données d'un court
    pixels: tuple = ()

    @property
    def court(self):
        return is_short_packet_type(self.dt)

    @property
    def fmt(self):
        return FORMATS.get(self.dt)

    @property
    def refuse(self):
        if self.dt in RESERVES:         # types réservés (Table 3) : refusés comme une largeur fausse
            return True
        if self.court or self.fmt is None:
            return False
        largeur = self.largeur
        return (largeur == 0 or largeur % PAS[self.fmt] != 0
                or largeur // PAS[self.fmt] * OCTETS_GROUPE[self.fmt] > 65535)

    def octets(self):
        if self.court:
            return build_short_packet(self.vc, self.dt, self.largeur)
        if self.fmt is None:
            return build_long_packet(self.vc, self.dt, bytes(self.pixels))
        return build_long_packet(self.vc, self.dt, pack(self.fmt, list(self.pixels)))

    def battements(self):
        """Mots i_pix_data présentés : cases remplies, bits hauts et cases vides tirés au hasard."""
        if self.court:
            return []
        pas, bits = PAR_BATTEMENT[self.fmt], BITS[self.fmt]
        mots = []
        for debut in range(0, len(self.pixels), pas):
            morceau = self.pixels[debut:debut + pas]
            mot = random.getrandbits(8 * CASE)
            for rang, pixel in enumerate(morceau):
                case = random.getrandbits(CASE) >> bits << bits | pixel
                mot = mot & ~(((1 << CASE) - 1) << CASE * rang) | case << CASE * rang
            mots.append((mot, len(morceau)))
        return mots


def ligne(fmt, largeur, vc=None):
    vc = random.randrange(4) if vc is None else vc
    if fmt is None:
        return Paquet(vc, random.choice(BRUTS), largeur, tuple(random.randbytes(largeur)))
    return Paquet(vc, DT[fmt], largeur, tuple(random.getrandbits(BITS[fmt]) for _ in range(largeur)))


def court(dt=None, vc=None, champ=None):
    return Paquet(random.randrange(4) if vc is None else vc, random.randrange(16) if dt is None else dt,
                  random.getrandbits(16) if champ is None else champ)


def refusee(fmt=None):
    fmt = fmt or random.choice(list(DT))
    largeur = 0 if fmt == "RAW8" or random.random() < 0.2 else random.choice([n for n in range(1, 60) if n % PAS[fmt]])
    return Paquet(random.randrange(4), DT[fmt], largeur, tuple(random.getrandbits(BITS[fmt]) for _ in range(largeur)))


def tire_ligne():
    fmt = random.choice(list(DT) + [None])
    groupes = random.choice((random.randint(1, 8), random.randint(9, 200)))
    return ligne(fmt, groupes * PAS.get(fmt, 1))


def trame(vc, lignes, fmt, largeur):
    numero = random.getrandbits(16)
    paquets = [court(0x00, vc, numero)]
    for rang in range(1, lignes + 1):
        paquets += [court(0x02, vc, rang), ligne(fmt, largeur, vc), court(0x03, vc, rang)]
    return paquets + [court(0x01, vc, numero)]


class Application:
    """Requêtes dans l'ordre, battements de pixels en un flot, tenus jusqu'à leur prise."""

    def __init__(self, paquets, trous=0.0, faux_nb=0.0):
        self.paquets = paquets
        self.trous = trous
        self.mots = [(mot, nb, rang) for rang, paquet in enumerate(paquets) for mot, nb in paquet.battements()]
        # i_pix_nb faux sur une part des battements des paquets émis : un o_evt_nb chacun, paquet inchangé
        self.faux_nb = 0
        for rang_mot, (mot, nb, rang) in enumerate(self.mots):
            if not paquets[rang].refuse and random.random() < faux_nb:
                self.mots[rang_mot] = (mot, random.choice([n for n in range(16) if n != nb]), rang)
                self.faux_nb += 1
        self.i_req = 0
        self.i_mot = 0
        self.req_valid = False
        self.pix_valid = False
        self.trous_vus = [0] * len(paquets)

    def dans_charge(self):
        return 0 < self.i_mot < len(self.mots) and self.mots[self.i_mot - 1][2] == self.mots[self.i_mot][2]

    def decide(self, pix_ready):
        if not self.req_valid and self.i_req < len(self.paquets):
            self.req_valid = True
        if not self.pix_valid and self.i_mot < len(self.mots):
            if random.random() >= self.trous:
                self.pix_valid = True
            elif pix_ready and self.dans_charge():
                self.trous_vus[self.mots[self.i_mot][2]] += 1

    def front(self, req_pris, pix_pris):
        if req_pris:
            self.i_req += 1
            self.req_valid = False
        if pix_pris:
            self.i_mot += 1
            self.pix_valid = False


class Banc:
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
            dut.i_req_width.value = paquet.largeur
        dut.i_pix_valid.value = app.pix_valid
        if app.pix_valid:
            mot, nb, _ = app.mots[app.i_mot]
            dut.i_pix_data.value = mot
            dut.i_pix_nb.value = nb

    async def joue(self, nom, paquets, lm, trous=0.0, comb=False, faux_nb=0.0):
        """Reset, puis les paquets ; lève une AssertionError au premier écart. Rend (pauses, trous, cycles)."""
        app = Application(paquets, trous, faux_nb)
        emis = [p for p in paquets if not p.refuse]
        attendus = [p.octets() for p in emis]
        self.pose(0, app, 0)
        await FallingEdge(self.dut.clk)
        limite = CYCLES_RESET + self.init_cycles + 20 * sum(len(o) // 4 + 4 for o in attendus) \
            + 4 * len(app.mots) + 2000
        trace, sortis, fin, cycle, refus, evt_nb = [], 0, 0, 0, 0, 0
        while sortis < len(emis) or app.i_mot < len(app.mots) or app.i_req < len(paquets) or fin < CYCLES_FIN:
            await FallingEdge(self.dut.clk)
            assert cycle < limite, f"{nom}, cycle {cycle} : {sortis}/{len(emis)} paquets sortis, " \
                                   f"{app.i_mot}/{len(app.mots)} battements pris, blocage"
            valid, data, nb, last, total, tx_init, req_ready, pix_ready, init_done, evt, evt_n = self.lit()
            refus += evt
            evt_nb += evt_n
            app.decide(pix_ready)
            ready = lm.ready()
            self.pose(int(cycle >= CYCLES_RESET), app, int(ready))
            if comb:
                await ReadOnly()
                assert self.lit() == (valid, data, nb, last, total, tx_init, req_ready, pix_ready, init_done, evt,
                                      evt_n), \
                    f"{nom}, cycle {cycle} : une sortie a suivi les entrées dans le cycle"
            pris = bool(valid and ready)
            trace.append(TxCycle(bool(valid), ready, data if valid else 0, nb if valid else 0, bool(valid and last),
                                 total if valid else 0, bool(tx_init)))
            lm.front(pris, bool(last))
            app.front(app.req_valid and req_ready, app.pix_valid and pix_ready)
            sortis += pris and bool(last)
            fin += sortis == len(emis) and app.i_mot == len(app.mots) and app.i_req == len(paquets)
            cycle += 1
        budget = PAUSE_BUDGET if trous == 0 else 10 ** 9
        init = {} if self.init_cycles == INIT_CYCLES else {"init_cycles": self.init_cycles}
        recus = check_tx_link(trace, pause_budget=budget, **init)
        assert len(recus) == len(attendus), f"{nom} : {len(recus)} paquets reçus, {len(attendus)} attendus"
        for rang, (recu, attendu) in enumerate(zip(recus, attendus)):
            p = emis[rang]
            assert recu == attendu, f"{nom}, paquet {rang} (0x{p.dt:02X}, largeur {p.largeur}) : " \
                                    f"{recu[:16].hex()}..., attendu {attendu[:16].hex()}..."
        nb_refus = sum(p.refuse for p in paquets)
        assert refus == nb_refus, f"{nom} : {refus} o_evt_width, {nb_refus} largeurs refusées"
        assert evt_nb == app.faux_nb, f"{nom} : {evt_nb} o_evt_nb, {app.faux_nb} i_pix_nb faux"
        pauses, _, battements = mesure(trace)
        if trous == 0:
            assert not any(pauses), f"{nom} : pauses sans trou de l'application : " \
                                    f"{[(r, emis[r].dt, emis[r].largeur, p) for r, p in enumerate(pauses) if p][:10]}"
        self.dut._log.info("%s : %d paquets (%d refusés), %d battements du LM en %d cycles, pauses %d, trous %d",
                           nom, len(paquets), nb_refus, battements, cycle, sum(pauses), sum(app.trous_vus))
        return pauses, app.trous_vus, cycle


# Vecteurs littéraux d'empaquetage (tableau 9.5 du cahier des charges du golden model, dérivés des Figures 101,
# 106 et 110) : un oracle écrit à la main, indépendant de mipi_csi2.formats.
VECTEURS = (("RAW6", (0x3F, 0x00, 0x15, 0x2A), "3F50A9"),
            ("RAW8", (0x12, 0x34), "1234"),
            ("RAW10", (0x3FF, 0x001, 0x2AA, 0x155), "FF00AA5567"),
            ("RAW10", (0x123, 0x0AB, 0x3C4, 0x2D6), "482AF1B58F"),
            ("RAW12", (0xABC, 0x123), "AB123C"),
            ("RAW14", (0x3FFF, 0x0001, 0x2AAA, 0x1555), "FF00AA557FA056"),
            ("RAW14", (0x1234, 0x2345, 0x3456, 0x0567), "488DD11574619D"))


@cocotb.test()
async def test_vecteurs_litteraux(dut):
    """Vecteurs RAW6, RAW8 et RAW10 écrits à la main : la charge émise vaut les octets attendus."""
    banc = Banc(dut)
    paquets = []
    for fmt, pixels, charge in VECTEURS:
        paquet = Paquet(0, DT[fmt], len(pixels), pixels)
        assert paquet.octets() == build_long_packet(0, DT[fmt], bytes.fromhex(charge)), f"{fmt} : modèle"
        paquets.append(paquet)
    await banc.joue("vecteurs littéraux", paquets, LmAleatoire(0.0, 0.0))


@cocotb.test()
async def test_format_par_format(dut):
    """Chaque format, toutes les largeurs de 1 à 48 groupes, LM toujours prêt : aucune pause, paquets exacts."""
    banc = Banc(dut)
    for fmt in list(DT) + [None]:
        paquets = [ligne(fmt, PAS.get(fmt, 1) * groupes) for groupes in range(1, 49)]
        await banc.joue(f"{fmt or 'brut'}", paquets, LmAleatoire(0.0, 0.0))


@cocotb.test()
async def test_trames(dut):
    """Trames FS, LS, ligne, LE, FE dans les trois formats, LM aléatoire puis réaliste à N = 1 à 4."""
    banc = Banc(dut)
    paquets = []
    for fmt in DT:
        paquets += trame(random.randrange(4), 3, fmt, 4 * random.randint(1, 100))
    await banc.joue("trames, LM aléatoire", paquets, LmAleatoire())
    for lanes in (1, 2, 3, 4):
        paquets = [p for fmt in ("RAW6", "RAW10", "RAW8", "RAW12", "RAW14") for p in trame(0, 2, fmt, 4 * random.randint(20, 160))]
        await banc.joue(f"trames, LM réaliste N = {lanes}", paquets, LmRealiste(lanes))


@cocotb.test()
async def test_melange(dut):
    """Lignes des quatre formats, paquets courts et largeurs refusées au hasard, LM aléatoire."""
    banc = Banc(dut)
    paquets = []
    for _ in range(400):
        tirage = random.random()
        paquets.append(court() if tirage < 0.2 else refusee() if tirage < 0.3 else tire_ligne())
    await banc.joue("mélange", paquets, LmAleatoire())


@cocotb.test()
async def test_grandes_lignes(dut):
    """Lignes de 4 000 à 16 000 pixels, RAW10 de 52 428 pixels (WC 65 535), largeur RAW10 au-delà refusée."""
    banc = Banc(dut)
    paquets = [ligne(fmt, 4 * random.randint(1000, 4000)) for fmt in DT]
    paquets += [ligne("RAW10", 52428), Paquet(1, 0x2B, 52432, tuple(random.getrandbits(10) for _ in range(52432)))]
    # RAW14 : WC 65 534 pour 37 448 pixels, 37 452 refusés (WC 65 541) ; RAW12 : WC 65 535 pour 43 690, 43 692 refusés
    paquets += [ligne("RAW14", 37448), Paquet(2, 0x2D, 37452, tuple(random.getrandbits(14) for _ in range(37452)))]
    paquets += [ligne("RAW12", 43690), Paquet(3, 0x2C, 43692, tuple(random.getrandbits(12) for _ in range(43692)))]
    await banc.joue("grandes lignes, LM toujours prêt", paquets, LmAleatoire(0.0, 0.0))
    await banc.joue("grandes lignes, LM réaliste N = 4", paquets[:3], LmRealiste(4))


@cocotb.test()
async def test_trous(dut):
    """Trous de l'application dans les pixels, LM aléatoire : paquets exacts, pauses mesurées."""
    banc = Banc(dut)
    for trous in (0.05, 0.3):
        paquets = [tire_ligne() if random.random() < 0.8 else court() for _ in range(200)]
        await banc.joue(f"trous {trous}", paquets, LmAleatoire(), trous=trous)


@cocotb.test()
async def test_sans_chemin_combinatoire(dut):
    """Les sorties ne bougent pas quand le banc change les entrées au milieu du cycle."""
    banc = Banc(dut)
    paquets = [tire_ligne() if random.random() < 0.7 else court() if random.random() < 0.6 else refusee()
               for _ in range(150)]
    await banc.joue("sans chemin combinatoire", paquets, LmAleatoire(), trous=0.2, comb=True)


@cocotb.test()
async def test_pix_nb_faux(dut):
    """i_pix_nb faux sur 10 % des battements : un o_evt_nb par battement, paquets exacts, aucune pause."""
    banc = Banc(dut)
    paquets = [tire_ligne() if random.random() < 0.8 else refusee() for _ in range(150)]
    await banc.joue("i_pix_nb faux", paquets, LmAleatoire(0.0, 0.0), faux_nb=0.1)

