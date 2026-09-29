#!/usr/bin/env python3
"""Ecrit src/MSPHY5973.v : top de la puce, cablage de doc/cablage_msphy5973.md.

v1.0.0 (option B du 29/09) : renvoi RX vers TX non fonctionnel, pont TX en cours (D38).
TX place et relie aux plots, tx_request_hs et clk_request a 0, fifo_tx_* de csi2_top libres.
Entrees MOT et CLK_W des sr16_tx tenues a 0 par des cmos_to_cml (pas de /4 TX livre).
"""
import sys
from pathlib import Path

LANES = 4
MIPI_PWR = ".IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS)"
IO_PWR = ".IOVDD(IOVDD), .IOVSS(IOVSS), .VDD(VDD), .VSS(VSS)"
PISTES = ["POLN_RX", "VB", "PBIAS", "PS", "POLN"]


def bias(cote):
    """Pistes de polarisation d'un cote : les coins n'en ont pas, un net par piste et par cote (comme 061)."""
    return ", ".join(f".{p}(pol_{cote}_{p})" for p in PISTES)


E_BIAS, N_BIAS, W_BIAS, S_BIAS = bias("e"), bias("n"), bias("w"), bias("s")

RX_PADS = ["clk"] + [f"d{k}" for k in range(LANES)]
TX_PADS = ["clk"] + [f"d{k}" for k in range(LANES)]
WEST_IN = ["clk_sys", "rst_n", "renvoi_mode0", "renvoi_mode1"]
SOUTH_IN = [f"en{k}" for k in range(LANES)]


def pad(cell, name, pwr, bias, sigs=""):
    return (f"    (* keep *) {cell} {name} (\n"
            f"        `ifdef USE_POWER_PINS\n        {pwr},\n        `endif\n"
            f"        {bias}{', ' + sigs if sigs else ''}\n    );\n")


def power_pad(cell, name, pwr, bias):
    return (f"    (* keep *) {cell} {name} (\n"
            f"        `ifdef USE_POWER_PINS\n        {pwr},\n        `endif\n"
            f"        {bias}\n    );\n")


