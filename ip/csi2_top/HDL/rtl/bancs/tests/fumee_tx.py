#!/usr/bin/env python3
"""Fumée TX du csi2_top (29/09/2026) : application -> llp_pix_tx -> llp_top -> LM -> FIFO TX, contre le golden.

L'application émet des trames du golden (mipi_csi2.frame.build_frame : FS, LS, ligne, LE, FE ; RAW8, RAW10, RAW12,
RAW6, RAW14), un paquet brut (DT 0x12, largeur en octets) et une ligne RAW10 de largeur refusée (30 pixels : pas un
multiple de 4, tx_evt_width attendu, aucun paquet). On reconstruit chaque paquet depuis les écritures du LM dans la FIFO
TX (un octet par lane physique de fifo_tx_wlanes, fifo_tx_fin en fin de paquet, N mots d'en-tête de tailles avant les
données : REMISE_TAILLE = 1) et on le compare octet pour octet au paquet du golden (build_short_packet,
build_long_packet). 1, 2 et 4 lanes, avec et sans contre-pression de la FIFO et trous de l'application.

    python3 3_digital/rtl/csi2_top/construit.py
    MIPI_CSI_SRC=<mipi-csi feat/raw12-raw14>/src python3 3_digital/rtl/csi2_top/tests/fumee_tx.py [--sans-campagne]
"""
from __future__ import annotations

import argparse
import json
import os
import random
import subprocess
import sys
from pathlib import Path

ICI = Path(__file__).resolve().parent
TOPD = ICI.parent
SOURCES = TOPD / "sources"
BUILD = TOPD / "build" / "fumee_tx"
DIGITAL = TOPD.parents[1]
sys.path.insert(0, str(DIGITAL / "mesures"))
sys.path.insert(0, os.environ["MIPI_CSI_SRC"])
from mipi_csi2.frame import FrameSpec, build_frame  # noqa: E402
from mipi_csi2.packet import build_long_packet  # noqa: E402
from mipi_csi2.formats import pack  # noqa: E402

DEFINES = ["-DLM_FIFO_ASYNC_P_REMPLACE", "-DLM_FIFO_SYNC_P_REMPLACE"]
BITS = {"RAW6": 6, "RAW8": 8, "RAW10": 10, "RAW12": 12, "RAW14": 14}
PAR_BATTEMENT = {"RAW6": 8}                     # autres : 4 pixels (ou 4 octets en brut) par battement


def compile_tb() -> Path:
    BUILD.mkdir(parents=True, exist_ok=True)
    vvp = BUILD / "tb_tx.vvp"
    fichiers = (SOURCES / "fichiers.f").read_text().split()
    r = subprocess.run(["iverilog", "-g2012", *DEFINES, f"-I{SOURCES / 'llp'}", "-s", "tb_tx", "-o", str(vvp),
                        str(ICI / "tb_tx.v"), *fichiers], capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"iverilog :\n{r.stdout}\n{r.stderr}")
    return vvp


def programme(rng):
    """[(vc, dt, width, [battements (nb, [cases])], paquet attendu ou None)]."""
    p = []
    for fmt, w, h, num, ls in (("RAW8", 40, 2, 1, True), ("RAW10", 32, 2, 2, False), ("RAW12", 34, 2, 3, True),
                               ("RAW6", 36, 1, 4, False), ("RAW14", 16, 2, 5, False)):
        pixels = [[rng.randrange(1 << BITS[fmt]) for _ in range(w)] for _ in range(h)]
        paquets = build_frame(FrameSpec(width=w, height=h, pixel_format=fmt, frame_number=num, line_sync=ls), pixels)
        lignes = iter(pixels)
        for q in paquets:
            dt = q[0] & 0x3F
            if dt < 0x10:
                p.append((0, dt, q[1] | q[2] << 8, [], q))
            else:
                ligne = next(lignes)
                k = PAR_BATTEMENT.get(fmt, 4)
                p.append((0, dt, w, [(len(ligne[i:i + k]), ligne[i:i + k]) for i in range(0, w, k)], q))
    brut = [rng.randrange(256) for _ in range(10)]
    p.append((1, 0x12, 10, [(len(brut[i:i + 4]), brut[i:i + 4]) for i in range(0, 10, 4)],
              build_long_packet(1, 0x12, bytes(brut))))
    refus = [rng.randrange(1024) for _ in range(30)]
    p.append((0, 0x2B, 30, [(len(refus[i:i + 4]), refus[i:i + 4]) for i in range(0, 30, 4)], None))
    ligne = [rng.randrange(1024) for _ in range(8)]      # après le refus, une ligne juste : la file est propre
    p.append((0, 0x2B, 8, [(4, ligne[:4]), (4, ligne[4:])], build_long_packet(0, 0x2B, pack("RAW10", ligne))))
    return p


