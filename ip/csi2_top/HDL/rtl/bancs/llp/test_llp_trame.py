"""Banc de llp_trame derrière llp_rx (top tb_llp_trame) contre mipi_csi2.rx.receive_stream(framing="sot"), mipi-csi
master d738c80 ou plus récent.

Le flux du LM vient de test_llp_rx.Flux : mêmes bursts, mêmes erreurs de burst. Les trames sont fabriquées ici, avec
des défauts de structure injectés (FS, FE, LS, LE absents ou faux, numéros de trame et de ligne, longueurs de ligne,
trames vides, lignes hors trame). Le même flux passe par le modèle, avec max_trail illimité (llp_rx ne compte pas la
traîne). Comparaisons :
- les erreurs de trame et de ligne, genre par genre et dans l'ordre des paquets, avec leur VC (hors trame, celui que
  le modèle range dans StreamError.virtual_channel depuis d738c80) ;
- par VC, la suite des trames fermées par un FE, bonnes ou non (o_fe_ok contre ReceivedFrame.ok) ;
- le nombre de pertes par genre (short_burst, ecc_uncorrectable, burst_error) et de burst_error tardifs ;
- les compteurs, contre les impulsions.
Écart toléré et compté : une trame que le modèle juge fausse pour le seul burst_error tardif de son FE, arrivé après
sa fermeture, et que llp_trame a déjà comptée bonne (README).
"""
import random
from collections import Counter, defaultdict

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge

import modele_llp  # noqa: F401  (met mipi_csi2 dans sys.path)
from mipi_csi2.formats import pack
from mipi_csi2.llp import LmBeat
from mipi_csi2.packet import build_long_packet, build_short_packet
from mipi_csi2.rx import StreamError, receive_stream
from test_llp_rx import CYCLE_VIDE, ECART_MAX, GENRES_COUPE, GENRES_ENTETE, GENRES_ERREUR, Flux, champ, code_battement

PERIODE_NS = 8
VIDANGE = 8
PAS = {"RAW6": 4, "RAW8": 1, "RAW10": 4, "RAW12": 2, "RAW14": 4}
DT = {"RAW6": 0x28, "RAW8": 0x2A, "RAW10": 0x2B, "RAW12": 0x2C, "RAW14": 0x2D}
BITS = {"RAW6": 6, "RAW8": 8, "RAW10": 10, "RAW12": 12, "RAW14": 14}
CHAMPS = (("fs", 1), ("fe", 1), ("fe_ok", 1), ("frame_vc", 2), ("frame_number", 16), ("err_hdr", 7),
          ("err_hdr_vc", 2), ("err_end", 3), ("err_end_vc", 2), ("loss", 3), ("loss_mask", 4), ("late", 1),
          ("late_mask", 4), ("slots_full", 1), ("cnt_ok", 16), ("cnt_frame", 16), ("cnt_line", 16))
ERR_HDR = ("missing_frame_end", "missing_frame_start", "frame_number_sequence", "frame_number_mismatch",
           "empty_frame", "line_sync_mismatch", "line_number_sequence")
ERR_END = ("missing_frame_start", "line_number_sequence", "line_length_mismatch")
GENRES_TRAME = set(ERR_HDR) | set(ERR_END)
GENRES_LIGNE = {"line_sync_mismatch", "line_number_sequence", "line_length_mismatch"}
PERTES = ("short_burst", "ecc_uncorrectable", "burst_error")


def decoupe(mot):
    sortie, rang = {}, 0
    for nom, largeur in CHAMPS:
        sortie[nom] = champ(mot, rang, largeur)
        rang += largeur
    return sortie


# --- fabrication des trames ----------------------------------------------------------------------------------------


def ligne(rng, vc, fmt, largeur):
    return build_long_packet(vc, DT[fmt], pack(fmt, [rng.getrandbits(BITS[fmt]) for _ in range(largeur)]))


def numeros_ligne(rng, n):
    """Numéros de LS d'une trame : progressifs, entrelacés, nuls, ou faux."""
    mode = rng.choice(("progressif", "progressif", "entrelace", "nuls", "faux"))
    if mode == "progressif":
        return list(range(1, n + 1))
    if mode == "entrelace":
        pas = rng.randint(2, 4)
        return [rng.randint(1, 9) + pas * rang for rang in range(n)]
    if mode == "nuls":
        return [0] * n
    numeros = list(range(1, n + 1))
    rang = rng.randrange(n)
    numeros[rang] = rng.choice((0, numeros[rang] + rng.randint(1, 3), max(numeros[rang] - 1, 0)))
    return numeros