def main(out):
    ports = ["inout IOVDD", "inout IOVSS", "inout IOVDD_MIPI", "inout IOVSS_MIPI", "inout VDD", "inout VSS"]
    for lane in RX_PADS:
        ports += [f"inout RX_{lane.upper()}_P", f"inout RX_{lane.upper()}_N"]
    for lane in TX_PADS:
        ports += [f"inout TX_{lane.upper()}_P", f"inout TX_{lane.upper()}_N"]
    ports += ["inout CLKIN_I_P", "inout CLKIN_I_N", "inout CLKIN_Q_P", "inout CLKIN_Q_N", "inout BANDGAP", "inout TX_ANALOG"]
    ports += [f"inout {name.upper()}" for name in WEST_IN + SOUTH_IN]

    v = ["// MSPHY5973 : D-PHY + CSI-2 + E/S, genere par scripts/gen_msphy5973.py, NE PAS EDITER.",
         "// Cablage : doc/cablage_msphy5973.md. v1.0.0 : renvoi RX vers TX non fonctionnel, pont TX en cours (D38).",
         "module MSPHY5973 (", ",\n".join(f"    {p}" for p in ports), ");", ""]
    for cote in "enws":
        v.append(f"    wire {', '.join(f'pol_{cote}_{p}' for p in PISTES)};")
    v.append("    wire vbg, tx_analog_padres_nc;")
    for lane in RX_PADS:
        v.append(f"    wire rx_{lane}_p_hs, rx_{lane}_n_hs, rx_{lane}_p_lp, rx_{lane}_n_lp;")
    for q in "iq":
        v.append(f"    wire clkin_{q}_p_hs, clkin_{q}_n_hs, clkin_{q}_p_lp_nc, clkin_{q}_n_lp_nc;")
    for lane in TX_PADS:
        v.append(f"    wire tx_{lane}_hsp, tx_{lane}_hsn, tx_{lane}_lpinp, tx_{lane}_lpinn;")
    v.append("    wire clk_sys, rst_n, rx_clk, clk_w, clk_tx, clk_q, clk_lane;")
    v.append("    wire cml_ckg_p, cml_ckg_n, clk_rx_en, cml_clk_rx_en_p, cml_clk_rx_en_n;")
    v.append("    wire tx_clk_run, run_q1, run_q2, run_q1_n_nc, run_q2_n_nc;")
    v.append("    wire [3:0] enable;")
    v.append("    wire [1:0] renvoi_mode;")
    v.append("    wire [31:0] mots;")
    v.append("    wire [31:0] mot_p, mot_n;")
    v.append("    wire clk_w_p, clk_w_n;")
    v.append("    wire [3:0] hspr, hsreq, stop;")
    v.append("    wire [11:0] statut_phy;")
    v.append("    wire [3:0] tx_hs_oe, tx_lp_p, tx_lp_n;")
    v.append("    wire tx_clk_hs_oe, tx_clk_lp_p, tx_clk_lp_n;")
    v.append("    wire [3:0] tx_mot_p, tx_mot_n, tx_dout_p, tx_dout_n, tx_dout;")
    v.append("    wire tx_clk_w_p, tx_clk_w_n;")
    v.append("")

    v.append("    // Coins : domaine MIPI a l'est et au nord, domaine IO a l'ouest et au sud")
    v.append(f"    (* keep *) MIPI_Corner corner_ne (\n        `ifdef USE_POWER_PINS\n        {MIPI_PWR}\n        `endif\n    );")
    v.append(f"    (* keep *) MIPI_Corner corner_sw (\n        `ifdef USE_POWER_PINS\n        {IO_PWR}\n        `endif\n    );")
    for c in ["corner_nw", "corner_se"]:
        v.append(f"    (* keep *) MIPI_CornerBreaker {c} (\n        `ifdef USE_POWER_PINS\n"
                 "        .IOVDD(IOVDD), .IOVSS(IOVSS), .IOVDD_MIPI(IOVDD_MIPI), .IOVSS_MIPI(IOVSS_MIPI), .VDD(VDD), .VSS(VSS)\n"
                 "        `endif\n    );")
    v.append("")

    v.append("    // Est : RX")
    v.append(power_pad("MIPI_IOPadIOVdd", "iovdd_mipi_pad", MIPI_PWR, E_BIAS))
    v.append(power_pad("MIPI_IOPadIOVss", "iovss_mipi_pad", MIPI_PWR, E_BIAS))
    v.append(pad("MIPI_IOPadBandgap", "bandgap_pad", MIPI_PWR, E_BIAS, ".PAD(BANDGAP), .VBG(vbg)"))
    for lane in RX_PADS:
        for s in "pn":
            v.append(pad("MIPI_IOPadRX", f"rx_{lane}_{s}_pad", MIPI_PWR, E_BIAS,
                         f".PAD(RX_{lane.upper()}_{s.upper()}), .OUT(rx_{lane}_{s}_hs), .P2C(rx_{lane}_{s}_lp)"))

    v.append("    // Nord : TX et CLKIN")
    v.append(power_pad("MIPI_IOPadVdd", "vdd_pad", MIPI_PWR, N_BIAS))
    v.append(power_pad("MIPI_IOPadVss", "vss_pad", MIPI_PWR, N_BIAS))
    v.append(pad("MIPI_IOPadAnalog", "tx_analog_pad", MIPI_PWR, N_BIAS, ".PAD(TX_ANALOG), .PADRES(tx_analog_padres_nc)"))
    for lane in TX_PADS:
        for s, hs, lp in (("p", "hsp", "lpinp"), ("n", "hsn", "lpinn")):
            v.append(pad("MIPI_IOPadTX", f"tx_{lane}_{s}_pad", MIPI_PWR, N_BIAS,
                         f".PAD(TX_{lane.upper()}_{s.upper()}), .IN_HS(tx_{lane}_{hs}), .LP_IN(tx_{lane}_{lp})"))
    for q in "iq":
        for s in "np":
            v.append(pad("MIPI_IOPadRX", f"clkin_{q}_{s}_pad", MIPI_PWR, N_BIAS,
                         f".PAD(CLKIN_{q.upper()}_{s.upper()}), .OUT(clkin_{q}_{s}_hs), .P2C(clkin_{q}_{s}_lp_nc)"))

    v.append("    // Ouest et sud : alimentations et entrees numeriques du domaine IO")
    v.append(power_pad("MIPI_IOPadIOVdd", "iovdd_pad", IO_PWR, W_BIAS))
    v.append(power_pad("MIPI_IOPadIOVss", "iovss_pad", IO_PWR, W_BIAS))
    v.append(power_pad("MIPI_IOPadVdd", "vdd_s_pad", IO_PWR, S_BIAS))
    v.append(power_pad("MIPI_IOPadVss", "vss_s_pad", IO_PWR, S_BIAS))
    cores = {"clk_sys": "clk_sys", "rst_n": "rst_n", "renvoi_mode0": "renvoi_mode[0]", "renvoi_mode1": "renvoi_mode[1]"}
    cores.update({f"en{k}": f"enable[{k}]" for k in range(LANES)})
    for name in WEST_IN + SOUTH_IN:
        v.append(pad("MIPI_IOPadIn", f"{name}_pad", IO_PWR, W_BIAS if name in WEST_IN else S_BIAS,
                     f".PAD({name.upper()}), .P2C({cores[name]})"))

    v.append("    // RX : deserialiseur CML, machines d'etats, conversion vers CMOS")
    d_ports = ", ".join(f".D{k}_P(rx_d{k}_p_hs), .D{k}_N(rx_d{k}_n_hs)" for k in range(LANES))
    m_ports = ", ".join(f".MOT{i}_P(mot_p[{i}]), .MOT{i}_N(mot_n[{i}])" for i in range(32))
    v.append("    (* keep *) sr16_rx4 sr16_rx4 (\n        `ifdef USE_POWER_PINS\n        .VDD(VDD), .VSS(VSS),\n        `endif\n"
             f"        .POLN(pol_e_POLN), .CK_P(cml_ckg_p), .CK_N(cml_ckg_n),\n        {d_ports},\n"
             f"        {m_ports},\n        .CLK_W_P(clk_w_p), .CLK_W_N(clk_w_n)\n    );")
    c2c = []
    for i in range(32):
        c2c.append((f"c2c_mot{i}", f"mot_p[{i}]", f"mot_n[{i}]", f"mots[{i}]"))
    c2c.append(("c2c_clk_w", "clk_w_p", "clk_w_n", "clk_w"))
    c2c.append(("c2c_rx_clk", "cml_ckg_p", "cml_ckg_n", "rx_clk"))
    c2c.append(("c2c_clk_tx", "clkin_i_p_hs", "clkin_i_n_hs", "clk_tx"))
    c2c.append(("c2c_clk_q", "clkin_q_p_hs", "clkin_q_n_hs", "clk_q"))
    c2c += [(f"c2c_dout{k}", f"tx_dout_p[{k}]", f"tx_dout_n[{k}]", f"tx_dout[{k}]") for k in range(LANES)]
    for name, inp, inn, y in c2c:
        v.append(f"    (* keep *) cml_to_cmos {name} (\n        `ifdef USE_POWER_PINS\n        .VDD(VDD), .VSS(VSS),\n        `endif\n"
                 f"        .INP({inp}), .INN({inn}), .Y({y})\n    );")
    v.append("    // Coupure de l'horloge HS recue (top_rx.vhd 3e264d466) : ck = rx_clk ET clk_rx_en, porte CML.")
    v.append("    (* keep *) cml_gate2 gate_rx_clk (\n        `ifdef USE_POWER_PINS\n        .VDD(VDD), .VSS(VSS),\n        `endif\n"
             "        .AP(rx_clk_p_hs), .AN(rx_clk_n_hs), .BP(cml_clk_rx_en_p), .BN(cml_clk_rx_en_n), .XP(cml_ckg_p), .XN(cml_ckg_n)\n    );")
    v.append("    (* keep *) cmos_to_cml c2m_clk_rx_en (\n        `ifdef USE_POWER_PINS\n        .VDD(VDD), .VSS(VSS),\n        `endif\n"
             "        .POLN(pol_e_POLN), .A(clk_rx_en), .OUTP(cml_clk_rx_en_p), .OUTN(cml_clk_rx_en_n)\n    );")
    v.append("    (* keep *) dphy_rx dphy_rx (\n        `ifdef USE_POWER_PINS\n        .VPWR(VDD), .VGND(VSS),\n        `endif\n"
             "        .PG(pol_e_PBIAS), .rx_clk(rx_clk), .clk_lp_p(rx_clk_p_lp), .clk_lp_n(rx_clk_n_lp),\n"
             "        .clk_stop(), .clk_term_en(), .clk_rx_en(clk_rx_en), .clk_miss(),\n"
             f"        .lp_p({{{', '.join(f'rx_d{k}_p_lp' for k in reversed(range(LANES)))}}}),\n"
             f"        .lp_n({{{', '.join(f'rx_d{k}_n_lp' for k in reversed(range(LANES)))}}}),\n"
             "        .stop(stop), .term_en(), .hs_rx_en(), .hsreq(hsreq), .hspr(hspr)\n    );")
    v.append(f"    assign statut_phy = {{{', '.join(f'hspr[{p}], hsreq[{p}], stop[{p}]' for p in reversed(range(LANES)))}}};")
    v.append("")

    v.append("    // CSI-2 : macro dure t4 g13 (78524823). Entrees d'application a 0, sorties d'application libres.")
    v.append("    // Alimentation de csi2_top par PDN_MACRO_CONNECTIONS : sa boite noire n'a pas de broches VPWR / VGND.")
    v.append("    (* keep *) csi2_top csi2_top (\n"
             "        .clk(clk_sys), .rst_n(rst_n), .enable(enable), .renvoi_mode(renvoi_mode),\n"
             "        .clk_w(clk_w), .mots(mots), .hspr(hspr), .statut_phy(statut_phy),\n"
             "        .cnt_gel(1'b0), .tx_pix_valid(1'b0), .tx_req_valid(1'b0), .tx_pix_data(112'b0),\n"
             "        .tx_pix_nb(4'b0), .tx_req_dt(6'b0), .tx_req_vc(2'b0), .tx_req_width(16'b0),\n"
             "        .fifo_tx_full(1'b0), .fifo_tx_wr(), .fifo_tx_wdata(), .fifo_tx_wlanes(), .fifo_tx_fin(), .tx_init()\n    );")
    v.append("")

    v.append("    // TX : machines d'etats, serialiseurs et pre-drivers. HS inactif en v1.0.0 (pas de pont TX ni de /4 TX).")
    v.append("    (* keep *) dphy_tx dphy_tx (\n        `ifdef USE_POWER_PINS\n        .VPWR(VDD), .VGND(VSS),\n        `endif\n"
             "        .PG(pol_e_PBIAS), .clk(clk_tx), .rst(~rst_n), .clk_request(1'b0), .clk_ready(),\n"
             "        .clk_lp_p(tx_clk_lp_p), .clk_lp_n(tx_clk_lp_n), .clk_hs_oe(tx_clk_hs_oe), .clk_run(tx_clk_run),\n"
             "        .tx_request_hs(4'b0), .tx_ready_hs(), .hs_sync(), .hs_trail(),\n"
             "        .lp_p(tx_lp_p), .lp_n(tx_lp_n), .hs_oe(tx_hs_oe)\n    );")
    c2l = [(f"c2m_mot{k}", f"tx_mot_p[{k}]", f"tx_mot_n[{k}]") for k in range(LANES)]
    c2l.append(("c2m_clk_w", "tx_clk_w_p", "tx_clk_w_n"))
    for name, outp, outn in c2l:
        v.append(f"    (* keep *) cmos_to_cml {name} (\n        `ifdef USE_POWER_PINS\n        .VDD(VDD), .VSS(VSS),\n        `endif\n"
                 f"        .POLN(pol_n_POLN), .A(1'b0), .OUTP({outp}), .OUTN({outn})\n    );")
    for k in range(LANES):
        mots = ", ".join(f".MOT{i}_P(tx_mot_p[{k}]), .MOT{i}_N(tx_mot_n[{k}])" for i in range(8))
        v.append(f"    (* keep *) sr16_tx sr16_tx{k} (\n        `ifdef USE_POWER_PINS\n        .VDD(VDD), .VSS(VSS),\n        `endif\n"
                 f"        .POLN(pol_n_POLN), .CK_P(clkin_i_p_hs), .CK_N(clkin_i_n_hs), .CLK_W_P(tx_clk_w_p), .CLK_W_N(tx_clk_w_n),\n"
                 f"        {mots},\n        .DOUT_P(tx_dout_p[{k}]), .DOUT_N(tx_dout_n[{k}])\n    );")
    # Lane d'horloge : CLKIN_Q (quadrature), tenue a HS-0 hors clk_run ; clk_run resynchronise sur clk_q par deux
    # bascules, puis porte d'horloge a verrou (pas de glitch). Decision de la principale du 29/09 18:52, calque de 061.
    v.append("    sg13g2_dfrbp_1 sync_run1 (.CLK(clk_q), .D(tx_clk_run), .RESET_B(rst_n), .Q(run_q1), .Q_N(run_q1_n_nc));")
    v.append("    sg13g2_dfrbp_1 sync_run2 (.CLK(clk_q), .D(run_q1), .RESET_B(rst_n), .Q(run_q2), .Q_N(run_q2_n_nc));")
    v.append("    sg13g2_lgcp_1 gate_clk_lane (.CLK(clk_q), .GATE(run_q2), .GCLK(clk_lane));")
    drv = [("clk", "clk_lane", "tx_clk_hs_oe", "tx_clk_lp_p", "tx_clk_lp_n")]
    drv += [(f"d{k}", f"tx_dout[{k}]", f"tx_hs_oe[{k}]", f"tx_lp_p[{k}]", f"tx_lp_n[{k}]") for k in range(LANES)]
    for lane, d, oe, lpp, lpn in drv:
        v.append(f"    (* keep *) hs_tx_pd pd_{lane} (.d({d}), .oe({oe}), .lpp({lpp}), .lpn({lpn}),\n"
                 f"        .hsp(tx_{lane}_hsp), .hsn(tx_{lane}_hsn), .lpinp(tx_{lane}_lpinp), .lpinn(tx_{lane}_lpinn));")
    v.append("")
    v.append("endmodule")
    Path(out).write_text("\n".join(v) + "\n")


