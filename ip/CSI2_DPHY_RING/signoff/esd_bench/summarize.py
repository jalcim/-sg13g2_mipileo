#!/usr/bin/env python3
"""Apply the pass/fail criteria to results_raw.txt and print markdown tables.
Usage: summarize.py results_raw.txt IOVss|IOVdd
Criteria (declared, see esd_MIPI_IOPad*.md):
  V_HV = 8.0 V  on any pair containing iovdd (3.3 V domain, thick oxide 7 nm)
  V_LV = 4.0 V  on pairs without iovdd (iovss-vss, vdd-vss, iovss-vdd : thin oxide 2 nm may sit there)
  I_CLAMP = 1.51 A per clamp NMOS (172 x 4.4 um = 756.8 um, 2 mA/um)
  I_DIODE = 2.67 A per DCN/DCP (2 x 35 um2 elements, 1.33 A each = IHP '2kv' element)
  CDM (~1 ns pulse): current limits x3 (Wunsch-Bell t^-1/2 would give x10 from 100 ns)
Input lines : [deckname:]RES ... ; duplicates (retries '_gear') : the valid run with the
latest tend is kept.
  run valid if the stress peak was simulated : HBM izap >= 0.95 x 0.640 A/kV x (level - Vpair)
  (short-circuit peak of the bench) and tend >= 10 ns ; MM tend >= 100 ns (3 half-periods) ;
  CDM tend >= 1 ns (peak at 0.17 ns). Maxima are taken over [0, tend].
"""
import sys, re, os, collections
V_HV, V_LV, I_CL, I_D = 8.0, 4.0, 1.51, 2.67
TMIN = {'HBM': 10e-9, 'MM': 100e-9, 'CDM': 1e-9}
TSTOP = {'HBM': 400e-9, 'MM': 250e-9, 'CDM': 3e-9}
LIM = {'vio': (V_HV, 'V(iovdd,iovss)'), 'viovss': (V_HV, 'V(iovdd,vss)'), 'viovdd': (V_HV, 'V(iovdd,vdd)'),
       'vgnd': (V_LV, 'V(iovss,vss)'), 'vcore': (V_LV, 'V(vdd,vss)'), 'vissvdd': (V_LV, 'V(iovss,vdd)'),
       'Icl_io': (I_CL, 'I clamp IOPadIOVdd'), 'Icl_core': (I_CL, 'I clamp IOPadVdd'),
       'Idcp_iovss': (I_D, 'I DCP IOPadIOVss'), 'Idcn_iovss': (I_D, 'I DCN IOPadIOVss'),
       'Idcp_vss': (I_D, 'I DCP IOPadVss'), 'Idcn_vss': (I_D, 'I DCN IOPadVss')}
rows = []
for line in open(sys.argv[1]):
    deckname = ''
    if ':RES ' in line:
        deckname, line = line.split(':', 1)
    f = line.split()
    if not f or f[0] != 'RES' or f[1] != sys.argv[2]: continue
    d = dict(kv.split('=') for kv in f[8:])
    d = {k: float(v) for k, v in d.items()}
    rows.append(dict(cell=f[1], ctx=f[2], var=f[3], st=f[4], pad=f[5], ref=f[6], lvl=int(f[7]),
                     deck=os.path.basename(deckname).replace('.log', ''), **d))

def judge(r):
    worst = None
    for k, (lim, lab) in LIM.items():
        if k not in r: continue
        if r['st'] == 'CDM' and k.startswith('I'): lim = 3 * lim
        m = r[k] / lim
        if worst is None or m > worst[0]: worst = (m, k, lab, r[k], lim)
    ok_t = r['tend'] >= TMIN[r['st']] and (r['st'] != 'HBM' or r['izap'] >= 0.95 * 0.640e-3 * (abs(r['lvl']) - r['vpair']))
    trunc = r['tend'] < 0.999 * TSTOP[r['st']]
    verdict = ('PASS' if worst[0] <= 1 else 'FAIL') if ok_t else 'INVALIDE'
    return worst, verdict, trunc