def trame(rng, vc, numero, avec_ls=None, fe=None, lignes=None, largeurs=None, embarquees=None, user=False):
    """Paquets d'une trame : FS, lignes 0x12, lignes RAW (LS et LE autour si avec_ls), ligne user, FE."""
    fmt = rng.choice(list(PAS))
    n = rng.randint(1, 4) if lignes is None else lignes
    largeur = PAS[fmt] * rng.randint(1, 8)
    largeurs = largeurs or [largeur] * n
    avec_ls = rng.random() < 0.5 if avec_ls is None else avec_ls
    numeros = numeros_ligne(rng, n) if avec_ls else None
    paquets = [build_short_packet(vc, 0x00, numero)]
    for _ in range(rng.randint(0, 2) if embarquees is None else embarquees):
        paquets.append(build_long_packet(vc, 0x12, rng.randbytes(rng.randint(0, 12))))
    for rang in range(n):
        if avec_ls:
            paquets.append(build_short_packet(vc, 0x02, numeros[rang]))
        paquets.append(ligne(rng, vc, fmt, largeurs[rang]))
        if avec_ls:
            paquets.append(build_short_packet(vc, 0x03, numeros[rang]))
    if user:
        paquets.append(build_long_packet(vc, 0x30 + rng.randrange(8), rng.randbytes(rng.randint(1, 20))))
    paquets.append(build_short_packet(vc, 0x01, numero if fe is None else fe))
    return paquets


def entrelace(rng, flots):
    """Mêle plusieurs suites de paquets en gardant l'ordre de chacune."""
    flots = [list(flot) for flot in flots if flot]
    sortie = []
    while flots:
        flot = rng.choice(flots)
        sortie.append(flot.pop(0))
        if not flot:
            flots.remove(flot)
    return sortie


class Numeros:
    """Numéros de trame par VC : suite normale, ou nuls pour un VC."""

    def __init__(self, rng):
        self.rng = rng
        self.dernier = {}
        self.nuls = {vc: rng.random() < 0.15 for vc in range(4)}

    def suivant(self, vc, defaut=False):
        if self.nuls[vc]:
            return 0
        precedent = self.dernier.get(vc, self.rng.randrange(1, 0xFFFF))
        numero = precedent % 0xFFFF + 1
        if defaut:
            numero = self.rng.choice((numero + self.rng.randint(1, 3), 1, 0, precedent))
            numero %= 0x10000
        self.dernier[vc] = numero
        return numero


def trames_propres(rng, nb, vcs=(0, 1)):
    numeros = Numeros(rng)
    flots = defaultdict(list)
    for _ in range(nb):
        vc = rng.choice(vcs)
        flots[vc] += trame(rng, vc, numeros.suivant(vc), user=rng.random() < 0.2)
    return entrelace(rng, flots.values())


def trames_defauts(rng, nb, vcs=(0, 1)):
    """Défauts de structure : un par trame au plus, tiré au hasard."""
    numeros = Numeros(rng)
    flots = defaultdict(list)
    for _ in range(nb):
        vc = rng.choice(vcs)
        defaut = rng.choice(("aucun", "numero", "fe_faux", "sans_fs", "sans_fe", "sans_ls", "sans_le", "ls_faux",
                             "largeur", "vide", "hors_trame", "double_fs"))
        numero = numeros.suivant(vc, defaut == "numero")
        if defaut == "vide":
            paquets = [build_short_packet(vc, 0x00, numero), build_short_packet(vc, 0x01, numero)]
        elif defaut == "hors_trame":
            paquets = [ligne(rng, vc, "RAW8", 4)] + trame(rng, vc, numero)
        elif defaut == "largeur":
            n = rng.randint(2, 4)
            largeurs = [4 * rng.randint(1, 6) for _ in range(n)]
            paquets = trame(rng, vc, numero, lignes=n, largeurs=largeurs)
        elif defaut == "fe_faux":
            paquets = trame(rng, vc, numero, fe=(numero + 1) % 0x10000)
        elif defaut in ("sans_ls", "sans_le", "ls_faux"):
            paquets = trame(rng, vc, numero, avec_ls=True, lignes=rng.randint(2, 4))
            genre = {"sans_ls": 0x02, "sans_le": 0x03}.get(defaut)
            rangs = [rang for rang, paquet in enumerate(paquets) if paquet[0] & 0x3F in (0x02, 0x03)]
            rang = rng.choice(rangs)
            if genre is not None:
                rangs = [r for r in rangs if paquets[r][0] & 0x3F == genre]
                del paquets[rng.choice(rangs)]
            else:
                paquets[rang] = build_short_packet(vc, paquets[rang][0] & 0x3F, rng.randrange(0, 12))
        else:
            paquets = trame(rng, vc, numero)
            if defaut == "sans_fs":
                paquets = paquets[1:]
            elif defaut == "sans_fe":
                paquets = paquets[:-1]
            elif defaut == "double_fs":
                paquets.insert(rng.randint(1, len(paquets) - 1), build_short_packet(vc, 0x00, numero))
        flots[vc] += paquets
    return entrelace(rng, flots.values())


