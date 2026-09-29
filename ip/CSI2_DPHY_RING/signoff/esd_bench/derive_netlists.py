#!/usr/bin/env python3
"""Derive two probe copies of the IHP sg13g2_io netlist (source untouched).
  io_probe_pdk.spice : IHP netlist + 0 V sense sources (clamp NMOS, DCN, DCP)
                       (+ clamp gate antenna diode remapped, see clamp())
  io_probe_esd.spice : same, but DCN/DCP antenna-diode models replaced by the
                       IHP ESD diode models (sg13g2_esd.lib, diodevss_4kv /
                       diodevdd_4kv : same geometry, DEV_A=70um2, DEV_P=116.2um)
Usage: derive_netlists.py <sg13g2_io.spice> <outdir>
"""
import sys, re, hashlib, os
src, out = sys.argv[1], sys.argv[2]
txt = open(src).read()
md5 = hashlib.md5(txt.encode()).hexdigest()

def sub_body(t, name, fn):
    m = re.search(r'(\.subckt %s .*?\n)(.*?)(\.ends)' % re.escape(name), t, re.S)
    assert m, name
    return t[:m.start(2)] + fn(m.group(2)) + t[m.end(2):]

def clamp(b):
    b = b.replace(' pad gate iovss sub! sg13_hv_nmos', ' pad_s gate iovss sub! sg13_hv_nmos')
    assert b.count('pad_s') == 172, b.count('pad_s')
    # gate antenna diode (0.48x0.48 um): the dantenna compact model (tt=700 ns, soft
    # breakdown nbv=48.9/112) stalls the transient solver (step < 1 fs at t~85 ps).
    # Replaced by the IHP ESD junction model of the same n+/psub type and same area.
    old = 'XD0 sub! gate dantenna l=480n w=480n m=1'
    assert old in b
    b = b.replace(old, 'D0 sub! gate diodevss_mod area=0.2304 pj=1.92 ; was: ' + old)
    return b + 'Vsc pad pad_s 0\n'

def dcn_pdk(b):
    b = b.replace('sub! cathode dantenna', 'sub! cath_s dantenna')
    return b + 'Vsn cath_s cathode 0\n'

def dcp_pdk(b):
    b = b.replace('XD1 anode cathode', 'XD1 an_s cathode').replace('XD0 anode cathode', 'XD0 an_s cathode')
    return b + 'Vsp anode an_s 0\n'

def dcn_esd(b):
    return ('* ESD model substitution (diodevss_4kv of sg13g2_esd.lib)\n'
            'D1 sub! cath_s diodevss_mod area=70 pj=116.2\n'
            'Dsub sub! guard dsub_4kv_mod area=381.0339 pj=90.32\n'
            'Vsn cath_s cathode 0\n'
            'XR0 anode sub! ptap1 R=5.191\n')

def dcp_esd(b):
    return ('* ESD model substitution (diodevdd_4kv of sg13g2_esd.lib)\n'
            'D1 an_s cathode diodevdd_mod area=70 pj=116.2\n'
            'Dsub sub! cathode dsub_4kv_mod area=381.0339 pj=90.32\n'
            'Vsp anode an_s 0\n'
            'XR0 guard sub! ptap1 R=17.289\n')

for tag, fn, fp in (('pdk', dcn_pdk, dcp_pdk), ('esd', dcn_esd, dcp_esd)):
    t = sub_body(txt, 'sg13g2_Clamp_N43N43D4R', clamp)
    t = sub_body(t, 'sg13g2_DCNDiode', fn)
    t = sub_body(t, 'sg13g2_DCPDiode', fp)
    hdr = '* DERIVED by derive_netlists.py from %s (md5 %s) -- variant %s\n' % (src, md5, tag)
    open(os.path.join(out, 'io_probe_%s.spice' % tag), 'w').write(hdr + t)
print(md5)
