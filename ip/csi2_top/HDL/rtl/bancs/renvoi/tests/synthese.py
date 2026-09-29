#!/usr/bin/env python3
"""Synthèse locale et STA avant placement du csi2_top --renvoi (prompt 056, étape 4), avec le csi2_top sans renvoi en
témoin.

Flot de rtl/integration/synthese_integration.py (yosys_local de rtl/synthese/compare_ldf_p.py : ABC « DELAY 4 »,
sg13g2_buf_4, Liberty typique ; puis OpenSTA aux trois coins de LibreLane pour ihp-sg13g2, horloges idéales, resets et
recovery écartés), fonction sta() reprise telle quelle. SDC : csi2_top.sdc (témoin), sources/csi2_top_renvoi.sdc
(renvoi_mode en faux chemin comme enable). Période 7,992 ns ; OCV ±5 % (SDC) puis ±10 %.
Chemins relevés en plus : pire chemin vers les bascules du renvoi (u_renvoi.*) et depuis elles.
Blocs : csi2_top (témoin) ; csi2_top --renvoi, paramètres par défaut (E_CRC, STATUT) ; RENVOI_ERREUR = 1 (E_SUP) ;
RENVOI_STATUT = 0 ; le module renvoi seul (surface).

    python3 3_digital/rtl/csi2_top/construit.py --renvoi
    PDK_ROOT=<dossier contenant ihp-sg13g2> python3 3_digital/rtl/csi2_top/renvoi/tests/synthese.py --sta <OpenSTA>
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path

ICI = Path(__file__).resolve().parent
RENVOI = ICI.parent
TOPD = RENVOI.parent
SOURCES = TOPD / "sources"
BUILD = TOPD / "build" / "renvoi_synthese"
DIGITAL = TOPD.parents[1]
sys.path.insert(0, str(DIGITAL / "rtl" / "integration"))
sys.path.insert(0, str(DIGITAL / "rtl" / "synthese"))
sys.path.insert(0, str(DIGITAL / "mesures"))
import synthese_integration as S  # noqa: E402
import compare_ldf_p as C  # noqa: E402
from synthese import COINS  # noqa: E402

RV_Q = re.compile(r"^u_renvoi\.")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sta", default=os.environ.get("STA", "sta"))
    ap.add_argument("--sans-campagne", action="store_true")
    ap.add_argument("--prof", type=int, default=None, help="RENVOI_PROF (défaut : celui du top)")
    a = ap.parse_args()
    m = json.loads((SOURCES / "manifeste.json").read_text())
    f = (SOURCES / "fichiers.f").read_text().split()
    if not f[0].endswith("csi2_top_renvoi.v"):
        sys.exit("construit.py --renvoi d'abord")
    renvoi = [x for x in f if Path(x).parent == RENVOI]
    commun = [x for x in f[1:] if x not in renvoi]
    racine = Path(os.environ["PDK_ROOT"]) / "ihp-sg13g2" / "libs.ref" / "sg13g2_stdcell" / "lib"
    libs = {coin.split()[0]: racine / fl for coin, fl in COINS.items()}
    typ = libs["typ"]
    prof = {"RENVOI_PROF": a.prof} if a.prof else {}
    blocs = [  # (nom, sources, top, paramètres, SDC)
        ("csi2_top (témoin, sans renvoi)", [str(TOPD / "csi2_top.v")] + commun, "csi2_top", {}, TOPD / "csi2_top.sdc"),
        ("csi2_top --renvoi (E_CRC, STATUT)", [f[0]] + commun + renvoi, "csi2_top", dict(prof),
         SOURCES / "csi2_top_renvoi.sdc"),
        ("csi2_top --renvoi E_SUP", [f[0]] + commun + renvoi, "csi2_top", {"RENVOI_ERREUR": 1, **prof},
         SOURCES / "csi2_top_renvoi.sdc"),
        ("csi2_top --renvoi sans STATUT", [f[0]] + commun + renvoi, "csi2_top", {"RENVOI_STATUT": 0, **prof},
         SOURCES / "csi2_top_renvoi.sdc"),
        ("renvoi seul", [str(SOURCES / "llp" / x) for x in ("llp_ecc.v", "llp_crc.v")] + renvoi, "renvoi",
         {"PROF": a.prof} if a.prof else {}, None),
    ]
    lignes, gardes = [], []
    for nom, sources, top, par, sdc in blocs:
        sortie = BUILD / re.sub(r"[^a-z0-9]+", "_", nom.lower()).strip("_")
        sortie.mkdir(parents=True, exist_ok=True)
        cwd = os.getcwd()
        os.chdir(SOURCES / "llp")                           # `include "llp_pix_regles.vh"
        try:
            surface, cellules, bascules = C.yosys_local(typ, sortie, sources, top, par, m["defines"], S.PERIODE)
        finally:
            os.chdir(cwd)
        netlist = sortie / "netlist.v"
        md5 = hashlib.md5(netlist.read_bytes()).hexdigest()
        q = C.bascules_par_q(netlist)
        rv = {i: n for i, n in q.items() if RV_Q.match(n)}
        ligne = dict(bloc=nom, parametres=" ".join(f"{k}={v}" for k, v in par.items()), surface_um2=round(surface, 1),
                     cellules=cellules, bascules=bascules, bascules_renvoi=len(rv) if top == "csi2_top" else "",
                     md5_netlist=md5[:8])
        gardes.append((sortie / "stat.txt", f"{sortie.name}/stat.txt"))
        if sdc:
            ligne["bits_de_ports"] = S.bits_de_ports(netlist)
            d = " ".join(f"{i}/D" for i in sorted(rv))
            ck = " ".join(f"{i}/CLK" for i in sorted(rv))
            for derate in S.DERATES:
                for coin, lib in libs.items():
                    res, fichiers = S.sta(a.sta, lib, sortie, coin, sdc, top, derate, d, ck, q)
                    l2 = dict(ligne, coin=coin, ocv=derate, setup_ns=res["setup"], hold_ns=res["hold"],
                              pire_chemin=res.get("setup_chemin", ""), setup_par_groupe=res.get("groupes", ""),
                              vers_renvoi=res.get("vers_llp_chemin", ""), depuis_renvoi=res.get("depuis_llp_chemin", ""))
                    if coin == "slow":
                        l2["seuil_1598"] = "tenu" if res["setup"] >= S.SEUIL else "NON TENU"
                    lignes.append(l2)
                    print({k: l2[k] for k in ("bloc", "coin", "ocv", "setup_ns", "hold_ns", "vers_renvoi",
                                              "depuis_renvoi")}, flush=True)
                    gardes += [(fl, f"{sortie.name}/{fl.name}") for fl in fichiers]
        else:
            lignes.append(ligne)
            print(ligne, flush=True)
        netlist.rename(sortie / "netlist.v.garde")
    if a.sans_campagne:
        return
    from campagne import Campagne
    c = Campagne("opensta", "csi2_top --renvoi (prompt 056) contre csi2_top : synthèse locale, surface, bascules, STA "
                 "avant placement à 7,992 ns, 3 coins, OCV ±5 % et ±10 %, chemins vers et depuis le renvoi",
                 outils=["yosys", "sta"], suffixe="renvoi_synthese",
                 versions={"pdk": str(racine), "LM": m["lcr"], "LLP": m["llp"], "renvoi": json.dumps(m["renvoi"])})
    for l in lignes:
        c.ligne(**l)
    for fl, n in gardes:
        c.garde(fl, n)
    c.garde(SOURCES / "manifeste.json")
    c.garde(Path(__file__))
    c.note("Flot local de synthese_integration.py (horloges idéales, resets et recovery écartés) : les chiffres se "
           "comparent entre eux (renvoi contre témoin), pas aux campagnes LibreLane (étape 5 du prompt 056). Les "
           "colonnes vers_renvoi et depuis_renvoi donnent le pire chemin vers une bascule u_renvoi.* et depuis elle.")
    print("campagne :", c.ferme())


if __name__ == "__main__":
    main()