def remplit(flux, paquets, genres=("propre",), p_sot_err=0.0):
    rng = flux.rng
    for paquet in paquets:
        if rng.random() < 0.02:
            flux.vide()
            flux.ecart()
        flux.burst(paquet, rng.choice(genres), rng.random() < p_sot_err)
    # Burst de fermeture : llp_rx ne ferme un burst qu'au sot suivant, le modèle aussi à la fin du flux. Un paquet
    # court générique referme le dernier burst des deux côtés, sans effet sur les trames.
    flux.burst(build_short_packet(0, 0x08, 0))


# --- comparaison ---------------------------------------------------------------------------------------------------


class Releve:
    """Sorties de llp_trame, cycle par cycle."""

    def __init__(self):
        self.erreurs = []               # (genre, vc), dans l'ordre : fin de paquet long, puis en-tête court
        self.fe = defaultdict(list)     # vc -> [bon, ...]
        self.pertes = Counter()
        self.tardifs = 0
        self.pleins = 0
        self.dernier = None

    def lit(self, s):
        for rang in sorted(range(3), key=lambda r: ERR_END[r]):
            if s["err_end"] >> rang & 1:
                self.erreurs.append((ERR_END[rang], s["err_end_vc"]))
        for rang in sorted(range(7), key=lambda r: ERR_HDR[r]):
            if s["err_hdr"] >> rang & 1:
                self.erreurs.append((ERR_HDR[rang], s["err_hdr_vc"]))
        if s["fe"]:
            self.fe[s["frame_vc"]].append(bool(s["fe_ok"]))
        assert not s["fe_ok"] or s["fe"], "o_fe_ok sans o_fe"
        for rang, genre in enumerate(PERTES):
            self.pertes[genre] += s["loss"] >> rang & 1
        self.tardifs += s["late"]
        self.pleins += s["slots_full"]
        self.dernier = s


if "virtual_channel" not in StreamError.__dataclass_fields__:
    raise RuntimeError("modèle mipi_csi2 antérieur à d738c80 : StreamError sans virtual_channel (oracle de llp_trame)")


def attendu(trames):
    """Erreurs de trame du modèle dans l'ordre des paquets, trames fermées par FE, pertes, tardifs."""
    erreurs, pertes, tardifs = [], set(), set()
    fe = defaultdict(list)
    tolerables = defaultdict(list)
    details = defaultdict(list)
    for trame_recue in trames:
        for erreur in trame_recue.errors:
            vc = trame_recue.virtual_channel if trame_recue.virtual_channel is not None else erreur.virtual_channel
            if erreur.packet_index is None:
                continue                # fin du flux dans une trame : llp_trame ne voit pas de fin de flux
            if erreur.kind in GENRES_TRAME:
                erreurs.append((erreur.packet_index, erreur.kind, vc))
            elif erreur.kind == "burst_error" and "after its packet" in erreur.detail:
                tardifs.add(erreur.packet_index)
            elif erreur.kind in PERTES:
                pertes.add((erreur.packet_index, erreur.kind))
        vc = trame_recue.virtual_channel
        if trame_recue.frame_number is not None and not any(e.kind == "missing_frame_end"
                                                            for e in trame_recue.errors):
            fe[vc].append(trame_recue.ok)
            seules_tardives = all(e.kind == "burst_error" and "after its packet" in e.detail
                                  for e in trame_recue.errors)
            tolerables[vc].append(bool(trame_recue.errors) and seules_tardives)
            details[vc].append([(e.kind, e.packet_index) for e in trame_recue.errors])
    erreurs.sort()
    return erreurs, fe, tolerables, details, Counter(genre for _, genre in pertes), len(tardifs)


