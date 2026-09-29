#!/usr/bin/env python3
"""Renomme les sous-cellules d'un GDS de macro avec un prefixe propre a la macro.

Les GDS assembles dans la puce ont 42 sous-cellules homonymes au contenu different (scripts/homonymes.py : kit CML
de versions differentes, rppd et MOS parametres, cellules standard de PDK differents, vias). A la fusion, une seule
version survit et les autres macros recoivent une geometrie qui n'est pas la leur (precheck de coupe6 : 568 M3.b
dans sr16_rx4, les sr16_tx et l'anneau). Les cellules gardees (celles que les LEF nomment) ne changent pas de nom.
Usage : uniq_gds.py <gds entree> <gds sortie> <prefixe> <regex des cellules gardees>
"""
import re
import sys

import klayout.db as db

entree, sortie, prefixe, garde = sys.argv[1:5]
motif = re.compile(garde)
ly = db.Layout()
ly.read(entree)
n = 0
for c in list(ly.each_cell()):
    if not motif.fullmatch(c.name):
        ly.rename_cell(c.cell_index(), f"{prefixe}__{c.name}")
        n += 1
ly.write(sortie)
print(f"uniq_gds : {entree} -> {sortie}, {n} cellules prefixees par {prefixe}__")
