"""Banc de llp_rx (top tb_llp_rx) contre mipi_csi2.llp.LlpHead(framing="sot").

Chaque cycle, le même battement LmBeat va au RTL et au modèle (un battement sans octet ni drapeau est un cycle où
rx_out_valid vaut 0). Les sorties du modèle sont traduites en événements attendus, datés du cycle où le RTL doit les
publier ; les sorties du RTL sont regroupées en événements de même forme :
- ("paquet", vc, dt, wc, court, corrigé, sot_err, charge, fin) : paquet long, o_hdr_valid, la charge, puis
  o_end_valid ; paquet court, o_hdr_valid seul (fin None) ;
- ("ecc",) : o_evt_ecc ; ("dt", vc) : o_evt_dt et o_evt_dt_vc ; ("court",) : o_evt_short_burst ; ("burst", tardif) : o_evt_burst, avec
  o_evt_burst_late (le paquet du burst était déjà sorti : BurstError.after_packet du modèle).
Toutes les sorties d'un battement sortent LATENCE cycles après lui (README). Dans un même cycle, les événements du
burst précédent (fin du paquet ouvert, evt_short_burst) passent avant ceux du nouveau burst.
Les deux suites sont comparées cycle par cycle, dans l'ordre : le banc s'arrête au premier écart et affiche le burst,
le cycle et les deux suites. Un paquet jeté par rx_out_err disparaît chez le modèle, alors que le RTL publie son
en-tête puis la fin 3 : le banc vérifie que cette fin tombe au cycle de o_evt_burst, puis retire le paquet.
R2 : avant le premier sot, ni le modèle (mipi-csi 8132e12 ou plus récent, exigé par modele_llp.py) ni le RTL ne
publient rien, pas même un BurstError sur un battement en erreur.
"""
import bisect
import random
from collections import Counter, deque

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge

import modele_llp  # noqa: F401  (met mipi_csi2 dans sys.path)
from mipi_csi2.crc import crc16
from mipi_csi2.ecc import EccStatus, correct_header, ecc8
from mipi_csi2.llp import BurstError, LlpHead, LmBeat, SotError, TrailOverrun
from mipi_csi2.packet import (
    DataTypeClass,
    build_long_packet,
    build_short_packet,
    data_type_class,
    is_short_packet_type,
    split_data_identifier,
)

PERIODE_NS = 8
LATENCE = 2
VIDANGE = LATENCE + 2
HISTORIQUE = 12
TRAINE_MAX = 40
ECART_MAX = 40
PARASITES_MAX = 12
WC_MAX = 65535
CYCLE_VIDE = LmBeat(b"")
RESERVES = [dt for dt in range(64) if data_type_class(dt) is DataTypeClass.RESERVED]

# Bus i_beat de tb_llp_rx : {sot_err, err, sot, valid, nb[2:0], data[31:0]}
ENTREE_NB, ENTREE_VALID, ENTREE_SOT, ENTREE_ERR, ENTREE_SOT_ERR = 32, 35, 36, 37, 38


def code_battement(rng, beat):
    """Mot i_beat d'un cycle. Les octets au-delà de nb et, sans valid, tous les champs, sont tirés au hasard."""
    if beat == CYCLE_VIDE:
        return rng.getrandbits(39) & ~(1 << ENTREE_VALID)
    nb = len(beat.data)
    data = int.from_bytes(beat.data, "little") | rng.getrandbits(32) >> 8 * nb << 8 * nb
    return (data | nb << ENTREE_NB | 1 << ENTREE_VALID | beat.sot << ENTREE_SOT | beat.error << ENTREE_ERR
            | beat.sot_error << ENTREE_SOT_ERR)


def champ(mot, rang, largeur):
    return mot >> rang & (1 << largeur) - 1


class Ecart(AssertionError):
    pass