async def joue(dut, flux, nom, modele_patch=None):
    """Reset, le flux cycle par cycle, puis comparaison au modèle. Rend le nombre d'écarts tolérés."""
    rng = flux.rng
    front = FallingEdge(dut.clk)
    dut.rst_n.value = 0
    dut.i_beat.value = 0
    dut.i_cnt_clear.value = 0
    for _ in range(3):
        await front
    dut.rst_n.value = 1
    releve = Releve()
    beats = flux.beats + [CYCLE_VIDE] * VIDANGE
    for beat in beats:
        await front
        releve.lit(decoupe(int(dut.o_trame.value)))
        dut.i_beat.value = code_battement(rng, beat)
    modele = [LmBeat(b"") if beat == CYCLE_VIDE else beat for beat in flux.beats]
    trames = receive_stream(modele, framing="sot", max_trail=10**9)
    erreurs, fe, tolerables, details, pertes, tardifs = attendu(trames)

    # erreurs de trame et de ligne, dans l'ordre
    obtenues = releve.erreurs
    for rang, ((index, genre, vc), (genre_rtl, vc_rtl)) in enumerate(zip(erreurs, obtenues)):
        if genre != genre_rtl or (vc is not None and vc != vc_rtl):
            contexte = [f"    {e[1]} vc {e[2]} (paquet {e[0]})" for e in erreurs[max(0, rang - 3):rang + 3]]
            raise AssertionError(f"{nom} : erreur {rang} : RTL {genre_rtl} vc {vc_rtl}, modèle {genre} vc {vc} "
                                 f"(paquet {index})\n  modèle autour :\n" + "\n".join(contexte)
                                 + f"\n  RTL autour : {obtenues[max(0, rang - 3):rang + 3]}")
    assert len(obtenues) == len(erreurs), \
        f"{nom} : {len(obtenues)} erreurs de trame au RTL, {len(erreurs)} au modèle ; " \
        f"en trop : {obtenues[len(erreurs):][:6] or erreurs[len(obtenues):][:6]}"

    # trames fermées par FE, bonnes ou non
    toleres = 0
    for vc in sorted(set(fe) | set(releve.fe)):
        suite_m, suite_r = fe.get(vc, []), releve.fe.get(vc, [])
        assert len(suite_m) == len(suite_r), f"{nom}, VC {vc} : {len(suite_r)} FE au RTL, {len(suite_m)} au modèle"
        for rang, (bon_m, bon_r, tol) in enumerate(zip(suite_m, suite_r, tolerables.get(vc, []))):
            if bon_m != bon_r:
                assert tol and bon_r and not bon_m, f"{nom}, VC {vc}, trame {rang} : RTL bonne={bon_r}, modèle " \
                                                    f"{bon_m}, erreurs du modèle {details[vc][rang]}"
                toleres += 1

    # pertes et tardifs
    assert +releve.pertes == +pertes, f"{nom} : pertes RTL {dict(releve.pertes)}, modèle {dict(pertes)}"
    assert releve.tardifs == tardifs, f"{nom} : {releve.tardifs} burst_error tardifs au RTL, {tardifs} au modèle"

    # compteurs contre les impulsions
    fin = releve.dernier
    nb_ok = sum(bon for suite in releve.fe.values() for bon in suite)
    nb_trame = sum(1 for genre, _ in obtenues if genre not in GENRES_LIGNE)
    nb_ligne = sum(1 for genre, _ in obtenues if genre in GENRES_LIGNE)
    assert (fin["cnt_ok"], fin["cnt_frame"], fin["cnt_line"]) == (nb_ok, nb_trame, nb_ligne), \
        f"{nom} : compteurs {fin['cnt_ok'], fin['cnt_frame'], fin['cnt_line']}, impulsions {nb_ok, nb_trame, nb_ligne}"

    dut._log.info("%s : %d cycles, %d erreurs de trame comparées %s, FE %s, pertes %s, tardifs %d, tolérés %d, "
                  "tables pleines %d", nom, len(beats), len(obtenues), dict(Counter(g for g, _ in obtenues)),
                  {vc: f"{sum(s)}/{len(s)}" for vc, s in sorted(releve.fe.items())}, dict(releve.pertes),
                  releve.tardifs, toleres, releve.pleins)
    return toleres


