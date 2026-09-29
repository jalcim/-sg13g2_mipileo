#!/usr/bin/env python3
"""Bout en bout RX du csi2_top contre le golden mipi_csi2 (29/09/2026).

Chaîne : trames fabriquées par le golden (mipi_csi2.frame.build_frame : FS, [LS], ligne, [LE], …, FE), erreurs
injectées sur les paquets, un paquet par burst -> modèle PHY D-PHY indépendant (modele_phy_dphy.py de
lm-corrections-revue, bit par bit, 1, 2 ou 4 lanes) -> csi2_top (LM + LLP + llp_pix_rx + llp_trame) -> sorties
d'application. Oracle : mipi_csi2.rx.receive_frames sur les mêmes paquets (tête feat/raw12-raw14 d829010 : RAW12, RAW14).

Jugé, trame par trame (VC, numéro) :
- ordre et numéros des trames (trame_fs, trame_fe), trame_fe_ok contre ReceivedFrame.ok ;
- pixels : les lignes livrées entières (rx_eol_status 0, et 1 : CRC faux, gardée par le golden avec l'erreur) de chaque trame, par type de données, contre ReceivedFrame.images ;
- codes d'erreur : ensemble des genres d'erreur de la trame (golden : StreamError.kind) contre ceux que le top
  signale sur ses ports (rx_eol_status 1, 2, 4 ; trame_err_hdr, trame_err_end, trame_loss par VC ; type réservé :
  o_rx_evt_dt et son VC, lu dans le top) ;
- ECC corrigée : nombre d'événements ecc_corrected du golden contre rx_sol/short_ecc_corrected ;
- compteurs : llp_cnt_* (paquets bons, ECC corrigée, ECC double, CRC, troncatures, types réservés, 0 burst, 0 sot_err),
  trame_cnt_ok, dbg_evt (une impulsion par événement de llp_rx attendu), dbg_erreur (0 après le premier en-tête) ;
- aucune trame du golden « hors trame » (entrée de numéro None) : les cas n'en fabriquent pas.
Témoins négatifs (--mutants) : câblage du top faussé (pixels, trame, fin de paquet), qui doit être refusé.

    python3 3_digital/rtl/csi2_top/construit.py
    MIPI_CSI_SRC=<mipi-csi feat/raw12-raw14>/src python3 3_digital/rtl/csi2_top/tests/bout_en_bout.py [--mutants]
        [--sans-campagne] [--cas MOTIF]
"""
from __future__ import annotations

import argparse
import json
import os
import random
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

ICI = Path(__file__).resolve().parent
TOPD = ICI.parent
SOURCES = TOPD / "sources"
BUILD = TOPD / "build" / "bout_en_bout"
DIGITAL = TOPD.parents[1]
sys.path.insert(0, str(SOURCES / "modeles"))
sys.path.insert(0, str(DIGITAL / "mesures"))
if "MIPI_CSI_SRC" not in os.environ:
    sys.exit("MIPI_CSI_SRC : dossier src/ de mipi-csi (feat/raw12-raw14 d829010 ou plus récent)")
sys.path.insert(0, os.environ["MIPI_CSI_SRC"])
import modele_phy_dphy as P  # noqa: E402
from mipi_csi2.frame import FrameSpec, build_frame  # noqa: E402
from mipi_csi2.packet import build_long_packet, build_short_packet  # noqa: E402
from mipi_csi2.rx import parse_packet, receive_frames  # noqa: E402
from mipi_csi2.formats import unpack  # noqa: E402,F401  (présence de RAW12/RAW14 vérifiée plus bas)

DEFINES = ["-DLM_FIFO_ASYNC_P_REMPLACE", "-DLM_FIFO_SYNC_P_REMPLACE"]
TS_PS = 7992
BITS_PIX = {"RAW6": 6, "RAW8": 8, "RAW10": 10, "RAW12": 12, "RAW14": 14}