class Moniteur:
    """Regroupe les sorties de llp_rx en événements, vérifie l'ordre hdr, charge, fin, et retire les fins 3."""

    def __init__(self):
        self.ouvert = None
        self.jetes = 0
        self.colles = 0                 # cycles avec la fin du paquet précédent et un nouvel en-tête
        self.entete_et_fin = 0          # cycles avec l'en-tête et la fin d'un même paquet long

    def ajoute(self, mot):
        nb, data = champ(mot, 61, 3), champ(mot, 29, 32)
        if self.ouvert is None:
            raise Ecart("o_pay_valid hors d'un paquet long ouvert")
        if not 1 <= nb <= 4 or data >> 8 * nb:
            raise Ecart(f"o_pay_nb = {nb}, o_pay_data = 0x{data:08X} : octets hors charge non nuls")
        self.ouvert[6] += data.to_bytes(4, "little")[:nb]
        if len(self.ouvert[6]) > self.ouvert[2]:
            raise Ecart(f"charge de {len(self.ouvert[6])} octets pour un WC de {self.ouvert[2]}")

    def ferme(self, mot):
        *entete, charge = self.ouvert
        self.ouvert = None
        return ("paquet", *entete, bytes(charge), champ(mot, 65, 2))

    def lit(self, mot):
        """Événements d'un cycle : d'abord ceux du burst précédent (charge et fin du paquet ouvert,
        evt_short_burst), puis ceux du nouveau (en-tête, sa charge, evt_ecc, evt_dt, sa fin, evt_burst)."""
        evenements = []
        entete, charge, fin = champ(mot, 0, 1), champ(mot, 28, 1), champ(mot, 64, 1)
        if entete and fin and self.ouvert is not None:
            evenements.append(self.ferme(mot))
            fin = 0
            self.colles += 1
        if not entete:
            if charge:
                self.ajoute(mot)
                charge = 0
            if fin and self.ouvert is not None:
                evenements.append(self.ferme(mot))
                fin = 0
        if champ(mot, 69, 1):
            evenements.append(("court",))
        if entete:
            if self.ouvert is not None:
                raise Ecart("o_hdr_valid alors que le paquet long précédent n'a pas eu son o_end_valid")
            vc, dt, wc, court = champ(mot, 1, 2), champ(mot, 3, 6), champ(mot, 9, 16), champ(mot, 25, 1)
            publie = [vc, dt, wc, court, champ(mot, 26, 1), champ(mot, 27, 1), bytearray()]
            if court:
                evenements.append(("paquet", *publie[:6], b"", None))
            else:
                self.ouvert = publie
        if charge:
            self.ajoute(mot)
        if champ(mot, 67, 1):
            evenements.append(("ecc",))
        if champ(mot, 70, 1):
            evenements.append(("dt", champ(mot, 72, 2)))
        if fin:
            if self.ouvert is None:
                raise Ecart("o_end_valid sans paquet long ouvert")
            self.entete_et_fin += entete
            evenements.append(self.ferme(mot))
        if champ(mot, 68, 1):
            evenements.append(("burst", champ(mot, 71, 1)))
        elif champ(mot, 71, 1):
            raise Ecart("o_evt_burst_late sans o_evt_burst")
        gardes = []
        for rang, evenement in enumerate(evenements):
            if evenement[0] == "paquet" and evenement[-1] == 3:
                if evenements[rang + 1:rang + 2] != [("burst", 0)]:
                    raise Ecart("fin 3 sans o_evt_burst au même cycle")
                self.jetes += 1
                continue
            gardes.append(evenement)
        return gardes


class Modele:
    """LlpHead(framing="sot") : ses sorties traduites en événements, datés du cycle de publication attendu."""

    def __init__(self):
        self.tete = LlpHead(framing="sot", max_trail=10**9)
        self.vu_sot = False

    def battement(self, beat, cycle):
        evenements, sot_err = [], False
        sorties = self.tete.feed(beat.data, beat.sot, beat.error, beat.sot_error)
        self.vu_sot |= beat.sot
        if not self.vu_sot:
            assert all(isinstance(sortie, BurstError) for sortie in sorties), sorties
            return []
        for sortie in sorties:
            if isinstance(sortie, TrailOverrun):
                continue
            if isinstance(sortie, SotError):
                sot_err = True
                continue
            if isinstance(sortie, BurstError):
                evenements.append((cycle + LATENCE, ("burst", int(sortie.after_packet))))
                continue
            evenements.append(self.paquet(sortie, cycle, sot_err))
            sot_err = False
        assert not sot_err, f"cycle {cycle} : SotError du modèle sans paquet derrière"
        return evenements

    @staticmethod
    def paquet(paquet, cycle, sot_err):
        if len(paquet) < 4:
            return cycle + LATENCE, ("court",)
        ecc = correct_header(paquet[:4])
        if ecc.status is EccStatus.UNCORRECTABLE:
            return cycle + LATENCE, ("ecc",)
        vc, dt = split_data_identifier(ecc.header[0])
        if data_type_class(dt) is DataTypeClass.RESERVED:
            return cycle + LATENCE, ("dt", vc)
        wc = ecc.header[1] | ecc.header[2] << 8
        court = is_short_packet_type(dt)
        charge, fin = b"", None
        if not court:
            charge = paquet[4:4 + wc]
            if len(paquet) < 4 + wc + 2:
                fin = 2
            else:
                fin = int(crc16(charge) != paquet[-2] | paquet[-1] << 8)
        corrige = int(ecc.status is EccStatus.CORRECTED)
        return cycle + LATENCE, ("paquet", vc, dt, wc, int(court), corrige, int(sot_err), charge, fin)