best = {}
for r in rows:
    k = (r['ctx'], r['var'], r['st'], r['pad'], r['ref'], r['lvl'])
    v = judge(r)[1] != 'INVALIDE'
    if k not in best or (v, r['tend']) > (judge(best[k])[1] != 'INVALIDE', best[k]['tend']):
        best[k] = r
rows = list(best.values())

def unit(k): return 'A' if k.startswith('I') else 'V'
def fmt_lvl(r): return f"{'+' if r['lvl']>0 else '-'}{abs(r['lvl'])} V"
def pin(r): return f"{r['pad']} / {r['ref']}" if r['ref'] != 'CDM' else f"{r['pad']} (charge sur sub!)"

def table(sel, title):
    print(f"\n{title}\n")
    print("| contexte | modèle | niveau | broche zappée / réf. | grandeur limitante | valeur | critère | verdict | note |")
    print("|---|---|---|---|---|---|---|---|---|")
    for r in sel:
        (m, k, lab, val, lim), v, tr = judge(r)
        note = f"run tronqué à {r['tend']*1e9:.3g} ns (max pris avant)" if tr else ''
        if r['deck'].endswith('_gear'): note = ('relancé en gear ; ' + note).strip(' ;')
        if r['var'] == 'pdk': note = ('modèle antenne PDK ; ' + note).strip(' ;')
        print(f"| {r['ctx']} | {r['st']} | {fmt_lvl(r)} | {pin(r)} | {lab} | {val:.3g} {unit(k)} | ≤ {lim:g} {unit(k)} | {v} | {note} |")

key = lambda r: (r['ctx'] != 'seul', r['st'], r['ref'], -r['lvl'] if r['lvl'] > 0 else 1e9 - r['lvl'])
esd = [r for r in rows if r['var'] == 'esd']
table(sorted([r for r in esd if (r['st'] == 'HBM' and abs(r['lvl']) == 2000) or r['st'] != 'HBM'], key=key),
      "### Niveaux normatifs (modèles de diodes ESD)")
# HBM sweep
print("\n### Balayage HBM : niveau max qui passe (grille 1-2-3-4-6-8 kV ; + 2,1 à 2,8 kV sur iovdd+ / iovss ; + 0,5 et 0,75 kV sur les zaps vers vdd)\n")
print("| contexte | broche zappée / réf. | polarité | max PASS | 1er FAIL | grandeur limitante au 1er FAIL |")
print("|---|---|---|---|---|---|")
g = collections.defaultdict(list)
for r in esd:
    if r['st'] == 'HBM': g[(r['ctx'], r['pad'], r['ref'], r['lvl'] > 0)].append(r)
for (ctx, pad, ref, pos), rs in sorted(g.items(), key=lambda x: (x[0][0] != 'seul', x[0][2], not x[0][3])):
    rs.sort(key=lambda r: abs(r['lvl']))
    mp, ff = None, None
    for r in rs:
        w, v, _ = judge(r)
        if v == 'PASS' and ff is None: mp = r
        elif v != 'PASS' and ff is None: ff = (r, w, v)
    mps = f"{abs(mp['lvl'])/1000:g} kV" if mp else '< 1 kV'
    ffs = f"{abs(ff[0]['lvl'])/1000:g} kV" if ff else '> 8 kV (non atteint)'
    lim = f"{ff[1][2]} = {ff[1][3]:.3g} {unit(ff[1][1])} ({ff[2]})" if ff else '—'
    print(f"| {ctx} | {pad} / {ref} | {'+' if pos else '-'} | {mps} | {ffs} | {lim} |")
pdk = sorted([r for r in rows if r['var'] == 'pdk'], key=key)
if pdk: table(pdk, "### Contrôle de validité : même banc avec les modèles d'antenne du PDK (dantenna/dpantenna)")
