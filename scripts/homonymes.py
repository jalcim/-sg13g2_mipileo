#!/usr/bin/env python3
"""Sous-cellules homonymes au contenu different entre les GDS assembles dans la puce.

A la fusion des GDS (KLayout.StreamOut), une seule version d'une cellule homonyme survit : les autres macros
recoivent alors une geometrie qui n'est pas la leur. Usage : homonymes.py <gds>...
"""
import collections
import hashlib
import sys

import klayout.db as db


def empreinte(ly, c):
    h = hashlib.md5()
    for li in ly.layer_indexes():
        info = str(ly.get_info(li))
        for s in sorted(str(x) for x in c.shapes(li).each()):
            h.update((info + s).encode())
    for inst in sorted(f"{ly.cell(i.cell_index).name}{i.trans}{i.na}{i.nb}" for i in c.each_inst()):
        h.update(inst.encode())
    return h.hexdigest()[:8]


cellules = collections.defaultdict(dict)
for f in sys.argv[1:]:
    ly = db.Layout()
    ly.read(f)
    for c in ly.each_cell():
        cellules[c.name][f.split("/")[-1]] = empreinte(ly, c)
conflits = {n: d for n, d in cellules.items() if len(set(d.values())) > 1}
print(f"{len(cellules)} cellules, {sum(len(d) > 1 for d in cellules.values())} communes, {len(conflits)} en conflit")
for n, d in sorted(conflits.items()):
    print(f"  {n} : {d}")