def lef_to_bb(lef, out):
    """Boite noire Verilog d'une macro depuis son LEF (bornes et directions, bus a plat)."""
    macro, pins, current = None, [], None
    for line in Path(lef).read_text().splitlines():
        words = line.split()
        if not words:
            continue
        if words[0] == "MACRO" and macro is None:
            macro = words[1]
        elif words[0] == "PIN":
            current = words[1]
        elif words[0] == "DIRECTION" and current:
            pins.append((current, {"INPUT": "input", "OUTPUT": "output"}.get(words[1], "inout")))
            current = None
    buses = {}
    for name, direction in pins:
        base, _, bit = name.partition("[")
        entry = buses.setdefault(base, [direction, []])
        if bit:
            entry[1].append(int(bit.rstrip("]")))
    decls = []
    for base, (direction, bits) in buses.items():
        width = f"[{max(bits)}:{min(bits)}] " if bits else ""
        decls.append(f"    {direction} wire {width}{base}")
    body = [f"(* blackbox *)", f"module {macro} ("]
    body.append(",\n".join(decls))
    body += [");", "endmodule"]
    Path(out).write_text(f"// Boite noire de {macro}, generee depuis {Path(lef).name} par scripts/gen_msphy5973.py.\n"
                         + "\n".join(body) + "\n")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--bb":
        lef_to_bb(sys.argv[2], sys.argv[3])
    else:
        main(sys.argv[1] if len(sys.argv) > 1 else "src/MSPHY5973.v")
