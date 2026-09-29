#!/usr/bin/env python3
"""LEF d'integration : OBS recalculees depuis le metal reel du GDS (Metal1 a Metal5, vias compris).

Les OBS produites par Caelum debordent tres largement le metal (couloirs fermes) et laissent du metal reel a nu :
le routeur de puce bute sur les premieres (coupe5 : 828 violations, toutes au bord de sr16_rx4 et des sr16_tx)
et passerait sur le second. Ici, OBS = metal reel de chaque couche, moins les formes des PIN de la meme couche.
Les PIN (et leur ORIGIN) sont repris tels quels du LEF source.
Usage : lef_obs_gds.py <gds> <lef source> <lef sortie>
"""
import re
import sys
import klayout.db as db

COUCHES = [("Metal1", 8), ("Via1", 19), ("Metal2", 10), ("Via2", 29), ("Metal3", 30), ("Via3", 49),
           ("Metal4", 50), ("Via4", 66), ("Metal5", 67)]

gds, lef_src, lef_out = sys.argv[1:4]
txt = open(lef_src).read()
macro = re.search(r"^MACRO (\S+)", txt, re.M).group(1)
pins = {}
section, lay = None, None
for line in txt.splitlines():
    w = line.split()
    if not w:
        continue
    if w[0] == "PIN":
        section = "pin"
    elif w[0] == "OBS":
        section = "obs"
    elif w[0] == "LAYER":
        lay = w[1]
    elif w[0] == "RECT" and section == "pin":
        pins.setdefault(lay, db.Region()).insert(db.Box(*[int(round(float(v) * 1000)) for v in w[1:5]]))

ly = db.Layout()
ly.read(gds)
top = ly.cell(macro)
lignes = ["  OBS"]
for nom, num in COUCHES:
    li = ly.find_layer(num, 0)
    if li is None:
        continue
    reel = db.Region(top.begin_shapes_rec(li)).merged()
    obs = (reel - pins.get(nom, db.Region())).merged()
    if obs.is_empty():
        continue
    lignes.append(f"    LAYER {nom} ;")
    for poly in obs.each():
        for trap in poly.decompose_trapezoids(db.Polygon.TD_htrapezoids):
            b = trap.bbox()
            if trap.is_box():
                lignes.append(f"      RECT {b.left/1000:.3f} {b.bottom/1000:.3f} {b.right/1000:.3f} {b.top/1000:.3f} ;")
            else:
                pts = " ".join(f"{p.x/1000:.3f} {p.y/1000:.3f}" for p in trap.each_point_hull())
                lignes.append(f"      POLYGON {pts} ;")
lignes.append("  END")

debut = re.search(r"^  OBS\b", txt, re.M)
fin = re.search(r"^  END\s*$", txt[debut.end():], re.M)
nouveau = txt[:debut.start()] + "\n".join(lignes) + txt[debut.end() + fin.end():]
tete = (f"# {macro} : LEF d'integration de MSPHY5973 (prompt-063-leo, 29/09/2026). PIN du LEF source {lef_src.split('/')[-1]},\n"
        f"# OBS recalculees depuis le metal reel du GDS (Metal1 a Metal5, vias compris), moins les PIN de la meme couche.\n")
open(lef_out, "w").write(tete + nouveau)
print(macro, "OBS :", sum(1 for l in lignes if l.strip().startswith(("RECT", "POLYGON"))), "formes")