def texte(evenement):
    cycle, (nom, *reste) = evenement
    if nom != "paquet":
        return f"{cycle:>8} {nom}"
    vc, dt, wc, court, corrige, sot_err, charge, fin = reste
    apercu = charge[:12].hex() + ("..." if len(charge) > 12 else "")
    return (f"{cycle:>8} paquet vc {vc} dt 0x{dt:02X} wc {wc} court {court} corrigé {corrige} sot_err {sot_err} "
            f"charge {len(charge)} o [{apercu}] fin {fin}")


def texte_battement(beat):
    if beat == CYCLE_VIDE:
        return "-"
    drapeaux = [nom for nom, vrai in (("sot", beat.sot), ("err", beat.error), ("sot_err", beat.sot_error)) if vrai]
    return f"{beat.data.hex() or '(vide)'} {' '.join(drapeaux)}"


# --- fabrication du flux -----------------------------------------------------------------------------------------


def tire_wc(rng):
    tirage = rng.random()
    if tirage < 0.25:
        return rng.randint(0, 9)
    if tirage < 0.75:
        return rng.randint(10, 120)
    if tirage < 0.97:
        return rng.randint(121, 700)
    return rng.randint(701, 4100)


def trame_imx219(rng, numero, cadrage_ligne=False):
    """FS, deux lignes 0x12, lignes RAW10 (0x2B) ou RAW8 (0x2A) de même largeur, FE."""
    vc = rng.randrange(4)
    dt = rng.choice((0x2B, 0x2A))
    wc = tire_wc(rng)
    paquets = [build_short_packet(vc, 0x00, numero & 0xFFFF)]
    paquets += [build_long_packet(vc, 0x12, rng.randbytes(tire_wc(rng))) for _ in range(2)]
    for ligne in range(1, rng.randint(1, 4) + 1):
        if cadrage_ligne:
            paquets.append(build_short_packet(vc, 0x02, ligne))
        paquets.append(build_long_packet(vc, dt, rng.randbytes(wc)))
        if cadrage_ligne:
            paquets.append(build_short_packet(vc, 0x03, ligne))
    paquets.append(build_short_packet(vc, 0x01, numero & 0xFFFF))
    return paquets


def paquet_quelconque(rng):
    """Type de données tiré parmi les 64 : court (0x00 à 0x0F) ou long, réservés compris."""
    vc, dt = rng.randrange(4), rng.randrange(64)
    if is_short_packet_type(dt):
        return build_short_packet(vc, dt, rng.getrandbits(16))
    return build_long_packet(vc, dt, rng.randbytes(tire_wc(rng)))


def paquet_reserve(rng):
    """En-tête d'un type réservé (R5), suivi d'autant d'octets qu'un paquet long de ce WC."""
    wc = tire_wc(rng)
    entete = bytes([rng.randrange(4) << 6 | rng.choice(RESERVES), wc & 0xFF, wc >> 8])
    return entete + bytes([ecc8(entete)]) + rng.randbytes(wc + 2)


