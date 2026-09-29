#!/usr/bin/env python3
"""Coquilles SPICE vides des cellules extraites en boites noires au LVS de puce (MAGIC_EXT_ABSTRACT_CELLS).

Meme regle que la livraison 1 (061, msphy4263/scripts/coquilles_lvs.py) : netgen apparie une boite noire par ses
broches, il lui faut un .subckt, meme vide. Broches des macros lues dans le LEF que la config utilise, plots MIPI
dans le HDL de MIPI_ring, bondpad dans son LEF. Usage : coquilles_lvs.py <sortie.spice>
"""
from pathlib import Path
import re
import sys

import yaml

ICI = Path(__file__).resolve().parent.parent


def broches_lef(chemin):
    return [m.group(1) for m in re.finditer(r"^  PIN (\S+)", chemin.read_text(), re.M)]


def broches_hdl(chemin):
    return {m.group(1): [b.strip() for b in m.group(2).split(",")]
            for m in re.finditer(r"module\s+(\w+)\s*\(([^)]*)\)", chemin.read_text())}


def main():
    config = yaml.safe_load((ICI / "librelane" / "config.yaml").read_text())
    lignes = ["* Coquilles vides pour le LVS de puce de MSPHY5973 (scripts/coquilles_lvs.py).", ""]
    for macro, vues in config["MACROS"].items():
        lef = ICI / "librelane" / vues["lef"][0].replace("dir::", "")
        lignes += [f".subckt {macro} " + " ".join(broches_lef(lef)), f".ends {macro}", ""]
    for cellule, broches in broches_hdl(ICI / "ip" / "CSI2_DPHY_RING" / "HDL" / "MIPI_ring.v").items():
        lignes += [f".subckt {cellule} " + " ".join(broches), f".ends {cellule}", ""]
    bondpad = ICI / "ip" / "sg13g2_bondpad_70x70_novias" / "lef" / "bondpad_70x70_novias.lef"
    lignes += [".subckt bondpad_70x70_novias " + " ".join(broches_lef(bondpad)), ".ends bondpad_70x70_novias", ""]
    Path(sys.argv[1]).write_text("\n".join(lignes))
    print(f"coquilles_lvs : {len(config['MACROS'])} macros, plots MIPI et bondpad -> {sys.argv[1]}")


if __name__ == "__main__":
    main()