# Mutants du câblage du top (le banc doit les refuser)
MUTANTS = [
    ("pix_nb_fixe", ".o_pix_nb               (rx_pix_nb)", ".o_pix_nb               ()"),
    ("fin_pix_sur_statut_0", ".i_end_status           (end_status),\n        .o_sol ",
     ".i_end_status           (2'd0),\n        .o_sol "),
    ("trame_sans_evt_ecc", ".i_evt_ecc              (evt_ecc)", ".i_evt_ecc              (1'b0)"),
    ("trame_vc_force_0", ".i_hdr_vc               (hdr_vc),\n        .i_hdr_dt               (hdr_dt),\n"
     "        .i_hdr_wc               (hdr_wc),\n        .i_hdr_short            (hdr_short),\n        .i_end_valid",
     ".i_hdr_vc               (2'd0),\n        .i_hdr_dt               (hdr_dt),\n"
     "        .i_hdr_wc               (hdr_wc),\n        .i_hdr_short            (hdr_short),\n        .i_end_valid"),
]


def compile_tb(mutant=None) -> Path:
    BUILD.mkdir(parents=True, exist_ok=True)
    vvp = BUILD / f"tb_rx{'_' + mutant[0] if mutant else ''}.vvp"
    fichiers = (SOURCES / "fichiers.f").read_text().split()
    if mutant:
        texte = Path(fichiers[0]).read_text()
        assert texte.count(mutant[1]) == 1, mutant[0]
        copie = BUILD / f"csi2_top_{mutant[0]}.v"
        copie.write_text(texte.replace(mutant[1], mutant[2]))
        fichiers[0] = str(copie)
    r = subprocess.run(["iverilog", "-g2012", *DEFINES, f"-I{SOURCES / 'llp'}", "-s", "tb_rx", "-o", str(vvp),
                        str(ICI / "tb_rx.v"), *fichiers], capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"iverilog :\n{r.stdout}\n{r.stderr}")
    return vvp


# ------------------------------------------------------------------------------------------------ scénarios
def pixels(rng, fmt, w, h):
    m = (1 << BITS_PIX[fmt]) - 1
    return [[rng.randrange(m + 1) for _ in range(w)] for _ in range(h)]


def trame(rng, fmt, w, h, num, vc=0, ls=False):
    return build_frame(FrameSpec(width=w, height=h, pixel_format=fmt, frame_number=num, virtual_channel=vc,
                                 line_sync=ls), pixels(rng, fmt, w, h))


def est_ligne(p: bytes) -> bool:
    return (p[0] & 0x3F) >= 0x10


def lignes_de(paquets):
    return [i for i, p in enumerate(paquets) if est_ligne(p)]


