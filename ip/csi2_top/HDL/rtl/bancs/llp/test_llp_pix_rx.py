"""Banc de llp_pix_rx derrière llp_rx (top tb_llp_pix_rx) contre mipi_csi2.formats et mipi_csi2.rx.

Le flux du LM vient de test_llp_rx.Flux : mêmes bursts, mêmes erreurs. Trois contrôles :
- Au cycle : une référence du README de llp_pix_rx, nourrie des sorties de llp_rx au cycle c, donne les sorties
  attendues au cycle c + LATENCE (en-têtes, cases de pixels, fins, paquets courts). Le banc s'arrête au premier écart.
- À la ligne, oracle mipi_csi2.formats : chaque ligne publiée est rapprochée du paquet long publié par llp_rx.
  Ligne bonne : ses pixels valent unpack(format, charge). État 4 : unpack ou payload_size refusent cette charge.
  Ligne coupée ou fausse : ses pixels sont le début de ce que la charge reçue contient de groupes complets
  (de pixels complets en RAW6). Un type non RAW sort ses octets tels quels.
- De bout en bout, sur les trames propres : les lignes bonnes valent les pixels tirés au départ, et les images de
  mipi_csi2.rx.receive_stream(framing="sot") pour le même flux.
"""
import random
from collections import Counter, deque

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge

import modele_llp  # noqa: F401  (met mipi_csi2 dans sys.path)
from mipi_csi2.formats import PACKERS, pack, raw_format_by_data_type, unpack

if not {"RAW12", "RAW14"} <= set(PACKERS):
    raise RuntimeError("modèle mipi_csi2 sans RAW12 ni RAW14 : il faut mipi-csi feat/raw12-raw14 d829010 ou plus récent")
from mipi_csi2.llp import LmBeat
from mipi_csi2.packet import DataTypeClass, build_long_packet, build_short_packet, data_type_class
from mipi_csi2.rx import receive_stream
from test_llp_rx import CYCLE_VIDE, ECART_MAX, GENRES_COUPE, GENRES_ERREUR, Flux, Moniteur, champ, code_battement

PERIODE_NS = 8
LATENCE = 1                             # sorties de llp_rx vers sorties de llp_pix_rx (README, patch 03)
VIDANGE = 6
FORMATS = {0x28: "RAW6", 0x2A: "RAW8", 0x2B: "RAW10", 0x2C: "RAW12", 0x2D: "RAW14"}
CODE_FORMAT = {None: 0, "RAW6": 1, "RAW8": 2, "RAW10": 3, "RAW12": 5, "RAW14": 6}
PAS = {"RAW6": 4, "RAW8": 1, "RAW10": 4, "RAW12": 2, "RAW14": 4}             # pixels d'un groupe
OCTETS_GROUPE = {"RAW6": 3, "RAW8": 1, "RAW10": 5, "RAW12": 3, "RAW14": 7}
BITS = {"RAW6": 6, "RAW8": 8, "RAW10": 10, "RAW12": 12, "RAW14": 14}
CASE = 14                               # largeur d'une case de pixel
IMAGES_NON_DEPAQUETEES = (0x29, 0x1E, 0x24)             # RAW7, YUV422 8 bits, RGB888 : code 4

# Bus o_pix de tb_llp_pix_rx, du poids faible au poids fort
CHAMPS_PIX = (("sol", 1), ("sol_vc", 2), ("sol_dt", 6), ("sol_wc", 16), ("sol_fmt", 3), ("pix_valid", 1),
              ("pix_nb", 3), ("pix_data", 6 * CASE), ("eol", 1), ("eol_status", 3), ("short_valid", 1), ("short_vc", 2),
              ("short_dt", 6), ("short_data", 16))


def decoupe(mot, champs):
    sortie, rang = {}, 0
    for nom, largeur in champs:
        sortie[nom] = champ(mot, rang, largeur)
        rang += largeur
    return sortie


