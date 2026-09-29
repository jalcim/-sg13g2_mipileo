#!/usr/bin/env python3
"""Preuves du renvoi RX -> TX (prompt 056) : csi2_top --renvoi avec renvoi_mode tenu à 00 équivalent au csi2_top sans
renvoi, et mutants refusés.

Protocole de analyse/bloc_v3/preuves_v3.py (lui-même celui de preuves_sync3.py) : lecture par l'outil de synthèse,
proc, flatten, memory, async2sync, equiv_make, equiv_simple -seq 5, equiv_induct -seq 5, equiv_status -assert.
- or : csi2_top.v et les sources de construit.py (sans renvoi) ;
- porte : sources/csi2_top_renvoi.v et renvoi/*.v (construit.py --renvoi), renvoi_mode relié à 00 puis retiré des
  ports ; paramètres du renvoi par défaut, puis RENVOI_ERREUR = 1, RENVOI_STATUT = 0 et RENVOI_PREREMPLI = 16 ;
- mutants (csi2_top_renvoi.v faussé sur un multiplexeur, doivent être refusés) : entrée TX du LM prise au renvoi en
  mode 00, llp_pix_tx privé de llp_tx en mode 00, nombre de pixels de llp_pix_tx pris au renvoi N3 en mode 00.

    python3 3_digital/rtl/csi2_top/construit.py --renvoi
    python3 3_digital/rtl/csi2_top/renvoi/tests/preuves.py [--sans-campagne]
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ICI = Path(__file__).resolve().parent
RENVOI = ICI.parent
TOPD = RENVOI.parent
SOURCES = TOPD / "sources"
TRAV = TOPD / "build" / "renvoi_preuves"
DIGITAL = TOPD.parents[1]
sys.path.insert(0, str(DIGITAL / "mesures"))
DEF = "-DLM_FIFO_ASYNC_P_REMPLACE -DLM_FIFO_SYNC_P_REMPLACE"

MUTANTS = [
    ("M1_entree_lm_au_renvoi", "    assign lm_in_valid = renvoi_app ? tx_in_valid : rv_tx_valid;",
     "    assign lm_in_valid = renvoi_app ? rv_tx_valid : tx_in_valid;"),
    ("M2_pix_tx_sans_llp_tx", "        .i_llp_req_ready        (ltx_req_ready & ~renvoi_n2),",
     "        .i_llp_req_ready        (ltx_req_ready & renvoi_n2),"),
    ("M3_pix_nb_du_renvoi", "    assign ptx_i_pix_nb    = renvoi_app ? tx_pix_nb    : n3_pix_nb;",
     "    assign ptx_i_pix_nb    = renvoi_n3 ? tx_pix_nb    : n3_pix_nb;"),
]


def yosys(lignes, nom):
    TRAV.mkdir(parents=True, exist_ok=True)
    ys, log = TRAV / f"{nom}.ys", TRAV / f"{nom}.log"
    ys.write_text("\n".join(lignes) + "\n")
    r = subprocess.run([os.environ.get("YOSYS", "yosys"), "-q", "-l", str(log), "-s", str(ys)], capture_output=True,
                       text=True)
    texte = log.read_text(errors="replace") if log.exists() else ""
    return r.returncode, texte + r.stderr


def lecture(fichiers, nom, params="", mode00=False):
    l = [f"read_verilog -sv {DEF} -I{SOURCES / 'llp'} {' '.join(fichiers)}", f"hierarchy -top csi2_top{params}",
         "setattr -mod -unset keep_hierarchy", "proc; flatten; memory; opt_clean"]
    if mode00:
        l += ["connect -set renvoi_mode 2'b00", "delete -port csi2_top/renvoi_mode", "opt_clean"]
    return l + [f"rename csi2_top {nom}", f"design -stash {nom}"]


def equiv(gold, gate, nom):
    code, texte = yosys(gold + gate + [
        "design -copy-from gold -as gold gold", "design -copy-from gate -as gate gate", "async2sync", "opt -purge",
        "equiv_make gold gate equiv", "hierarchy -top equiv", "equiv_simple -seq 5", "equiv_induct -seq 5",
        "equiv_status -assert"], nom)
    prouve = code == 0 and "Equivalence successfully proven!" in texte
    m = re.search(r"Of those cells (\d+) are proven and (\d+) are unproven", texte)
    det = (f"{m.group(1)} cellules $equiv prouvées, {m.group(2)} non prouvées" if m else
           ("aucune cellule non prouvée" if prouve else (texte.strip().splitlines()[-1][:200] if texte else "?")))
    return prouve, det


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sans-campagne", action="store_true")
    a = ap.parse_args()
    f = (SOURCES / "fichiers.f").read_text().split()
    if not f[0].endswith("csi2_top_renvoi.v"):
        sys.exit("construit.py --renvoi d'abord")
    renvoi = [x for x in f if Path(x).parent == RENVOI]
    commun = [x for x in f[1:] if x not in renvoi]
    gold = lecture([str(TOPD / "csi2_top.v")] + commun, "gold")
    res = []
    for nom, params, pgold in [
            ("E0_defaut", "", ""),
            ("E1_erreur_sup_sans_statut", " -chparam RENVOI_ERREUR 1 -chparam RENVOI_STATUT 0", ""),
            ("E2_prerempli_16", " -chparam RENVOI_PREREMPLI 16", ""),
            ("E3_n1_seul_debug0", " -chparam DEBUG 0 -chparam RENVOI_NIVEAUX 1 -chparam RENVOI_STATUT 0",
             " -chparam DEBUG 0")]:
        g = gold if not pgold else lecture([str(TOPD / "csi2_top.v")] + commun, "gold", pgold)
        prouve, det = equiv(g, lecture([f[0]] + commun + renvoi, "gate", params, mode00=True), nom)
        res.append(dict(cas=nom, objet=f"csi2_top --renvoi, renvoi_mode = 00{params} contre csi2_top{pgold}",
                        attendu="équivalent",
                        resultat="équivalent" if prouve else "non prouvé", detail=det, conforme=prouve))
        print(res[-1], flush=True)
    texte = Path(f[0]).read_text()
    for nom, avant, apres in MUTANTS:
        assert texte.count(avant) == 1, nom
        mut = TRAV / f"csi2_top_renvoi_{nom}.v"
        TRAV.mkdir(parents=True, exist_ok=True)
        mut.write_text(texte.replace(avant, apres))
        prouve, det = equiv(gold, lecture([str(mut)] + commun + renvoi, "gate", "", mode00=True), nom)
        res.append(dict(cas=nom, objet=f"mutant : {avant.strip()} -> {apres.strip()}", attendu="différent (refusé)",
                        resultat="équivalent" if prouve else "non prouvé", detail=det,
                        conforme=not prouve and "non prouvées" in det))
        print(res[-1], flush=True)
    ok = all(r["conforme"] for r in res)
    print(f"preuves : {sum(r['conforme'] for r in res)}/{len(res)} conformes")
    if not a.sans_campagne:
        from campagne import Campagne
        m = json.loads((SOURCES / "manifeste.json").read_text())
        c = Campagne("yosys", "renvoi RX -> TX : csi2_top --renvoi en mode 00 équivalent au csi2_top, mutants refusés",
                     outils=["yosys"], suffixe="renvoi_preuves", versions={"renvoi": json.dumps(m["renvoi"])})
        for r in res:
            c.ligne(**r)
        c.garde(Path(__file__))
        c.garde(SOURCES / "manifeste.json")
        for r in res:
            log = TRAV / f"{r['cas']}.log"
            if log.exists():
                c.garde(log, f"journaux/{log.name}")
        print("campagne :", c.ferme(f"{sum(r['conforme'] for r in res)} preuves sur {len(res)} conformes"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