async def scenario(dut, nom, construit, lanes=(1, 2, 3, 4)):
    Clock(dut.clk, PERIODE_NS, unit="ns").start()
    for nb_lanes in lanes:
        flux = Flux(random.Random(random.getrandbits(64)), nb_lanes)
        flux.parasites()
        construit(flux)
        await joue(dut, flux, f"{nom}, N = {nb_lanes or 'aléatoire'}")


@cocotb.test()
async def test_trames_propres(dut):
    """Trames propres sur deux VC mêlés, LS et LE ou non, lignes 0x12 et user : aucune erreur, toutes bonnes."""
    await scenario(dut, "trames propres", lambda flux: remplit(flux, trames_propres(flux.rng, 30)))


@cocotb.test()
async def test_structure(dut):
    """FS, FE, LS, LE absents, en double ou faux, numéros de trame et de ligne, largeurs, trames vides, hors trame."""
    await scenario(dut, "structure", lambda flux: remplit(flux, trames_defauts(flux.rng, 60, (0, 1, 2, 3))))


@cocotb.test()
async def test_bursts(dut):
    """Trames propres, bursts abîmés : ECC, CRC, rx_out_err, coupes, types réservés, sot_err, battements vides."""
    genres = ("propre",) * 4 + GENRES_ENTETE + GENRES_ERREUR + GENRES_COUPE + ("crc", "type_reserve")

    def construit(flux):
        flux.ecart_max = flux.rng.choice((0, 3, ECART_MAX))
        remplit(flux, trames_propres(flux.rng, 40, (0, 1, 2)), genres, p_sot_err=0.1)
    await scenario(dut, "bursts", construit)


@cocotb.test()
async def test_melange(dut):
    """Défauts de structure et bursts abîmés ensemble, quatre VC."""
    genres = ("propre",) * 6 + GENRES_ENTETE + GENRES_ERREUR + GENRES_COUPE + ("crc", "type_reserve")
    await scenario(dut, "mélange", lambda flux: remplit(flux, trames_defauts(flux.rng, 80, (0, 1, 2, 3)), genres))


@cocotb.test()
async def test_nb_variable(dut):
    """Hors spec : 1 à 4 octets par battement, défauts et bursts abîmés."""
    genres = ("propre",) * 6 + GENRES_ERREUR + GENRES_COUPE + ("crc",)
    await scenario(dut, "nb variable", lambda flux: remplit(flux, trames_defauts(flux.rng, 60), genres), lanes=(None,))


@cocotb.test()
async def test_numeros_de_trame(dut):
    """Numéros de trame aux bornes : 0xFFFF puis 1, remises à 1, sauts, zéros, avec et sans paquets perdus."""
    def construit(flux):
        rng = flux.rng
        paquets = []
        for vc, suite in ((0, [0xFFFD, 0xFFFE, 0xFFFF, 1, 2]), (1, [5, 6, 1, 2, 9, 10]), (2, [0, 0, 0, 3]),
                          (3, [7, 8, 8, 0, 9])):
            for numero in suite:
                paquets += trame(rng, vc, numero, avec_ls=False, embarquees=0)
        genres = ("propre",) * 8 + ("ecc2", "err_milieu", "vide")
        remplit(flux, paquets, genres)
    await scenario(dut, "numéros de trame", construit)


@cocotb.test()
async def test_raz_compteurs(dut):
    """i_cnt_clear remet les trois compteurs à zéro ; ils repartent des impulsions suivantes."""
    Clock(dut.clk, PERIODE_NS, unit="ns").start()
    flux = Flux(random.Random(random.getrandbits(64)), 4)
    flux.parasites()
    remplit(flux, trames_defauts(flux.rng, 20))
    await joue(dut, flux, "avant remise à zéro")
    dut.i_cnt_clear.value = 1
    await FallingEdge(dut.clk)
    dut.i_cnt_clear.value = 0
    await FallingEdge(dut.clk)
    s = decoupe(int(dut.o_trame.value))
    assert (s["cnt_ok"], s["cnt_frame"], s["cnt_line"]) == (0, 0, 0), s