def sorties_rx(mot):
    """Sorties de llp_rx, rangement de tb_llp_rx."""
    return {"hdr": champ(mot, 0, 1), "vc": champ(mot, 1, 2), "dt": champ(mot, 3, 6), "wc": champ(mot, 9, 16),
            "short": champ(mot, 25, 1), "pay": champ(mot, 28, 1), "data": champ(mot, 29, 32),
            "nb": champ(mot, 61, 3), "end": champ(mot, 64, 1), "status": champ(mot, 65, 2)}


def nom_format(dt):
    return FORMATS.get(dt)


def code_format(dt):
    """o_sol_fmt attendu : 1, 2, 3, 5, 6 pour RAW6/8/10/12/14, 4 pour un autre type image (octets bruts), 0 sinon."""
    if dt in FORMATS:
        return CODE_FORMAT[FORMATS[dt]]
    return 4 if data_type_class(dt) is DataTypeClass.IMAGE else 0


def taille_refusee(fmt, wc):
    """payload_size de mipi_csi2.formats, et WC nul d'une ligne image."""
    return fmt is not None and (wc == 0 or wc % OCTETS_GROUPE[fmt] != 0)


def normalise(sortie):
    """Champs comparés : ceux qu'une impulsion rend valides, plus les cases de pixels à chaque cycle."""
    vus = {"sol": sortie["sol"], "pix": (sortie["pix_valid"], sortie["pix_nb"], sortie["pix_data"]),
           "eol": sortie["eol"], "short": sortie["short_valid"]}
    if sortie["sol"]:
        vus["sol_champs"] = (sortie["sol_vc"], sortie["sol_dt"], sortie["sol_wc"], sortie["sol_fmt"])
    if sortie["eol"]:
        vus["eol_status"] = sortie["eol_status"]
    if sortie["short_valid"]:
        vus["short_champs"] = (sortie["short_vc"], sortie["short_dt"], sortie["short_data"])
    return vus


class Reference:
    """Le README de llp_pix_rx, cycle par cycle : sorties de llp_rx au cycle c vers sorties au cycle c + LATENCE."""

    def __init__(self):
        self.ouvert, self.fmt, self.refusee = False, None, False
        self.reste, self.reste_n = 0, 0         # bits en RAW6, octets en RAW10 (premier en poids faible)

    def cycle(self, rx):
        long = rx["hdr"] and not rx["short"]
        sortie = {"sol": int(long), "pix_valid": 0, "pix_nb": 0, "pix_data": 0, "eol": rx["end"], "eol_status": 0,
                  "short_valid": int(rx["hdr"] and rx["short"]), "sol_vc": rx["vc"], "sol_dt": rx["dt"],
                  "sol_wc": rx["wc"], "sol_fmt": code_format(rx["dt"]), "short_vc": rx["vc"],
                  "short_dt": rx["dt"], "short_data": rx["wc"]}
        refusee_fin = taille_refusee(nom_format(rx["dt"]), rx["wc"]) if long and not self.ouvert else self.refusee
        if long:
            self.fmt, self.refusee = nom_format(rx["dt"]), taille_refusee(nom_format(rx["dt"]), rx["wc"])
            self.reste, self.reste_n = 0, 0
        if rx["pay"]:
            pixels = self.charge(rx["data"] & (1 << 8 * rx["nb"]) - 1, rx["nb"])
            sortie["pix_valid"] = int(bool(pixels))
            sortie["pix_nb"] = len(pixels)
            sortie["pix_data"] = sum(pixel << CASE * rang for rang, pixel in enumerate(pixels))
        if rx["end"]:
            sortie["eol_status"] = rx["status"] or (4 if refusee_fin else 0)
        self.ouvert = (not (rx["end"] and not self.ouvert)) if long else self.ouvert and not rx["end"]
        return normalise(sortie)

    def charge(self, data, nb):
        if self.fmt == "RAW6":
            bits = self.reste | data << self.reste_n
            total = self.reste_n + 8 * nb
            compte = total // 6
            self.reste, self.reste_n = bits >> 6 * compte, total - 6 * compte
            return [bits >> 6 * rang & 0x3F for rang in range(compte)]
        if self.fmt in ("RAW10", "RAW12", "RAW14"):
            groupe = OCTETS_GROUPE[self.fmt]
            octets = (self.reste | data << 8 * self.reste_n).to_bytes(12, "little")[:self.reste_n + nb]
            complets = len(octets) // groupe * groupe
            self.reste, self.reste_n = int.from_bytes(octets[complets:], "little"), len(octets) - complets
            return unpack(self.fmt, octets[:complets]) if complets else []
        return list(data.to_bytes(4, "little")[:nb])


