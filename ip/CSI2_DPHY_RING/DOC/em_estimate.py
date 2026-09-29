#!/usr/bin/env python3.13
"""Estimation EM (DC, 11 ans @105 C) d'un pad d'alim MIPI_IOPad* : valeurs ESTIMEES.

Usage : python3.13 em_estimate.py [--rail-y Y] MAG/drc/MIPI_IOPadIOVss.gds [...]
  --rail-y Y : fin de la zone d'injection impose (sinon : premier y ou le TopMetal2
               du net couvre toute la largeur ; obligatoire si ce y n'existe pas,
               ex. MIPI_IOPadVss --rail-y 140, MIPI_IOPadVdd --rail-y 127.5).
Methode :
  1. connectivite M1..TopMetal2 + vias (LayoutToNetlist) ; net du pad = celui du
     stub TopMetal2 (point (40, 1.5), bas de cellule).
  2. injection plot -> rail : lignes de coupe horizontales y = 0 .. y_rail (y_rail =
     premier y ou le TopMetal2 du net couvre toute la largeur) ; largeur de metal
     du net par couche, minimum sur y ; vias du net compte par niveau dans cette zone.
  3. rail : lignes de coupe verticales x = 0 .. 80 ; largeur du net par couche,
     minimum sur x (courant qui sort de la cellule d'un cote).
Densites : SG13G2_os_process_spec.pdf, table 2.15.
"""
import sys
import klayout.db as db

METALS = [  # nom, (layer, dt), J mA/um
    ("Metal1", (8, 0), 1.0), ("Metal2", (10, 0), 2.0), ("Metal3", (30, 0), 2.0),
    ("Metal4", (50, 0), 2.0), ("Metal5", (67, 0), 2.0),
    ("TopMetal1", (126, 0), 15.0), ("TopMetal2", (134, 0), 16.0)]
VIAS = [  # nom, (layer, dt), I mA/via, metal bas, metal haut
    ("Via1", (19, 0), 0.4, 0, 1), ("Via2", (29, 0), 0.4, 1, 2), ("Via3", (49, 0), 0.4, 2, 3),
    ("Via4", (66, 0), 0.4, 3, 4), ("TopVia1", (125, 0), 1.4, 4, 5), ("TopVia2", (133, 0), 10.0, 5, 6)]
STEP = 0.01  # um


def cut_width(reg, horizontal, pos, lo, hi, dbu):
    """Longueur de metal de reg coupee par la ligne (horizontale y=pos ou verticale x=pos)."""
    p = int(round(pos / dbu))
    a, b = int(round(lo / dbu)), int(round(hi / dbu))
    e = db.Edges([db.Edge(a, p, b, p) if horizontal else db.Edge(p, a, p, b)])
    return (e & reg).length() * dbu


def analyse(path, rail_y=None):
    ly = db.Layout()
    ly.read(path)
    top = ly.top_cell()
    dbu = ly.dbu
    l2n = db.LayoutToNetlist(db.RecursiveShapeIterator(ly, top, []))
    mreg = [l2n.make_layer(ly.layer(*ld), n) for n, ld, _ in METALS]
    vreg = [l2n.make_layer(ly.layer(*ld), n) for n, ld, *_ in VIAS]
    for m in mreg:
        l2n.connect(m)
    for v, (_, _, _, lo, hi) in zip(vreg, VIAS):
        l2n.connect(v)
        l2n.connect(v, mreg[lo])
        l2n.connect(v, mreg[hi])
    l2n.extract_netlist()
    net = l2n.probe_net(mreg[6], db.DPoint(40.0, 1.5))
    if net is None:
        sys.exit(f"{path}: pas de TopMetal2 en (40, 1.5)")
    nm = [l2n.shapes_of_net(net, m, True).merged() for m in mreg]
    nv = [l2n.shapes_of_net(net, v, True) for v in vreg]
    bb = top.bbox().to_dtype(dbu)
    W = 80.0
    print(f"== {top.name}  net du plot = {net.expanded_name()}")
    # y_rail : premier y ou TopMetal2 du net couvre toute la largeur
    y = 0.0
    while rail_y is None and cut_width(nm[6], True, y + STEP / 2, 0, W, dbu) < W - 1e-6:
        y += STEP
        if y > bb.top:
            sys.exit("pas de rail TopMetal2 pleine largeur")
    y_rail = y if rail_y is None else rail_y
    print(f"stub TopMetal2 -> rail pleine largeur a y = {y_rail:.2f} um")
    print("-- injection (coupes horizontales y = 0 .. y_rail) : largeur min du net par couche")
    ys = [i * STEP + STEP / 2 for i in range(int(round(y_rail / STEP)))]
    inj = {}
    for (n, _, J), r in zip(METALS, nm):
        ws = [cut_width(r, True, yy, -1, W + 1, dbu) for yy in ys]
        wmin = min(ws)
        ymin = ys[ws.index(wmin)]
        inj[n] = (wmin, J)
        print(f"  {n:10s} w_min = {wmin:7.2f} um a y = {ymin:6.2f}  -> {wmin * J:8.1f} mA")
    # somme parallele par ligne de coupe (toutes couches), minimum sur y
    par = [sum(cut_width(r, True, yy, -1, W + 1, dbu) * J for (_, _, J), r in zip(METALS, nm)) for yy in ys]
    print(f"  toutes couches en parallele : min {min(par):.1f} mA a y = {ys[par.index(min(par))]:.2f}")
    print("-- vias du net dans la zone d'injection (y < y_rail)")
    zone = db.Region(db.Box(int(-1 / dbu), 0, int((W + 1) / dbu), int(round(y_rail / dbu))))
    for (n, _, I, _, _), r in zip(VIAS, nv):
        c = (r & zone).count()
        print(f"  {n:8s} {c:5d} vias -> {c * I:8.1f} mA")
    print("-- vias du net par tranche : stub y<3 / 3..y_rail / y>=y_rail")
    for (n, _, I, _, _), r in zip(VIAS, nv):
        cs = []
        for a, b in ((0, 3), (3, y_rail), (y_rail, bb.top)):
            z = db.Region(db.Box(int(-1 / dbu), int(round(a / dbu)), int((W + 1) / dbu), int(round(b / dbu))))
            cs.append(sum(1 for v in r.each() if z.interacting(db.Region(v)).count() and v.bbox().center().y >= a / dbu and v.bbox().center().y < b / dbu))
        print(f"  {n:8s} {cs[0]:5d} / {cs[1]:5d} / {cs[2]:5d}  ({I} mA/via)")
    print("-- rail (coupes verticales x = 0 .. 80, toute la hauteur) : largeur min du net par couche")
    xs = [i * STEP + STEP / 2 for i in range(int(round(W / STEP)))]
    for (n, _, J), r in zip(METALS, nm):
        ws = [cut_width(r, False, xx, bb.bottom - 1, bb.top + 1, dbu) for xx in xs]
        wmin = min(ws)
        print(f"  {n:10s} w_min = {wmin:7.2f} um a x = {xs[ws.index(wmin)]:6.2f}  -> {wmin * J:8.1f} mA")
    print()


if __name__ == "__main__":
    args = sys.argv[1:]
    ry = None
    if args[:1] == ["--rail-y"]:
        ry = float(args[1])
        args = args[2:]
    for p in args:
        analyse(p, ry)