def flip(p: bytes, bits) -> bytes:
    b = bytearray(p)
    for k in bits:
        b[k // 8] ^= 1 << (k % 8)
    return bytes(b)


def ecc2(rng, p):
    while True:
        a, b = rng.sample(range(24), 2)
        q = flip(p, [a, b])
        if not parse_packet(q).header_ok:
            return q


def scenarios(rng):
    """{nom : (lanes, débit par lane, horloge continue, paquets, injections)} ; injections : genres injectés."""
    s = {}
    s["raw8_4l_1000"] = ((0, 1, 2, 3), 1000.0, True,
                         trame(rng, "RAW8", 40, 4, 1) + trame(rng, "RAW8", 40, 4, 2, ls=True), [])
    s["raw10_2l_728_nc"] = ((0, 1), 728.0, False,
                            trame(rng, "RAW10", 32, 4, 1, ls=True) + trame(rng, "RAW10", 32, 3, 2), [])
    s["raw12_1l_1000"] = ((2,), 1000.0, True, trame(rng, "RAW12", 32, 3, 1) + trame(rng, "RAW12", 34, 2, 2), [])
    s["raw6_raw14_4l"] = ((0, 1, 2, 3), 912.0, True,
                          trame(rng, "RAW6", 32, 2, 1) + trame(rng, "RAW14", 16, 3, 2, ls=True), [])
    # deux VC entrelacés (VC0 RAW10, VC2 RAW8), 4 lanes
    a, b = trame(rng, "RAW10", 16, 3, 1, vc=0), trame(rng, "RAW8", 24, 3, 7, vc=2)
    s["vc_entrelaces_4l"] = ((0, 1, 2, 3), 1000.0, True, [x for pair in zip(a, b) for x in pair] + a[len(b):]
                             + b[len(a):], [])
    # erreurs injectées, une trame chacune (4 lanes, 1 000 Mb/s par lane)
    f1 = trame(rng, "RAW10", 32, 4, 1)          # ECC corrigée sur l'en-tête d'une ligne : trame bonne
    i = lignes_de(f1)[1]
    f1[i] = flip(f1[i], [rng.randrange(24)])
    f2 = trame(rng, "RAW10", 32, 4, 2)          # CRC faux sur une ligne
    i = lignes_de(f2)[2]
    b_ = bytearray(f2[i]); b_[10] ^= 0x21; f2[i] = bytes(b_)
    f3 = trame(rng, "RAW10", 32, 4, 3)          # ECC double sur l'en-tête d'une ligne : paquet perdu
    i = lignes_de(f3)[0]
    f3[i] = ecc2(rng, f3[i])
    # ligne tronquée : burst coupé au milieu de la charge ; ligne longue (200 octets) pour que le trail et le bruit
    # d'après le burst (livrés par le LM jusqu'au sot suivant) ne complètent pas le WC : sinon le LLP voit un CRC faux
    f4 = trame(rng, "RAW10", 160, 4, 4)
    i = lignes_de(f4)[3]
    f4[i] = f4[i][:4 + 17]
    f5 = trame(rng, "RAW8", 40, 3, 5)           # type réservé 0x2E (paquet long) au milieu de la trame
    f5.insert(2, build_long_packet(0, 0x2E, bytes(rng.randrange(256) for _ in range(12))))
    f6 = trame(rng, "RAW8", 40, 2, 6)[:-1]      # FE perdu : le FS suivant ferme la trame (missing_frame_end)
    f7 = trame(rng, "RAW12", 16, 2, 7)          # taille hors groupe : ligne RAW12 de WC impair (payload_size)
    i = lignes_de(f7)[1]
    f7[i] = build_long_packet(0, 0x2C, bytes(rng.randrange(256) for _ in range(25)))
    s["erreurs_4l"] = ((0, 1, 2, 3), 1000.0, True, f1 + f2 + f3 + f4 + f5 + f6 + f7,
                       ["ecc1", "crc", "ecc2", "tronque", "dt_reserve", "fe_perdu", "taille"])
    # mêmes erreurs à 1 lane et à 2 lanes (bancs 1/2/4 lanes)
    s["erreurs_2l_nc"] = ((1, 3), 728.0, False, f1 + f2 + f3 + f4, ["ecc1", "crc", "ecc2", "tronque"])
    s["erreurs_1l"] = ((0,), 1000.0, True, f2 + f3 + f5, ["crc", "ecc2", "dt_reserve"])
    return s


# ------------------------------------------------------------------------------------------------ attendu (golden)
def attendu(paquets):
    fr = receive_frames(paquets)
    trames = [f for f in fr if not f.is_stream_level]
    hors = [f for f in fr if f.is_stream_level]
    res = []
    for f in trames:
        res.append(dict(vc=f.virtual_channel, num=f.frame_number, ok=f.ok,
                        images={dt: [list(l) for l in ls] for dt, ls in f.images.items()},
                        genres=sorted({e.kind for e in f.errors}),
                        corriges=sum(e.kind == "ecc_corrected" for e in f.events)))
    return res, hors


# ------------------------------------------------------------------------------------------------ lu (top)
ERR_HDR = ["missing_frame_end", "missing_frame_start", "frame_number_sequence", "frame_number_mismatch",
           "empty_frame", "line_sync_mismatch", "line_number_sequence"]
ERR_END = ["missing_frame_start", "line_number_sequence", "line_length_mismatch"]
LOSS = ["short_burst", "ecc_uncorrectable", "burst_error"]
EOL = {1: "crc_mismatch", 2: "truncated", 4: "payload_size"}


def lit(sortie: Path):
    """Trames reconstruites depuis les ports du top ; ordre dans un cycle : fins de ligne et erreurs, missing_frame_end
    (trame ancienne), FE, FS, frame_number_sequence (trame nouvelle)."""
    par_t = defaultdict(list)
    fin = None
    illisibles = []
    for ligne in sortie.read_text().splitlines():
        c = ligne.split()
        if any(ch in x.lower() for x in c[1:] for ch in "xz"):    # x ou z sur une sortie : illisible, compté
            illisibles.append(ligne[:80])
            continue
        if c[0] == "K":
            fin = [int(x, 16) if i == 11 else int(x) for i, x in enumerate(c[1:])]
        else:
            par_t[int(c[1])].append(c)
    ouvertes, trames, hors = {}, [], []
    ligne_c = None
    stats = Counter()
    premier_h = None

    def charge(vc, genre):
        (ouvertes[vc]["genres"] if vc in ouvertes else hors).append(genre)

    for t in sorted(par_t):
        ev = par_t[t]
        for c in ev:                              # pixels, lignes, paquets courts, en-têtes, débogage
            k = c[0]
            if k == "H" and premier_h is None:
                premier_h = t
            if k == "S":
                ligne_c = dict(vc=int(c[2]), dt=int(c[3], 16), fmt=int(c[5]), pix=[], corrige=int(c[6]))
            elif k == "X" and ligne_c is not None:
                nb, d = int(c[2]), int(c[3], 16)
                ligne_c["pix"] += [(d >> (14 * j)) & 0x3FFF for j in range(nb)]
            elif k == "L" and ligne_c is not None:
                st = int(c[2])
                vc = ligne_c["vc"]
                if ligne_c["corrige"] and vc in ouvertes:
                    ouvertes[vc]["corriges"] += 1
                # une ligne au CRC faux sort entière (état 1) : le golden la garde aussi dans images, avec l'erreur
                if st in (0, 1) and vc in ouvertes:
                    ouvertes[vc]["images"].setdefault(ligne_c["dt"], []).append(ligne_c["pix"])
                if st in EOL:
                    charge(vc, EOL[st])
                ligne_c = None
            elif k == "C" and int(c[5]) and int(c[2]) in ouvertes:
                ouvertes[int(c[2])]["corriges"] += 1
            elif k == "R":
                charge(int(c[2]), "unknown_data_type")
            elif k == "D":
                if premier_h is not None and int(c[2]):
                    stats["dbg_erreur"] += 1
                stats["dbg_evt"] += int(c[3])
        for c in ev:                              # erreurs de trame (sauf frame_number_sequence)
            if c[0] != "T":
                continue
            eh, ehv, ee, eev, lo, lom = int(c[2], 16), int(c[3]), int(c[4], 16), int(c[5]), int(c[6], 16), int(c[7], 16)
            for j, g in enumerate(ERR_HDR):
                if eh >> j & 1 and j != 2:
                    charge(ehv, g)
            for j, g in enumerate(ERR_END):
                if ee >> j & 1:
                    charge(eev, g)
            for j, g in enumerate(LOSS):
                if lo >> j & 1:
                    touche = [v for v in range(4) if lom >> v & 1]
                    for v in touche:
                        charge(v, g)
                    if not touche:
                        hors.append(g)
            if int(c[8]):
                stats["late"] += 1
            if eh & 1 and ehv in ouvertes:         # missing_frame_end : trame ancienne fermée, fausse
                o = ouvertes.pop(ehv)
                o["ok"] = False
                trames.append(o)
        for c in ev:
            if c[0] == "G":
                vc, num, ok = int(c[2]), int(c[3]), int(c[4])
                o = ouvertes.pop(vc, None)
                if o is None:
                    hors.append(f"FE sans trame ouverte (VC {vc})")
                    continue
                if o["num"] != num:
                    o["genres"].append(f"numéro de FE {num} pour FS {o['num']}")
                o["ok"] = bool(ok)
                trames.append(o)
        for c in ev:
            if c[0] == "F":
                vc, num = int(c[2]), int(c[3])
                if vc in ouvertes:                # FS sans missing_frame_end signalé : écart
                    o = ouvertes.pop(vc)
                    o["ok"] = None
                    trames.append(o)
                ouvertes[vc] = dict(vc=vc, num=num, ok=None, images={}, genres=[], corriges=0, t=t)
        for c in ev:
            if c[0] == "T" and int(c[2], 16) >> 2 & 1:
                charge(int(c[3]), "frame_number_sequence")
    for o in ouvertes.values():
        o["ok"] = None
        trames.append(o)
    trames.sort(key=lambda o: o["t"])
    for o in trames:
        o["genres"] = sorted(set(o["genres"]))
    if illisibles:
        hors.append(f"{len(illisibles)} lignes de sortie avec x ou z : {illisibles[:2]}")
    return trames, hors, fin, stats


def compteurs_attendus(paquets):
    n = Counter()
    for p in paquets:
        if len(p) < 4:
            n["trunc"] += 1
            continue
        q = parse_packet(p)
        if not q.header_ok:
            n["ecc_double"] += 1
            continue
        if q.ecc.status.name == "CORRECTED":
            n["ecc_corrected"] += 1
        dt = q.data_type
        reserve = dt in (0x04, 0x05, 0x06, 0x07, 0x13, 0x14, 0x15, 0x16, 0x17, 0x1B, 0x25, 0x26, 0x27, 0x2E, 0x2F) \
            or 0x38 <= dt <= 0x3F
        if reserve:
            n["dt"] += 1
            if q.ecc.status.name == "CORRECTED":
                n["ecc_corrected"] -= 1       # un réservé corrigé n'est pas publié (README)
            continue
        if q.is_short:
            n["ok"] += 1
        elif len(p) < 4 + q.word_count + 2:
            n["trunc"] += 1
        elif q.crc_ok:
            n["ok"] += 1
        else:
            n["crc"] += 1
    return n


def cas(nom, vvp, graine, lanes, debit, continue_, paquets, injections):
    rng = random.Random(graine)
    mod = P.Modele(charges=[list(p) for p in paquets], lanes=lanes, debit=debit, continue_=continue_, graine=graine)
    mod.construit()
    ev = mod.evenements()
    stim, sortie = BUILD / f"{nom}.stim", BUILD / f"{nom}.sortie"
    with open(stim, "w") as f:
        for (t, ty, v) in ev:
            f.write(f"{t} {ty} {v:x}\n")
        f.write(f"{ev[-1][0] + 1000} 9 0\n")
    masque = sum(1 << l for l in lanes)
    r = subprocess.run(["vvp", "-n", str(vvp), f"+TS={TS_PS}", f"+PHASE={rng.randrange(TS_PS)}", f"+MASQUE={masque:x}",
                        f"+STIM={stim}", f"+SORTIE={sortie}"], capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"vvp {nom} : {r.stdout[-500:]} {r.stderr[-500:]}")
    att, att_hors = attendu(paquets)
    lu, hors, fin, stats = lit(sortie)
    ecarts = []
    if att_hors:
        ecarts.append(f"golden : erreurs hors trame {[e.kind for f in att_hors for e in f.errors]}")
    if hors:
        ecarts.append(f"top : erreurs hors trame {hors}")
    if [(a["vc"], a["num"]) for a in att] != [(o["vc"], o["num"]) for o in lu]:
        ecarts.append(f"trames {[(o['vc'], o['num']) for o in lu]} au lieu de {[(a['vc'], a['num']) for a in att]}")
    lignes_ok = 0
    for a, o in zip(att, lu):
        tag = f"trame VC{a['vc']} n°{a['num']}"
        if o["ok"] != a["ok"]:
            ecarts.append(f"{tag} : fe_ok {o['ok']} au lieu de {a['ok']}")
        if o["genres"] != a["genres"]:
            ecarts.append(f"{tag} : erreurs {o['genres']} au lieu de {a['genres']}")
        if o["images"] != a["images"]:
            ecarts.append(f"{tag} : pixels différents ({ {k: len(v) for k, v in o['images'].items()} } lignes pour "
                          f"{ {k: len(v) for k, v in a['images'].items()} })")
        if o["corriges"] != a["corriges"]:
            ecarts.append(f"{tag} : {o['corriges']} ECC corrigées au lieu de {a['corriges']}")
        lignes_ok += sum(len(v) for v in a["images"].values())
    n = compteurs_attendus(paquets)
    k = dict(zip(("ok", "ecc_corrected", "ecc_double", "crc", "trunc", "burst", "dt", "sot_err", "trame_ok",
                  "trame_err", "trame_ligne", "verrou", "erreur_fifo"), fin or [-1] * 13))
    voulu = dict(ok=n["ok"], ecc_corrected=n["ecc_corrected"], ecc_double=n["ecc_double"], crc=n["crc"],
                 trunc=n["trunc"], burst=0, dt=n["dt"], sot_err=0, trame_ok=sum(a["ok"] for a in att), erreur_fifo=0)
    for c_, v in voulu.items():
        if k[c_] != v:
            ecarts.append(f"compteur {c_} = {k[c_]} au lieu de {v}")
    evt = n["ecc_double"] + n["dt"]
    if stats["dbg_evt"] != evt:
        ecarts.append(f"dbg_evt : {stats['dbg_evt']} impulsions au lieu de {evt}")
    if stats["dbg_erreur"]:
        ecarts.append(f"dbg_erreur : {stats['dbg_erreur']} impulsions après le premier en-tête")
    return dict(cas=nom, lanes="".join(map(str, lanes)), debit_mbps_par_lane=debit, horloge_continue=continue_,
                paquets=len(paquets), trames=len(att), trames_bonnes=sum(a["ok"] for a in att), lignes_jugees=lignes_ok,
                erreurs_injectees=" ".join(injections), genres_golden=" ".join(sorted({g for a in att
                                                                                        for g in a["genres"]})),
                compteurs=" ".join(f"{c_}={k[c_]}" for c_ in voulu), ecarts=len(ecarts),
                verdict="ok" if not ecarts else "ÉCHEC", detail=" ; ".join(ecarts)[:600]), sortie


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mutants", action="store_true")
    ap.add_argument("--sans-campagne", action="store_true")
    ap.add_argument("--cas", default="")
    a = ap.parse_args()
    if not (SOURCES / "fichiers.f").exists():
        sys.exit("sources absentes : lancer d'abord construit.py")
    from mipi_csi2 import formats
    assert "RAW12" in formats.PACKERS and "RAW14" in formats.PACKERS, "golden sans RAW12/RAW14 : feat/raw12-raw14"
    sc = scenarios(random.Random(2026))
    vvp = compile_tb()
    lignes = []
    for g, (nom, (lanes, debit, cont, paquets, inj)) in enumerate(sc.items(), start=1):
        if a.cas not in nom:
            continue
        l, s = cas(nom, vvp, g, lanes, debit, cont, paquets, inj)
        lignes.append((l, s))
        print({x: l[x] for x in ("cas", "trames", "trames_bonnes", "lignes_jugees", "verdict", "detail")}, flush=True)
    mutants = []
    if a.mutants:
        for m in MUTANTS:
            v = compile_tb(m)
            refus = 0
            for g, (nom, (lanes, debit, cont, paquets, inj)) in enumerate(sc.items(), start=1):
                if nom not in ("raw10_2l_728_nc", "erreurs_4l", "vc_entrelaces_4l"):
                    continue
                l, _ = cas(f"{nom}_{m[0]}", v, g, lanes, debit, cont, paquets, inj)
                refus += l["verdict"] != "ok"
            mutants.append(dict(cas=f"mutant {m[0]}", detail=f"{m[1][:60]} -> {m[2][:60]}", ecarts=refus,
                                verdict="refusé" if refus else "NON REFUSÉ"))
            print(mutants[-1], flush=True)
    ok = all(l["verdict"] == "ok" for l, _ in lignes) and all(m["verdict"] == "refusé" for m in mutants)
    print(f"bout en bout : {sum(l['verdict'] == 'ok' for l, _ in lignes)}/{len(lignes)} cas justes ; "
          f"{sum(m['verdict'] == 'refusé' for m in mutants)}/{len(mutants)} mutants refusés")
    if not a.sans_campagne:
        from campagne import Campagne
        m = json.loads((SOURCES / "manifeste.json").read_text())
        mc = subprocess.run(["git", "-C", os.environ["MIPI_CSI_SRC"], "rev-parse", "--short", "HEAD"],
                            capture_output=True, text=True).stdout.strip() or "hors git (archive)"
        c = Campagne("iverilog", "csi2_top de bout en bout RX contre le golden mipi_csi2 (trames RAW6 à RAW14, FS/FE/LS/LE, "
                     "2 VC, erreurs ECC, CRC, tronquée, type réservé, FE perdu, taille ; 1, 2, 4 lanes)",
                     outils=["iverilog"], suffixe="csi2_top_bout_en_bout",
                     versions={"LM": m["lcr"], "LLP": m["llp"], "mipi_csi": mc})
        for l, s in lignes:
            c.ligne(**l)
            c.garde(s, f"sorties/{s.name}")
        for x in mutants:
            c.ligne(**x)
        c.garde(SOURCES / "manifeste.json")
        print("campagne :", c.ferme(f"{sum(l['verdict'] == 'ok' for l, _ in lignes)} cas sur {len(lignes)} justes ; "
                                    f"{sum(x['verdict'] == 'refusé' for x in mutants)} mutants sur {len(mutants)} refusés"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
