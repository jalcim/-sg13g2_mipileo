#!/usr/bin/env python3
"""Bancs 1, 2 et 4 lanes (analyse/lanes_2_4) rejoués sur le csi2_top (29/09/2026).

Même chaîne que analyse/lanes_2_4/campagne_lanes.py (flux D-PHY, SM de Lionel par GHDL, 4 SR8 golden, modèle PHY L22,
juge moteur_lanes/llp_bout_en_bout), avec le csi2_top à la place du bloc v2 :
- sources : rtl/csi2_top/construit.py (sources/fichiers.f, manifeste) au lieu de rtl/integration ;
- banc : analyse/lanes_2_4/tb_rx_top.v dont l'instance lm_llp_top est remplacée, au texte près, par une instance du
  csi2_top ; les sorties de llp_top que le juge lit (en-têtes, charge, fins, événements) sont prises dans le top par
  leur nom hiérarchique (dut.hdr_valid…), tx_erreur et erreur_fifo du LM de même (dut.lm_tx_erreur,
  dut.lm_erreur_fifo), les compteurs sur les ports llp_cnt_* ; format de sortie inchangé ;
- campagne : suffixe csi2_top_lanes_<groupe>.

    python3 3_digital/rtl/csi2_top/construit.py
    python3 3_digital/rtl/csi2_top/tests/lanes.py <groupe> [--paralleles 3] [--troncons K] [--filtre F]
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ICI = Path(__file__).resolve().parent
TOPD = ICI.parent
DIGITAL = TOPD.parents[1]
LANES = DIGITAL / "analyse" / "lanes_2_4"
sys.path.insert(0, str(LANES))
sys.path.insert(0, str(DIGITAL / "mesures"))
import moteur_lanes as L  # noqa: E402

L.INTEG = TOPD
L.BUILD = TOPD / "build" / "lanes"
# ARM_N : défaut du top (bloc v3 : 8, choix 42), sans defparam ; LANES_ARM_N=N pour le surcharger (29/09/2026)
L.ARM_N = __import__("os").environ.get("LANES_ARM_N", "defaut")

INSTANCE = """    csi2_top dut (   // défauts du top (bloc v3 : REMISE_TAILLE = 1, ARM_N = 8, SYNC = 3 ; NB_VC = 4)
        .clk(clk), .rst_n(rst_n), .enable(enable),
        .clk_w(w_clk_w), .mots(w_mots), .hspr(hspr), .statut_phy(statut_phy),
        .fifo_tx_wr(), .fifo_tx_wdata(), .fifo_tx_wlanes(), .fifo_tx_fin(), .fifo_tx_full(1'b0), .tx_init(),
        .rx_sol(), .rx_sol_vc(), .rx_sol_dt(), .rx_sol_wc(), .rx_sol_fmt(), .rx_sol_ecc_corrected(), .rx_sol_sot_err(),
        .rx_pix_valid(), .rx_pix_nb(), .rx_pix_data(), .rx_eol(), .rx_eol_status(), .rx_short_valid(), .rx_short_vc(),
        .rx_short_dt(), .rx_short_data(), .rx_short_ecc_corrected(), .rx_short_sot_err(),
        .trame_fs(), .trame_fe(), .trame_fe_ok(), .trame_vc(), .trame_numero(), .trame_err_hdr(), .trame_err_hdr_vc(),
        .trame_err_end(), .trame_err_end_vc(), .trame_loss(), .trame_loss_mask(), .trame_late(), .trame_late_mask(),
        .trame_slots_pleins(),
        .tx_req_valid(1'b0), .tx_req_ready(), .tx_req_vc(2'd0), .tx_req_dt(6'd0), .tx_req_width(16'd0),
        .tx_pix_valid(1'b0), .tx_pix_ready(), .tx_pix_data(112'd0), .tx_pix_nb(4'd0), .tx_evt_width(), .tx_evt_nb(),
        .tx_init_done(),
        .dbg_verrou(), .dbg_erreur(), .dbg_evt(), .cnt_gel(1'b0),
        .llp_cnt_ok(k_ok), .llp_cnt_ecc_corrected(k_corr), .llp_cnt_ecc_double(k_dbl), .llp_cnt_crc(k_crc),
        .llp_cnt_trunc(k_trunc), .llp_cnt_burst(k_burst), .llp_cnt_dt(k_dt), .llp_cnt_sot_err(k_se),
        .trame_cnt_ok(), .trame_cnt_err(), .trame_cnt_ligne()
    );
    // sorties de llp_top et débogage du LM, lues dans le top (le juge lit le même format que pour le bloc v2)
    assign h_v = dut.hdr_valid;  assign h_vc = dut.hdr_vc;  assign h_dt = dut.hdr_dt;  assign h_wc = dut.hdr_wc;
    assign h_court = dut.hdr_short;  assign h_corr = dut.hdr_ecc_corrected;  assign h_se = dut.hdr_sot_err;
    assign p_v = dut.pay_valid;  assign p_data = dut.pay_data;  assign p_nb = dut.pay_nb;
    assign e_v = dut.end_valid;  assign e_st = dut.end_status;
    assign v_ecc = dut.evt_ecc;  assign v_burst = dut.evt_burst;  assign v_court = dut.evt_short_burst;
    assign v_dt = dut.evt_dt;  assign v_se = dut.evt_sot_err;
    assign w_tx_erreur = dut.lm_tx_erreur;  assign w_erreur_fifo = dut.lm_erreur_fifo;
"""


def tb_csi2() -> Path:
    t = (LANES / "tb_rx_top.v").read_text()
    debut = t.index("    lm_llp_top dut (")
    fin = t.index("    );\n", debut) + len("    );\n")
    t = t[:debut] + INSTANCE + t[fin:]
    t = t.replace("module tb_rx_top;", "module tb_rx_top;   // csi2_top (rtl/csi2_top/tests/lanes.py)")
    assert "lm_llp_top" not in re.sub(r"//.*", "", t)
    L.BUILD.mkdir(parents=True, exist_ok=True)
    f = L.BUILD / "tb_rx_top_csi2.v"
    f.write_text(t)
    return f


def compile_rx(p: dict, sortie: Path, top_v: str | None = None) -> Path:
    cmd = ["iverilog", "-g2012", "-o", str(sortie), "-s", "tb_rx_top", *L.surcharge_arm_n("tb_rx_top"),
           "-DLM_FIFO_ASYNC_P_REMPLACE", "-DLM_FIFO_SYNC_P_REMPLACE", f"-I{TOPD / 'sources' / 'llp'}",
           *(p["fichiers"] if not top_v else [top_v] + p["fichiers"][1:]), p["sr8"], p["modele"], str(tb_csi2())]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        raise SystemExit(f"iverilog :\n{r.stdout}\n{r.stderr}")
    return sortie


L.compile_rx = compile_rx

import campagne as _C  # noqa: E402

_Campagne = _C.Campagne


class _CampagneCsi2(_Campagne):
    def __init__(self, outil, objet, *a, suffixe="", **k):
        super().__init__(outil, "csi2_top (LM du bloc v3 + LLP E0 SYNC3 + nd + pixel + trame) : " + objet.replace(" (bloc v2)", "").replace(
            "bloc lm_llp_top du choix 31 : LM du choix 30 et 27/N2, llp_top de352a6c patché",
            "csi2_top : LM du bloc v3 (SYNC3, ARM_N = 8), llp_top E0 (b09a6a09 + patchs_llp + SYNC3) et llp_rx nd"), *a, suffixe="csi2_top_" + suffixe, **k)


_C.Campagne = _CampagneCsi2

import campagne_lanes  # noqa: E402

if __name__ == "__main__":
    campagne_lanes.main()
