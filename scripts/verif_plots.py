#!/usr/bin/env python3
"""Routage interne des plots MIPI_IOPadRX et MIPI_IOPadTX : chaque etiquette de borne est-elle reliee a un composant ?

Extraction de connectivite (metaux, vias, contacts, poly) sur la cellule a plat. Pour chaque etiquette, on donne
le nombre de formes du net et le nombre de contacts (cont) qu'il touche : un net sans contact n'atteint aucun
transistor ni resistance. Usage : klayout -b -r verif_plots.py -rd gds=<MIPI_ring.gds>
"""
import klayout.db as db

CONDUCTEURS = [("gatpoly", 5), ("cont", 6), ("metal1", 8), ("via1", 19), ("metal2", 10), ("via2", 29),
               ("metal3", 30), ("via3", 49), ("metal4", 50), ("via4", 66), ("metal5", 67),
               ("topvia1", 125), ("topmetal1", 126), ("topvia2", 133), ("topmetal2", 134)]
PILE = [nom for nom, _ in CONDUCTEURS]
TEXTES = {"metal1": 8, "metal2": 10, "metal3": 30, "metal4": 50, "metal5": 67, "topmetal1": 126, "topmetal2": 134}
BORNES = {"PAD", "OUT", "P2C", "IN_HS", "LP_IN", "POLN_RX", "VB", "PBIAS", "PS", "POLN"}

ly = db.Layout()
ly.read(gds)
for nom in ("MIPI_IOPadRX", "MIPI_IOPadTX"):
    cell = ly.cell(nom)
    filles = sorted({ly.cell(i.cell_index).name for i in cell.each_inst()})
    print(f"== {nom} : {sum(1 for _ in cell.each_inst())} instances filles ({', '.join(filles)})")
    for nom_couche, num in CONDUCTEURS:
        li = ly.find_layer(num, 0)
        if li is not None:
            print(f"   {nom_couche:10s} formes propres a la cellule : {cell.shapes(li).size()}")
    l2n = db.LayoutToNetlist(db.RecursiveShapeIterator(ly, cell, []))
    couches = {}
    for nom_couche, num in CONDUCTEURS:
        li = ly.find_layer(num, 0)
        couches[nom_couche] = l2n.make_layer(li, nom_couche) if li is not None else l2n.make_layer(nom_couche)
    for a, b in zip(PILE, PILE[1:]):
        l2n.connect(couches[a])
        l2n.connect(couches[a], couches[b])
    l2n.connect(couches[PILE[-1]])
    etiquettes = []
    for metal, num in TEXTES.items():
        for dt in (25, 2, 0):
            li = ly.find_layer(num, dt)
            if li is None:
                continue
            it = db.RecursiveShapeIterator(ly, cell, li)
            it.max_depth = 0
            while not it.at_end():
                forme = it.shape()
                if forme.is_text() and forme.text_string in BORNES:
                    etiquettes.append((forme.text_string, metal, forme.text_pos.transformed(it.trans())))
                it.next()
    l2n.extract_netlist()
    vus = set()
    for texte, metal, pos in etiquettes:
        if (texte, metal) in vus:
            continue
        vus.add((texte, metal))
        net = l2n.probe_net(couches[metal], pos)
        if net is None:
            print(f"   {texte:8s} ({metal}) : etiquette hors metal en {pos}")
            continue
        formes = sum(l2n.shapes_of_net(net, couches[c], True).count() for c in PILE)
        contacts = l2n.shapes_of_net(net, couches["cont"], True).count()
        print(f"   {texte:8s} ({metal}) : {formes} formes, {contacts} contacts, "
              f"boite {l2n.shapes_of_net(net, couches[metal], True).bbox()}")