def pixels_recus(fmt, charge):
    """Pixels que la charge reçue contient en entier : groupes complets, pixels complets en RAW6."""
    if fmt == "RAW6":
        bits = int.from_bytes(charge, "little")
        return [bits >> 6 * rang & 0x3F for rang in range(len(charge) * 8 // 6)]
    if fmt in ("RAW10", "RAW12", "RAW14"):
        groupe = OCTETS_GROUPE[fmt]
        return unpack(fmt, charge[:len(charge) // groupe * groupe])
    return list(charge)


class Lignes:
    """Regroupe les sorties de llp_pix_rx en lignes et paquets courts ; retire les lignes jetées (état 3)."""

    def __init__(self):
        self.ouverte = None
        self.evenements = []
        self.jetees = 0

    def ferme(self, statut):
        vc, dt, wc, fmt, pixels = self.ouverte
        self.ouverte = None
        if statut == 3:
            self.jetees += 1
            return
        self.evenements.append(("ligne", vc, dt, wc, fmt, tuple(pixels), statut))

    def lit(self, sortie):
        if sortie["eol"] and self.ouverte is not None and not sortie["sol"]:
            # o_sol_* tiennent la ligne jusqu'à son o_eol, même quand un paquet court arrive au même cycle
            tenus = (sortie["sol_vc"], sortie["sol_dt"], sortie["sol_wc"], sortie["sol_fmt"])
            assert tenus == tuple(self.ouverte[:4]), f"o_sol_* {tenus} à o_eol, ligne {self.ouverte[:4]}"
        if sortie["eol"] and self.ouverte is not None and (sortie["sol"] or sortie["short_valid"]):
            self.ferme(sortie["eol_status"])
            sortie = dict(sortie, eol=0)
        if sortie["short_valid"]:
            self.evenements.append(("court", sortie["short_vc"], sortie["short_dt"], sortie["short_data"]))
        if sortie["sol"]:
            assert self.ouverte is None, "o_sol alors qu'une ligne est ouverte"
            self.ouverte = (sortie["sol_vc"], sortie["sol_dt"], sortie["sol_wc"], sortie["sol_fmt"], [])
        if sortie["pix_valid"]:
            assert self.ouverte is not None, "o_pix_valid hors d'une ligne"
            self.ouverte[4].extend(sortie["pix_data"] >> CASE * rang & (1 << CASE) - 1 for rang in range(sortie["pix_nb"]))
        if sortie["eol"]:
            assert self.ouverte is not None, "o_eol sans ligne ouverte"
            self.ferme(sortie["eol_status"])


def rapproche(lignes, paquets, nom):
    """Oracle formats.py : chaque ligne contre le paquet long de llp_rx qui la porte."""
    longs = [paquet for paquet in paquets if paquet[0] == "paquet" and not paquet[4]]
    courts = [paquet for paquet in paquets if paquet[0] == "paquet" and paquet[4]]
    lignes_seules = [ligne for ligne in lignes if ligne[0] == "ligne"]
    courts_pix = [ligne for ligne in lignes if ligne[0] == "court"]
    assert len(lignes_seules) == len(longs), f"{nom} : {len(lignes_seules)} lignes, {len(longs)} paquets longs"
    assert [c[1:] for c in courts_pix] == [(p[1], p[2], p[3]) for p in courts], f"{nom} : paquets courts"
    bilan = Counter()
    for rang, (ligne, paquet) in enumerate(zip(lignes_seules, longs)):
        _, vc, dt, wc, code, pixels, statut = ligne
        _, pvc, pdt, pwc, _, _, _, charge, fin = paquet
        fmt = nom_format(dt)
        contexte = f"{nom}, ligne {rang} (vc {vc}, dt 0x{dt:02X}, wc {wc}, état {statut})"
        assert (vc, dt, wc, code) == (pvc, pdt, pwc, code_format(dt)), f"{contexte} : en-tête {paquet[1:4]}"
        attendu = fin or (4 if taille_refusee(fmt, wc) else 0)
        assert statut == attendu, f"{contexte} : état attendu {attendu}"
        assert list(pixels) == pixels_recus(fmt, charge), f"{contexte} : pixels"
        if fmt is None:
            bilan["brut"] += 1
        elif statut == 0:
            assert list(pixels) == unpack(fmt, charge), f"{contexte} : unpack"
            bilan[f"{fmt} bonne"] += 1
        elif statut == 4:
            try:
                refuse = len(charge) == 0 or unpack(fmt, charge) is None
            except ValueError:
                refuse = True
            assert refuse, f"{contexte} : état 4 sur une charge que unpack accepte"
            bilan[f"{fmt} taille refusée"] += 1
        else:
            bilan[f"{fmt} état {statut}"] += 1
    return bilan


def ligne_pixels(rng, fmt, largeur):
    return [rng.getrandbits(BITS[fmt]) for _ in range(largeur)]


def tire_largeur(rng, fmt):
    tirage = rng.random()
    groupes = rng.randint(1, 4) if tirage < 0.3 else rng.randint(5, 80) if tirage < 0.9 else rng.randint(81, 1000)
    return groupes * PAS[fmt]


def trame_pixels(rng, numero, fmt=None, vc=None):
    """FS, deux lignes 0x12, lignes RAW6, RAW8 ou RAW10 de même largeur, FE. Rend les paquets et les lignes."""
    vc = rng.randrange(4) if vc is None else vc
    fmt = fmt or rng.choice(list(PAS))
    dt = {v: k for k, v in FORMATS.items()}[fmt]
    largeur = tire_largeur(rng, fmt)
    paquets = [build_short_packet(vc, 0x00, numero & 0xFFFF)]
    paquets += [build_long_packet(vc, 0x12, rng.randbytes(rng.randint(0, 60))) for _ in range(2)]
    lignes = [ligne_pixels(rng, fmt, largeur) for _ in range(rng.randint(1, 4))]
    paquets += [build_long_packet(vc, dt, pack(fmt, ligne)) for ligne in lignes]
    paquets.append(build_short_packet(vc, 0x01, numero & 0xFFFF))
    return paquets, dt, lignes


def ligne_hors_groupe(rng):
    """Ligne RAW dont la taille n'est pas un multiple du groupe, ou de WC nul : état 4 attendu."""
    dt = rng.choice(list(FORMATS))
    fmt = FORMATS[dt]
    wc = 0 if fmt == "RAW8" or rng.random() < 0.2 else rng.choice(
        [n for n in range(1, 40) if n % OCTETS_GROUPE[fmt]])
    return build_long_packet(rng.randrange(4), dt, rng.randbytes(wc))


# --- exécution ---------------------------------------------------------------------------------------------------


async def joue(dut, flux, nom):
    """Reset, puis le flux cycle par cycle ; contrôle au cycle, puis à la ligne. Rend (lignes, bilan)."""
    rng = flux.rng
    front = FallingEdge(dut.clk)
    dut.rst_n.value = 0
    dut.i_beat.value = 0
    for _ in range(3):
        await front
    dut.rst_n.value = 1
    reference, moniteur, lignes = Reference(), Moniteur(), Lignes()
    paquets, attendus = [], deque([None] * LATENCE)
    beats = flux.beats + [CYCLE_VIDE] * VIDANGE
    for cycle, beat in enumerate(beats):
        await front
        rx = int(dut.o_rx.value)
        sortie = decoupe(int(dut.o_pix.value), CHAMPS_PIX)
        attendu = attendus.popleft()
        if attendu is not None and normalise(sortie) != attendu:
            raise AssertionError(f"{nom} : écart au cycle {cycle} ({flux.origine(cycle - 2 - LATENCE)})\n"
                                 f"  RTL :       {normalise(sortie)}\n  référence : {attendu}")
        lignes.lit(sortie)
        paquets += moniteur.lit(rx)
        attendus.append(reference.cycle(sorties_rx(rx)))
        dut.i_beat.value = code_battement(rng, beat)
    assert lignes.ouverte is None and moniteur.ouvert is None, f"{nom} : ligne encore ouverte en fin de flux"
    bilan = rapproche(lignes.evenements, paquets, nom)
    dut._log.info("%s : %d cycles, %d lignes, %d courts, %d lignes jetées ; %s", nom, len(beats),
                  sum(1 for ev in lignes.evenements if ev[0] == "ligne"),
                  sum(1 for ev in lignes.evenements if ev[0] == "court"), lignes.jetees, dict(sorted(bilan.items())))
    return lignes.evenements, bilan


async def scenario(dut, nom, construit, lanes=(1, 2, 3, 4)):
    Clock(dut.clk, PERIODE_NS, unit="ns").start()
    for nb_lanes in lanes:
        flux = Flux(random.Random(random.getrandbits(64)), nb_lanes)
        flux.parasites()
        extra = construit(flux)
        # Burst de fermeture : llp_rx ne ferme un paquet qu'au sot suivant (R3). Sans lui, un dernier burst coupé en
        # plein paquet laisse la ligne ouverte en fin de flux. Un paquet court générique, sans effet sur les lignes.
        flux.burst(build_short_packet(0, 0x08, 0))
        evenements, _ = await joue(dut, flux, f"{nom}, N = {nb_lanes or 'aléatoire'}")
        if extra is not None:
            extra(flux, evenements, nb_lanes)


@cocotb.test()
async def test_trames_propres(dut):
    """Trames propres RAW6, RAW8, RAW10 : lignes contre les pixels tirés et contre receive_stream(framing="sot")."""
    def construit(flux):
        rng = flux.rng
        tirees, numeros = [], Counter()
        for _ in range(30):
            flux.p_trou = rng.choice((0.0, 0.0, 0.1, 0.3))
            vc = rng.randrange(4)
            numeros[vc] += 1                # numéros de trame consécutifs sur chaque VC (annexe C.4)
            paquets, dt, lignes = trame_pixels(rng, numeros[vc], vc=vc)
            tirees.append((dt, lignes))
            for paquet in paquets:
                flux.burst(paquet)

        def verifie(flux, evenements, nb_lanes):
            recues = [ev for ev in evenements if ev[0] == "ligne" and ev[2] in FORMATS]
            attendues = [(dt, ligne) for dt, lignes in tirees for ligne in lignes]
            assert [(ev[2], list(ev[5])) for ev in recues] == attendues, "lignes contre les pixels tirés"
            assert all(ev[6] == 0 for ev in recues), "ligne propre en erreur"
            beats = [b if b != CYCLE_VIDE else LmBeat(b"") for b in flux.beats]
            trames = [t for t in receive_stream(beats, framing="sot") if t.frame_number is not None]
            images = [(dt, ligne) for t in trames for dt, lignes in t.images.items() for ligne in lignes]
            assert images == attendues, "lignes contre receive_stream"
            # Flux.ecart glisse parfois un battement vide (burst perdu, R10) : seul burst_error est permis
            erreurs = [e for t in trames for e in t.errors if e.kind != "burst_error"]
            assert not erreurs, erreurs[:2]
        return verifie
    await scenario(dut, "trames propres", construit)


# Vecteurs littéraux d'empaquetage : RAW6 à RAW10 du tableau 9.5 du cahier des charges du golden model (Figures 101,
# 106, 110), RAW12 et RAW14 figés dans le modèle feat/raw12-raw14 (Figures 113, 116). Oracle écrit à la main,
# indépendant du code de mipi_csi2.formats.
VECTEURS = ((0x28, "3F50A9", (0x3F, 0x00, 0x15, 0x2A)),
            (0x2A, "1234", (0x12, 0x34)),
            (0x2B, "FF00AA5567", (0x3FF, 0x001, 0x2AA, 0x155)),
            (0x2B, "482AF1B58F", (0x123, 0x0AB, 0x3C4, 0x2D6)),
            (0x2C, "AB123C", (0xABC, 0x123)),
            (0x2D, "FF00AA557FA056", (0x3FFF, 0x0001, 0x2AAA, 0x1555)),
            (0x2D, "488DD11574619D", (0x1234, 0x2345, 0x3456, 0x0567)))


@cocotb.test()
async def test_vecteurs_litteraux(dut):
    """Vecteurs RAW6, RAW8 et RAW10 écrits à la main : les pixels publiés valent les pixels attendus."""
    def construit(flux):
        for dt, charge, _ in VECTEURS:
            flux.burst(build_long_packet(0, dt, bytes.fromhex(charge)))

        def verifie(flux, evenements, nb_lanes):
            recues = [(ev[2], ev[5], ev[6]) for ev in evenements if ev[0] == "ligne"]
            assert recues == [(dt, pixels, 0) for dt, _, pixels in VECTEURS], recues
        return verifie
    await scenario(dut, "vecteurs littéraux", construit)


@cocotb.test()
async def test_format_par_format(dut):
    """Chaque format seul, toutes les largeurs de 1 à 64 groupes, bursts dos à dos, sans trou puis avec."""
    def construit(flux):
        rng = flux.rng
        flux.ecart_max = 0
        for dt, fmt in FORMATS.items():
            for groupes in range(1, 65):
                flux.p_trou = 0.0 if groupes % 2 else 0.3
                flux.burst(build_long_packet(rng.randrange(4), dt, pack(fmt, ligne_pixels(rng, fmt,
                                                                                        groupes * PAS[fmt]))))
    await scenario(dut, "format par format", construit)


@cocotb.test()
async def test_tailles_refusees(dut):
    """Lignes RAW hors groupe ou de WC nul (état 4, ou 1 et 2 s'il y a aussi CRC faux ou coupe), lignes bonnes,
    types bruts et types image non dépaquetés."""
    def construit(flux):
        rng = flux.rng
        for rang in range(300):
            flux.p_trou = rng.choice((0.0, 0.2))
            tirage = rng.random()
            if tirage < 0.4:
                # taille hors groupe seule, ou avec un CRC faux ou une coupe : l'état de llp_rx passe avant 4
                flux.burst(ligne_hors_groupe(rng), rng.choice(("propre", "propre", "crc", "coupe_paquet")))
            elif tirage < 0.8:
                fmt = rng.choice(list(PAS))
                dt = {v: k for k, v in FORMATS.items()}[fmt]
                flux.burst(build_long_packet(rng.randrange(4), dt, pack(fmt, ligne_pixels(rng, fmt, PAS[fmt] * 3))))
            else:
                # types bruts, puis types image non dépaquetés (RAW7, RAW12, RAW14, YUV422, RGB888) : code 4
                flux.burst(build_long_packet(rng.randrange(4), rng.choice((0x12, 0x30, 0x10) + IMAGES_NON_DEPAQUETEES),
                                             rng.randbytes(rng.randint(0, 40))))
    await scenario(dut, "tailles refusées", construit)


@cocotb.test()
async def test_erreurs(dut):
    """CRC faux, rx_out_err, troncatures au milieu d'un groupe, en-têtes abîmés : la ligne s'arrête au dernier
    pixel complet et son état reprend celui de llp_rx."""
    genres = ("propre", "crc", "ecc1_donnees", "ecc2", "type_reserve") + GENRES_ERREUR + GENRES_COUPE

    def construit(flux):
        rng = flux.rng
        for numero in range(40):
            flux.p_trou = rng.choice((0.0, 0.1, 0.3))
            flux.ecart_max = rng.choice((0, 3, ECART_MAX))
            paquets, _, _ = trame_pixels(rng, numero)
            for paquet in paquets:
                flux.burst(paquet, rng.choice(genres), rng.random() < 0.1)
    await scenario(dut, "erreurs", construit)


@cocotb.test()
async def test_nb_variable(dut):
    """Hors spec : 1 à 4 octets par battement, pour tous les restes de RAW6 et RAW10."""
    def construit(flux):
        rng = flux.rng
        for numero in range(40):
            paquets, _, _ = trame_pixels(rng, numero)
            for paquet in paquets:
                flux.burst(paquet, rng.choice(("propre", "propre", "crc", "coupe_paquet")))
    await scenario(dut, "nb variable", construit, lanes=(None,))
