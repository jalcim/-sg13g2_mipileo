"""Lance le lint et les bancs cocotb du LLP avec Icarus Verilog, contre le modèle mipi_csi2.

Depuis la racine du dépôt : MIPI_CSI_SRC=<checkout mipi-csi>/src python3 3_digital/rtl/tests/llp/run_llp.py [motif]
Dépendances : iverilog (12 ou plus), verilator (lint), cocotb (2.x).
"""
import os
import subprocess
import sys
from pathlib import Path

from cocotb_tools.runner import get_results, get_runner

ICI = Path(__file__).resolve().parent
LLP = ICI.parent.parent / "llp"
SOURCES = sorted(LLP.glob("*.v")) + [LLP.parent / "lm_cdc.v"]     # lm_sync_reset, pour llp_top

# (top, banc, sources de test en plus de SOURCES, paramètres du top)
CAS = [
    ("tb_llp_ecc", "test_llp_ecc", [ICI / "tb_llp_ecc.v"], {}),
    ("llp_crc_step", "test_llp_crc", [], {}),
    ("tb_llp_rx", "test_llp_rx", [ICI / "tb_llp_rx.v"], {}),
    ("tb_llp_tx", "test_llp_tx", [ICI / "tb_llp_tx.v"], {}),
    ("llp_tx", "test_llp_tx_init", [], {}),
    ("tb_llp_top", "test_llp_top", [ICI / "tb_llp_top.v"], {}),
    ("tb_llp_top", "test_llp_top_sat", [ICI / "tb_llp_top.v"], {"CNT_WIDTH": 3, "INIT_CYCLES": 20000}),
    ("tb_llp_pix_rx", "test_llp_pix_rx", [ICI / "tb_llp_pix_rx.v"], {}),
    ("llp_pix_rx", "test_llp_pix_rx_tailles", [], {}),
    ("tb_llp_trame", "test_llp_trame", [ICI / "tb_llp_trame.v"], {}),
    ("tb_llp_trame", "test_llp_trame_wrap", [ICI / "tb_llp_trame.v"], {"FRAME_WRAP": 1}),
    ("tb_llp_trame", "test_llp_trame_balayage", [ICI / "tb_llp_trame.v"], {}),
    ("tb_llp_pix_tx", "test_llp_pix_tx", [ICI / "tb_llp_pix_tx.v"], {}),
]


def main():
    """run_llp.py [motif] : seuls les bancs dont le nom contient le motif."""
    motif = sys.argv[1] if len(sys.argv) > 1 else ""
    sys.path.insert(0, str(ICI))
    import modele_llp  # noqa: F401  (erreur claire si MIPI_CSI_SRC manque, avant toute compilation)

    runner = get_runner("icarus")
    bilan, echecs = [], 0
    lint = subprocess.run(["bash", str(ICI / "lint_llp.sh")], capture_output=True, text=True)
    echecs += lint.returncode != 0
    bilan.append(("lint (tests/llp/lint_llp.sh)", 1, int(lint.returncode != 0)))
    if lint.returncode:
        print(lint.stdout + lint.stderr)
    for top, banc, sources, parametres in CAS:
        if motif not in banc:
            continue
        build = ICI / "sim_build" / banc
        try:
            runner.build(sources=SOURCES + sources, hdl_toplevel=top, build_dir=build, always=True, includes=[LLP],
                         parameters=parametres, timescale=("1ns", "1ps"))
            xml = runner.test(hdl_toplevel=top, test_module=banc, build_dir=build, test_dir=build)
            n, f = get_results(xml)
        except Exception as erreur:  # un banc qui plante compte en échec, les suivants tournent quand même
            print(f"{banc} : {erreur!r}")
            n, f = 1, 1
        echecs += f
        bilan.append((banc, n, f))
    print()
    for nom, n, f in bilan:
        print(f"{nom:32} {n - f}/{n} {'OK' if f == 0 else 'ÉCHEC'}")
    print("tout passe" if echecs == 0 else f"{echecs} échec(s)")
    sys.exit(1 if echecs else 0)


if __name__ == "__main__":
    main()
