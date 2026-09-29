"""STA d'un module du LLP synthétisé seul : synthèse de LibreLane (synthese.py, 5006f3ba de lm-corrections-revue, absent de
llp-rtl), puis OpenSTA avec ../../llp/llp_pix.sdc aux trois coins, à une période donnée.

Usage, depuis la racine d'une copie du dépôt :
    PYTHONHASHSEED=13 PDK_ROOT=<PDK IHP> YOSYS=<yosys avec pyosys> PATH=<venv LibreLane>/bin:$PATH \\
    python3 3_digital/rtl/tests/llp/sta_llp_module.py <dossier de synthese.py> <période ns> <top> <sortie>
Top : llp_pix_rx, llp_pix_tx ou llp_trame. Le dossier llp/ est donné à Yosys comme dossier d'include
(llp_pix_regles.vh). Imprime surface, cellules, bascules, puis la marge de setup et de hold par coin.
"""
import re
import subprocess
import sys
from pathlib import Path

RACINE = Path.cwd()
LLP = RACINE / "3_digital/rtl/llp"
sys.path.insert(0, sys.argv[1])
import synthese as S  # noqa: E402

PERIODE = float(sys.argv[2])
TOP = sys.argv[3]
SORTIE = Path(sys.argv[4]) / TOP / f"p{PERIODE:g}"
SORTIE.mkdir(parents=True, exist_ok=True)
S.ATTAQUE = "sg13g2_buf_4"
S.REGLAGES["VERILOG_INCLUDE_DIRS"] = [str(LLP)]
S.RTL = RACINE / "3_digital/rtl"
libdir = Path(S.os.environ["PDK_ROOT"]) / "ihp-sg13g2/libs.ref/sg13g2_stdcell/lib"
typ = libdir / "sg13g2_stdcell_typ_1p20V_25C.lib"
surface, cellules, bascules, exclues = S.yosys_librelane(typ, SORTIE, [f"llp/{TOP}.v"], TOP, {}, PERIODE, "DELAY 4")
print(f"surface {surface:.0f} um2, {cellules} cellules, {bascules} bascules, exclues {exclues}")
sdc = (LLP / "llp_pix.sdc").read_text().replace("set periode 7.14", f"set periode {PERIODE}")
(SORTIE / "llp_pix.sdc").write_text(sdc)
MARGES = r"""
foreach sens {max min} {
  set chemins [find_timing_paths -path_group clk -path_delay $sens]
  if {[llength $chemins]} { puts "SLACK $sens [get_property [lindex $chemins 0] slack]" }
}
"""
for coin, fichier in S.COINS.items():
    nom = re.sub(r"\W+", "_", coin).strip("_")
    tcl = SORTIE / f"sta_{nom}.tcl"
    tcl.write_text("\n".join([
        f"read_liberty {libdir / fichier}", f"read_verilog {SORTIE / 'netlist.v'}", f"link_design {TOP}",
        f"read_sdc {SORTIE / 'llp_pix.sdc'}", "unset_propagated_clock [all_clocks]",
        f"report_checks -path_delay max -path_group clk -digits 3 -fields {{fanout}} > {SORTIE / f'setup_{nom}.txt'}",
        f"report_checks -path_delay min -digits 3 > {SORTIE / f'hold_{nom}.txt'}",
        MARGES, "exit"]) + "\n")
    r = subprocess.run(["sta", "-no_splash", "-exit", str(tcl)], capture_output=True, text=True)
    chemin = (SORTIE / f"setup_{nom}.txt").read_text()
    debut = re.search(r"Startpoint: (\S+)", chemin)
    fin = re.search(r"Endpoint: (\S+)", chemin)
    print(coin, re.findall(r"SLACK (\S+ \S+)", r.stdout), "chemin :", debut and debut[1], "->", fin and fin[1],
          r.stderr[-300:])
