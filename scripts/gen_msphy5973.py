#!/usr/bin/env python3
"""Ecrit src/MSPHY5973.v : top de la puce, cablage de doc/cablage_msphy5973.md.

TX provisoire en LP seul (trous 1 et 2 de la fiche : pas de pont TX ni de /4 TX) :
tx_request_hs et clk_request a 0, d des pre-drivers a 0, fifo_tx_full a 0.
"""
import sys
from pathlib import Path

LANES = 4
MIPI_PWR = ".IOVDD(IOVDD_MIPI), .IOVSS(IOVSS_MIPI), .VDD(VDD), .VSS(VSS)"
IO_PWR = ".IOVDD(IOVDD), .IOVSS(IOVSS), .VDD(VDD), .VSS(VSS)"
MIPI_BIAS = ".POLN_RX(POLN_RX), .VB(VB), .PBIAS(PBIAS), .PS(PS), .POLN(POLN)"
IO_BIAS = ".POLN_RX(POLN_RX_IO), .VB(VB_IO), .PBIAS(PBIAS_IO), .PS(PS_IO), .POLN(POLN_IO)"

RX_PADS = ["clk"] + [f"d{k}" for k in range(LANES)]
TX_PADS = ["clk"] + [f"d{k}" for k in range(LANES)]
WEST_IN = ["clk_sys", "rst_n"] + [f"en{k}" for k in range(LANES)]
SOUTH_IN = ["renvoi_mode0", "renvoi_mode1"]


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
    ports += ["inout CLKIN_P", "inout CLKIN_N", "inout BANDGAP"]
    ports += [f"inout {name.upper()}" for name in WEST_IN + SOUTH_IN]

    v = ["// MSPHY5973 : D-PHY + CSI-2 + E/S, genere par scripts/gen_msphy5973.py, NE PAS EDITER.",
         "// Cablage : doc/cablage_msphy5973.md. TX en LP seul (pas de pont TX ni de /4 TX livres).",
         "module MSPHY5973 (", ",\n".join(f"    {p}" for p in ports), ");", ""]
    v.append("    wire POLN_RX, VB, PBIAS, PS, POLN;")
    v.append("    wire POLN_RX_IO, VB_IO, PBIAS_IO, PS_IO, POLN_IO;")
    v.append("    wire vbg;")
    for lane in RX_PADS:
        v.append(f"    wire rx_{lane}_p_hs, rx_{lane}_n_hs, rx_{lane}_p_lp, rx_{lane}_n_lp;")
    v.append("    wire clkin_p_hs, clkin_n_hs, clkin_p_lp_nc, clkin_n_lp_nc;")
    for lane in TX_PADS:
        v.append(f"    wire tx_{lane}_hsp, tx_{lane}_hsn, tx_{lane}_lpinp, tx_{lane}_lpinn;")
    v.append("    wire clk_sys, rst_n, rx_clk, clk_w, tx_ck;")
    v.append("    wire [3:0] enable;")
    v.append("    wire [1:0] renvoi_mode;")
    v.append("    wire [31:0] mots;")
    v.append("    wire [31:0] mot_p, mot_n;")
    v.append("    wire clk_w_p, clk_w_n;")
    v.append("    wire [3:0] hspr, hsreq, stop;")
    v.append("    wire [11:0] statut_phy;")
    v.append("    wire [3:0] tx_hs_oe, tx_lp_p, tx_lp_n;")
    v.append("    wire tx_clk_hs_oe, tx_clk_lp_p, tx_clk_lp_n;")
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
    v.append(power_pad("MIPI_IOPadIOVdd", "iovdd_mipi_pad", MIPI_PWR, MIPI_BIAS))
    v.append(power_pad("MIPI_IOPadIOVss", "iovss_mipi_pad", MIPI_PWR, MIPI_BIAS))
    for lane in RX_PADS:
        for s in "pn":
            v.append(pad("MIPI_IOPadRX", f"rx_{lane}_{s}_pad", MIPI_PWR, MIPI_BIAS,
                         f".PAD(RX_{lane.upper()}_{s.upper()}), .OUT(rx_{lane}_{s}_hs), .P2C(rx_{lane}_{s}_lp)"))

    v.append("    // Nord : TX, CLKIN, bandgap")
    v.append(power_pad("MIPI_IOPadVdd", "vdd_pad", MIPI_PWR, MIPI_BIAS))
    v.append(power_pad("MIPI_IOPadVss", "vss_pad", MIPI_PWR, MIPI_BIAS))
    for lane in TX_PADS:
        for s, hs, lp in (("p", "hsp", "lpinp"), ("n", "hsn", "lpinn")):
            v.append(pad("MIPI_IOPadTX", f"tx_{lane}_{s}_pad", MIPI_PWR, MIPI_BIAS,
                         f".PAD(TX_{lane.upper()}_{s.upper()}), .IN_HS(tx_{lane}_{hs}), .LP_IN(tx_{lane}_{lp})"))
    for s in "np":
        v.append(pad("MIPI_IOPadRX", f"clkin_{s}_pad", MIPI_PWR, MIPI_BIAS,
                     f".PAD(CLKIN_{s.upper()}), .OUT(clkin_{s}_hs), .P2C(clkin_{s}_lp_nc)"))
    v.append(pad("MIPI_IOPadBandgap", "bandgap_pad", MIPI_PWR, MIPI_BIAS, ".PAD(BANDGAP), .VBG(vbg)"))

    v.append("    // Ouest et sud : alimentations et entrees numeriques du domaine IO")
    v.append(power_pad("MIPI_IOPadIOVdd", "iovdd_pad", IO_PWR, IO_BIAS))
    v.append(power_pad("MIPI_IOPadIOVss", "iovss_pad", IO_PWR, IO_BIAS))
    v.append(power_pad("MIPI_IOPadVdd", "vdd_s_pad", IO_PWR, IO_BIAS))
    v.append(power_pad("MIPI_IOPadVss", "vss_s_pad", IO_PWR, IO_BIAS))
    cores = {"clk_sys": "clk_sys", "rst_n": "rst_n", "renvoi_mode0": "renvoi_mode[0]", "renvoi_mode1": "renvoi_mode[1]"}
    cores.update({f"en{k}": f"enable[{k}]" for k in range(LANES)})
    for name in WEST_IN + SOUTH_IN:
        v.append(pad("MIPI_IOPadIn", f"{name}_pad", IO_PWR, IO_BIAS, f".PAD({name.upper()}), .P2C({cores[name]})"))

    v.append("    // RX : deserialiseur CML, machines d'etats, conversion vers CMOS")
    d_ports = ", ".join(f".D{k}_P(rx_d{k}_p_hs), .D{k}_N(rx_d{k}_n_hs)" for k in range(LANES))
    m_ports = ", ".join(f".MOT{i}_P(mot_p[{i}]), .MOT{i}_N(mot_n[{i}])" for i in range(32))
    v.append("    sr16_rx4 sr16_rx4 (\n        `ifdef USE_POWER_PINS\n        .VDD(VDD), .VSS(VSS),\n        `endif\n"
             f"        .POLN(POLN), .CK_P(rx_clk_p_hs), .CK_N(rx_clk_n_hs),\n        {d_ports},\n"
             f"        {m_ports},\n        .CLK_W_P(clk_w_p), .CLK_W_N(clk_w_n)\n    );")
    c2c = []
    for i in range(32):
        c2c.append((f"c2c_mot{i}", f"mot_p[{i}]", f"mot_n[{i}]", f"mots[{i}]"))
    c2c.append(("c2c_clk_w", "clk_w_p", "clk_w_n", "clk_w"))
    c2c.append(("c2c_rx_clk", "rx_clk_p_hs", "rx_clk_n_hs", "rx_clk"))
    c2c.append(("c2c_tx_ck", "clkin_p_hs", "clkin_n_hs", "tx_ck"))
    for name, inp, inn, y in c2c:
        v.append(f"    cml_to_cmos {name} (\n        `ifdef USE_POWER_PINS\n        .VDD(VDD), .VSS(VSS),\n        `endif\n"
                 f"        .INP({inp}), .INN({inn}), .Y({y})\n    );")
    v.append("    dphy_rx dphy_rx (\n        `ifdef USE_POWER_PINS\n        .VPWR(VDD), .VGND(VSS),\n        `endif\n"
             "        .PG(POLN_RX), .rx_clk(rx_clk), .clk_lp_p(rx_clk_p_lp), .clk_lp_n(rx_clk_n_lp),\n"
             "        .clk_stop(), .clk_term_en(), .clk_rx_en(), .clk_miss(),\n"
             f"        .lp_p({{{', '.join(f'rx_d{k}_p_lp' for k in reversed(range(LANES)))}}}),\n"
             f"        .lp_n({{{', '.join(f'rx_d{k}_n_lp' for k in reversed(range(LANES)))}}}),\n"
             "        .stop(stop), .term_en(), .hs_rx_en(), .hsreq(hsreq), .hspr(hspr)\n    );")
    v.append(f"    assign statut_phy = {{{', '.join(f'hspr[{p}], hsreq[{p}], stop[{p}]' for p in reversed(range(LANES)))}}};")
    v.append("")

    v.append("    // CSI-2 : macro dure t4 g13 (78524823). Entrees d'application a 0, sorties d'application libres.")
    v.append("    csi2_top csi2_top (\n        `ifdef USE_POWER_PINS\n        .VPWR(VDD), .VGND(VSS),\n        `endif\n"
             "        .clk(clk_sys), .rst_n(rst_n), .enable(enable), .renvoi_mode(renvoi_mode),\n"
             "        .clk_w(clk_w), .mots(mots), .hspr(hspr), .statut_phy(statut_phy),\n"
             "        .cnt_gel(1'b0), .tx_pix_valid(1'b0), .tx_req_valid(1'b0), .tx_pix_data(112'b0),\n"
             "        .tx_pix_nb(4'b0), .tx_req_dt(6'b0), .tx_req_vc(2'b0), .tx_req_width(16'b0),\n"
             "        .fifo_tx_full(1'b0), .fifo_tx_wr(), .fifo_tx_wdata(), .fifo_tx_wlanes(), .fifo_tx_fin(), .tx_init()\n    );")
    v.append("")

    v.append("    // TX : machines d'etats et pre-drivers, en LP seul tant que le pont TX et le /4 TX manquent")
    v.append("    dphy_tx dphy_tx (\n        `ifdef USE_POWER_PINS\n        .VPWR(VDD), .VGND(VSS),\n        `endif\n"
             "        .PG(POLN_RX), .clk(tx_ck), .rst(~rst_n), .clk_request(1'b0), .clk_ready(),\n"
             "        .clk_lp_p(tx_clk_lp_p), .clk_lp_n(tx_clk_lp_n), .clk_hs_oe(tx_clk_hs_oe), .clk_run(),\n"
             "        .tx_request_hs(4'b0), .tx_ready_hs(), .hs_sync(), .hs_trail(),\n"
             "        .lp_p(tx_lp_p), .lp_n(tx_lp_n), .hs_oe(tx_hs_oe)\n    );")
    drv = [("clk", "tx_clk_hs_oe", "tx_clk_lp_p", "tx_clk_lp_n")]
    drv += [(f"d{k}", f"tx_hs_oe[{k}]", f"tx_lp_p[{k}]", f"tx_lp_n[{k}]") for k in range(LANES)]
    for lane, oe, lpp, lpn in drv:
        v.append(f"    (* keep *) hs_tx_pd pd_{lane} (.d(1'b0), .oe({oe}), .lpp({lpp}), .lpn({lpn}),\n"
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
    body = [f"(* blackbox *)", f"module {macro} ("]
    body.append(",\n".join(f"    {d} wire {n}" for n, d in pins))
    body += [");", "endmodule"]
    Path(out).write_text(f"// Boite noire de {macro}, generee depuis {Path(lef).name} par scripts/gen_msphy5973.py.\n"
                         + "\n".join(body) + "\n")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--bb":
        lef_to_bb(sys.argv[2], sys.argv[3])
    else:
        main(sys.argv[1] if len(sys.argv) > 1 else "src/MSPHY5973.v")