def inverse_bits(octets, rangs):
    octets = bytearray(octets)
    for rang in rangs:
        octets[rang // 8] ^= 1 << rang % 8
    return bytes(octets)


GENRES_ENTETE = ("ecc1_donnees", "ecc1_parite", "ecc2", "ecc_reserve")
GENRES_ERREUR = ("err_sot", "err_milieu", "err_traine")
GENRES_COUPE = ("coupe_entete", "coupe_paquet")


class Flux:
    """Suite de battements, un par cycle, et la liste des bursts qu'elle porte."""

    def __init__(self, rng, lanes, p_trou=0.2, ecart_max=ECART_MAX):
        self.rng = rng
        self.lanes = lanes              # None : nb tiré de 1 à 4 à chaque battement
        self.p_trou = p_trou
        self.ecart_max = ecart_max
        self.beats = []
        self.debuts = []                # premier cycle de chaque burst
        self.descriptions = []
        self.genres = Counter()

    def trou(self, cycles):
        self.beats += [CYCLE_VIDE] * cycles

    def parasites(self):
        """Battements avant le premier sot, avec ou sans rx_out_err et rx_out_sot_err : à ignorer (R2)."""
        rng = self.rng
        for _ in range(rng.randint(1, PARASITES_MAX)):
            octets = rng.randbytes(self.lanes or rng.randint(1, 4)) if rng.random() < 0.9 else b""
            self.beats.append(LmBeat(octets, False, rng.random() < 0.3, rng.random() < 0.2))
            self.trou(rng.randint(0, 2))

    def ecart(self):
        """Entre deux bursts : 0 à ecart_max cycles vides, parfois un battement vide (burst perdu, R10) au milieu."""
        avant = self.rng.randint(0, self.ecart_max)
        self.trou(avant // 2)
        if self.rng.random() < 0.05:
            self.vide()
        self.trou(avant - avant // 2)

    def vide(self):
        self.note("vide", "battement vide")
        self.beats.append(LmBeat(b"", True, True))

    def note(self, genre, description):
        self.debuts.append(len(self.beats))
        self.descriptions.append(f"burst {len(self.debuts) - 1} ({genre}) : {description}")
        self.genres[genre] += 1

    def tailles(self, longueur):
        """Octets de chaque battement : N partout, le dernier complété par la traîne ; ou 1 à 4 au hasard."""
        if self.lanes:
            return [self.lanes] * -(-longueur // self.lanes)
        tailles = []
        while sum(tailles) < longueur:
            tailles.append(self.rng.randint(1, 4))
        return tailles

    def burst(self, paquet, genre="propre", sot_err=False):
        """Un burst : le paquet, abîmé selon genre, puis la traîne, en battements avec des trous."""
        rng = self.rng
        traine = rng.randint(0, TRAINE_MAX)
        if genre == "err_traine":
            traine = max(traine, 2 * (self.lanes or 4))
        if genre == "type_reserve":
            paquet = paquet_reserve(rng)
        if genre in GENRES_ENTETE:
            rangs = {"ecc1_donnees": [rng.randrange(24)], "ecc1_parite": [rng.randrange(24, 30)],
                     "ecc2": rng.sample(range(30), 2), "ecc_reserve": [rng.randrange(30, 32)]}[genre]
            paquet = inverse_bits(paquet[:4], rangs) + paquet[4:]
        if genre == "crc":
            if len(paquet) == 4:
                genre = "propre"
            else:
                rang = rng.randrange(32, 8 * len(paquet))
                paquet = paquet[:4] + inverse_bits(paquet[4:], [rang - 32])
        flot = paquet + rng.randbytes(traine)
        tailles = self.tailles(len(flot))
        flot += rng.randbytes(sum(tailles) - len(flot))
        fins = [sum(tailles[:rang + 1]) for rang in range(len(tailles))]
        err_des = None
        if genre in GENRES_COUPE:
            permis = [rang + 1 for rang, fin in enumerate(fins)
                      if (fin < 4 if genre == "coupe_entete" else 4 <= fin < len(paquet))]
            if not permis and genre == "coupe_entete":
                genre = "coupe_paquet"
                permis = [rang + 1 for rang, fin in enumerate(fins) if 4 <= fin < len(paquet)]
            if permis:
                tailles = tailles[:rng.choice(permis)]
            else:
                genre = "propre"
        dernier_du_paquet = next(rang for rang, fin in enumerate(fins) if fin >= len(paquet))
        if genre == "err_sot":
            err_des = 0
        elif genre == "err_milieu":
            err_des = rng.randint(min(1, dernier_du_paquet), dernier_du_paquet)
        elif genre == "err_traine":
            err_des = rng.randint(dernier_du_paquet + 1, len(tailles) - 1)
        self.note(genre, f"{len(paquet)} o [{paquet[:8].hex()}], {len(tailles)} battements"
                         f"{f', err dès le {err_des}e' if err_des is not None else ''}{', sot_err' if sot_err else ''}")
        debut = 0
        for rang, taille in enumerate(tailles):
            if rang and rng.random() < self.p_trou:
                self.trou(rng.randint(1, 3))
            erreur = err_des is not None and rang >= err_des
            self.beats.append(LmBeat(flot[debut:debut + taille], rang == 0, erreur, rang == 0 and sot_err))
            debut += taille
        self.ecart()

    def origine(self, cycle):
        rang = bisect.bisect_right(self.debuts, cycle) - 1
        return self.descriptions[rang] if rang >= 0 else "avant le premier burst"


# --- exécution ---------------------------------------------------------------------------------------------------


async def joue(dut, flux, nom, attente=0, pilote_reset=True, suivi=None, retard=0):
    """Reset, puis le flux cycle par cycle ; comparaison au modèle à chaque cycle.

    attente : cycles vides de plus avant le flux (reset synchronisé d'un top). pilote_reset faux : un autre banc tient
    rst_n. suivi(cycle, mot, obtenus, beat) : appelé à chaque cycle, une fois les sorties comparées et le battement posé.
    retard : cycles de bascules d'un top entre le battement et llp_rx, ajoutés aux latences.
    """
    rng = flux.rng
    front = FallingEdge(dut.clk)
    dut.i_beat.value = 0
    if pilote_reset:
        dut.rst_n.value = 0
        for _ in range(3):
            await front
        dut.rst_n.value = 1
    for _ in range(attente):
        await front
    moniteur, modele = Moniteur(), Modele()
    attendus, historique = deque(), deque(maxlen=HISTORIQUE)
    beats = flux.beats + [CYCLE_VIDE] * (VIDANGE + retard)
    nb_evenements = 0
    for cycle, beat in enumerate(beats):
        await front
        obtenus, cause, mot = [], None, int(dut.o_mon.value)
        try:
            obtenus = [(cycle, evenement) for evenement in moniteur.lit(mot)]
        except Ecart as erreur:
            cause = str(erreur)
        prevus = []
        while attendus and attendus[0][0] <= cycle:
            prevus.append(attendus.popleft())
        if cause is None and obtenus != prevus:
            cause = "suites différentes"
        if cause is not None:
            lignes = [f"{nom} : écart au cycle {cycle} : {cause}",
                      f"  battement du cycle {cycle - LATENCE - retard} : {flux.origine(cycle - LATENCE - retard)}",
                      "  événements déjà concordants :", *("    " + texte(ev) for ev in historique),
                      "  RTL :", *("    " + texte(ev) for ev in obtenus),
                      "  modèle :", *("    " + texte(ev) for ev in prevus),
                      "  modèle, à suivre :", *("    " + texte(ev) for ev in list(attendus)[:4]),
                      "  derniers battements :", *(f"    {rang:>8} {texte_battement(beats[rang])}"
                                                   for rang in range(max(0, cycle - 8), cycle))]
            raise Ecart("\n".join(lignes))
        historique.extend(obtenus)
        nb_evenements += len(obtenus)
        dut.i_beat.value = code_battement(rng, beat)
        if suivi is not None:
            suivi(cycle, mot, obtenus, beat)
        for evenement in modele.battement(beat, cycle + retard):
            assert not attendus or evenement[0] >= attendus[-1][0], "événements du modèle hors d'ordre"
            attendus.append(evenement)
    assert not attendus, f"{nom} : événements du modèle jamais publiés : {[texte(ev) for ev in attendus]}"
    dut._log.info("%s : %d cycles, %d bursts, %d événements comparés, %d paquets jetés par err, %d cycles fin et "
                  "en-tête de deux bursts, %d cycles en-tête et fin d'un même paquet ; %s",
                  nom, len(beats), sum(flux.genres.values()), nb_evenements, moniteur.jetes, moniteur.colles,
                  moniteur.entete_et_fin, dict(sorted(flux.genres.items())))
    return flux.genres


async def scenario(dut, nom, construit, lanes=(1, 2, 3, 4)):
    """Un flux par valeur de N, fabriqué par construit(flux), joué depuis un reset."""
    Clock(dut.clk, PERIODE_NS, unit="ns").start()
    total = Counter()
    for nb_lanes in lanes:
        flux = Flux(random.Random(random.getrandbits(64)), nb_lanes)
        flux.parasites()
        construit(flux)
        total += await joue(dut, flux, f"{nom}, N = {nb_lanes or 'aléatoire'}")
    dut._log.info("%s : %d bursts au total, %s", nom, sum(total.values()), dict(sorted(total.items())))


def tire_p_trou(rng):
    return rng.choice((0.0, 0.0, 0.1, 0.3, 0.6))


def trames(flux, nb_trames, choisit_genre=lambda rng, paquet: "propre", p_sot_err=0.0, cadrage=False):
    rng = flux.rng
    for numero in range(nb_trames):
        flux.p_trou = tire_p_trou(rng)
        for paquet in trame_imx219(rng, numero, cadrage):
            flux.burst(paquet, choisit_genre(rng, paquet), rng.random() < p_sot_err)


@cocotb.test()
async def test_trames_imx219(dut):
    """Trames IMX219 propres : FS, 0x12, RAW10 ou RAW8, FE, WC de 0 à 4 100, traîne de 0 à 40 octets."""
    await scenario(dut, "trames IMX219", lambda flux: trames(flux, 40))


@cocotb.test()
async def test_entetes(dut):
    """En-tête à un bit faux (données, parité), à deux bits faux, ECC[7:6] à 1, type réservé (R5)."""
    def genre(rng, paquet):
        return rng.choice(("propre", "type_reserve") + GENRES_ENTETE)
    await scenario(dut, "en-têtes", lambda flux: trames(flux, 40, genre))


@cocotb.test()
async def test_crc(dut):
    """CRC faux : un bit inversé dans la charge ou dans le pied."""
    def genre(rng, paquet):
        return rng.choice(("propre", "crc"))
    await scenario(dut, "CRC", lambda flux: trames(flux, 30, genre))


@cocotb.test()
async def test_erreurs_burst(dut):
    """rx_out_err dès le sot, au milieu du paquet, seulement dans la traîne (R8, R9) ; battements vides (R10)."""
    def construit(flux):
        rng = flux.rng
        for numero in range(40):
            flux.p_trou = tire_p_trou(rng)
            for paquet in trame_imx219(rng, numero):
                if rng.random() < 0.15:
                    flux.vide()
                    flux.ecart()
                flux.burst(paquet, rng.choice(("propre",) + GENRES_ERREUR))
    await scenario(dut, "erreurs de burst", construit)


@cocotb.test()
async def test_troncatures(dut):
    """sot au milieu d'un paquet (R3), sot après 1 à 3 octets d'en-tête, écarts de 0 cycle entre bursts."""
    def construit(flux):
        rng = flux.rng
        for numero in range(40):
            flux.p_trou = tire_p_trou(rng)
            flux.ecart_max = rng.choice((0, 3, ECART_MAX))
            for paquet in trame_imx219(rng, numero):
                flux.burst(paquet, rng.choice(("propre",) + GENRES_COUPE))
    await scenario(dut, "troncatures", construit)


@cocotb.test()
async def test_sot_err(dut):
    """rx_out_sot_err sur le battement sot (R11), seul ou avec un en-tête abîmé, un CRC faux, une erreur, une coupe."""
    def genre(rng, paquet):
        return rng.choice(("propre", "propre", "ecc1_donnees", "ecc2", "type_reserve", "crc", "err_sot", "err_milieu",
                           "coupe_paquet"))
    await scenario(dut, "sot_err", lambda flux: trames(flux, 30, genre, p_sot_err=0.5))


TOUS_GENRES = ("propre",) * 6 + GENRES_ENTETE + GENRES_ERREUR + GENRES_COUPE + ("crc", "type_reserve")


def melange(flux, nb_bursts):
    rng = flux.rng
    for rang in range(nb_bursts):
        if rang % 20 == 0:
            flux.p_trou = tire_p_trou(rng)
            flux.ecart_max = rng.choice((0, 5, ECART_MAX))
        if rng.random() < 0.03:
            flux.vide()
            flux.ecart()
        paquet = paquet_quelconque(rng) if rng.random() < 0.5 else rng.choice(trame_imx219(rng, rang, True))
        flux.burst(paquet, rng.choice(TOUS_GENRES), rng.random() < 0.1)


@cocotb.test()
async def test_melange(dut):
    """Tous les cas au hasard, types de données quelconques (réservés compris), LS et LE."""
    await scenario(dut, "mélange", lambda flux: melange(flux, 600))


@cocotb.test()
async def test_nb_variable(dut):
    """Hors spec (nb vaut N sur tout le burst) : 1 à 4 octets tirés à chaque battement, pour R13 dans tous ses cas."""
    await scenario(dut, "nb variable", lambda flux: melange(flux, 600), lanes=(None,))


@cocotb.test()
async def test_paquet_max(dut):
    """Paquet long de 65 541 octets (WC 65 535), CRC bon puis faux, entre deux paquets courts."""
    def construit(flux):
        rng = flux.rng
        for genre in ("propre", "crc"):
            flux.burst(build_short_packet(0, 0x00, 1))
            flux.burst(build_long_packet(1, 0x2B, rng.randbytes(WC_MAX)), genre)
            flux.burst(build_short_packet(0, 0x01, 1))
    await scenario(dut, "paquet maximal", construit, lanes=(4, 3))