def cas(nom, vvp, graine, masque, plein=0, trou=0):
    rng = random.Random(graine)
    prog = programme(rng)
    req, pix = BUILD / f"{nom}.req", BUILD / f"{nom}.pix"
    req.write_text("".join(f"{(vc << 22) | (dt << 16) | w:06x}\n" for vc, dt, w, _, _ in prog))
    battements = [(nb, cases) for *_, bt, _ in prog for nb, cases in bt]
    pix.write_text("".join(f"{nb:01x}{sum(c << (14 * j) for j, c in enumerate(cases)):028x}\n"
                           for nb, cases in battements))
    sortie = BUILD / f"{nom}.sortie"
    r = subprocess.run(["vvp", "-n", str(vvp), f"+MASQUE={masque:x}", f"+REQ={req}", f"+PIX={pix}",
                        f"+NREQ={len(prog)}", f"+NPIX={len(battements)}", f"+SORTIE={sortie}", f"+PLEIN={plein}",
                        f"+TROU={trou}", f"+GRAINE={graine}"], capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"vvp {nom} : {r.stdout[-500:]} {r.stderr[-500:]}")
    lanes = [l for l in range(4) if masque >> l & 1]
    n = len(lanes)
    paquets, courant, entete, entetes, ecarts, evt_w, evt_nb = [], [], [], [], [], 0, 0
    for ligne in sortie.read_text().splitlines():
        c = ligne.split()
        if c[0] == "W":
            wdata, wl, fin = int(c[2], 16), int(c[3], 16), int(c[4])
            if len(entete) < n:
                entete.append(wdata)
                if len(entete) == n:
                    entetes.append(entete)
                continue
            courant += [(wdata >> (8 * l)) & 0xFF for l in range(4) if wl >> l & 1]
            if fin:
                paquets.append(bytes(courant))
                courant, entete = [], []
        elif c[0] == "Y":
            evt_w += int(c[2])
            evt_nb += int(c[3])
    attendus = [q for *_, q in prog if q is not None]
    if "délai dépassé" in r.stdout:
        ecarts.append("délai dépassé")
    if len(paquets) != len(attendus):
        ecarts.append(f"{len(paquets)} paquets écrits pour {len(attendus)} attendus")
    faux = [i for i, (a, b) in enumerate(zip(attendus, paquets)) if a != b]
    if faux:
        ecarts.append(f"paquets faux : {faux[:5]}")
    for i, (a, e) in enumerate(zip(attendus, entetes)):
        par = [len(a) // n + (1 if k < len(a) % n else 0) for k in range(n)]
        if e != [(p << 30) | par[k] for k, p in enumerate(lanes)]:
            ecarts.append(f"paquet {i} : en-tête de tailles faux")
            break
    if evt_w != 1 or evt_nb:
        ecarts.append(f"tx_evt_width {evt_w} (attendu 1), tx_evt_nb {evt_nb} (attendu 0)")
    return dict(cas=nom, lanes="".join(map(str, lanes)), fifo_pleine_pct=plein, trous_appli_pct=trou,
                requetes=len(prog), paquets_attendus=len(attendus), paquets_ecrits=len(paquets),
                octets=sum(len(a) for a in attendus), evt_width=evt_w, ecarts=len(ecarts),
                verdict="ok" if not ecarts else "ÉCHEC", detail=" ; ".join(ecarts)[:400]), sortie


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sans-campagne", action="store_true")
    a = ap.parse_args()
    vvp = compile_tb()
    lignes = [cas(*x) for x in (("tx_4l", vvp, 21, 0xF), ("tx_4l_contre_pression", vvp, 22, 0xF, 30, 20),
                                ("tx_2l", vvp, 23, 0x3), ("tx_1l_lane3", vvp, 24, 0x8, 10, 10))]
    for l, _ in lignes:
        print(l, flush=True)
    ok = all(l["verdict"] == "ok" for l, _ in lignes)
    if not a.sans_campagne:
        from campagne import Campagne
        m = json.loads((SOURCES / "manifeste.json").read_text())
        c = Campagne("iverilog", "csi2_top, fumée TX : application pixels -> llp_pix_tx -> llp_top -> LM -> FIFO TX, "
                     "contre les paquets du golden, 1, 2 et 4 lanes", outils=["iverilog"], suffixe="csi2_top_fumee_tx",
                     versions={"LM": m["lcr"], "LLP": m["llp"]})
        for l, s in lignes:
            c.ligne(**l)
            c.garde(s, f"sorties/{s.name}")
        print("campagne :", c.ferme(f"{sum(l['verdict'] == 'ok' for l, _ in lignes)} cas sur {len(lignes)} justes"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
