import re, sys
import klayout.db as db
COUCHES = {"Metal2": 10, "Metal3": 30, "Metal4": 50, "Metal5": 67}
def lef_regions(lef):
    txt = open(lef).read()
    macro = re.search(r"^MACRO (\S+)", txt, re.M).group(1)
    pins, obs = {}, {}
    lay = None
    section = None
    for line in txt.splitlines():
        w = line.split()
        if not w: continue
        if w[0] == "PIN": section = "pin"
        elif w[0] == "OBS": section = "obs"
        elif w[0] == "LAYER": lay = w[1]
        elif w[0] == "RECT" and section:
            b = db.Box(*[int(round(float(v) * 1000)) for v in w[1:5]])
            (pins if section == "pin" else obs).setdefault(lay, db.Region()).insert(b)
    return macro, pins, obs
for gds, lef in zip(sys.argv[1::2], sys.argv[2::2]):
    macro, pins, obs = lef_regions(lef)
    ly = db.Layout(); ly.read(gds)
    top = ly.cell(macro)
    for nom, num in COUCHES.items():
        li = ly.find_layer(num, 0)
        reel = db.Region(top.begin_shapes_rec(li)).merged() if li is not None else db.Region()
        couvert = (obs.get(nom, db.Region()) + pins.get(nom, db.Region())).merged()
        nu = (reel - couvert).merged()
        trop = (couvert - reel.sized(300)).merged()
        print(f"{macro:12s} {nom}: metal reel {reel.area()/1e6:9.1f} um2, hors OBS/PIN {nu.area()/1e6:8.2f} um2 ({nu.count()} zones)"
              + (f", ex. {list(nu.each())[0].bbox()}" if nu.count() else "")
              + f" | OBS sans metal {trop.area()/1e6:9.1f} um2")
