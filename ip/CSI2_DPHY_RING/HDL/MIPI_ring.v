// MIPI_ring : modeles boite noire des cellules du ring MIPI (ports inout, sans fonction)
`timescale 1ns/10ps

`celldefine
module MIPI_Filler200 (IOVSS, IOVDD, VSS, VDD, POLN_RX, VB, PBIAS, PS, POLN);
    inout IOVSS;
    inout IOVDD;
    inout VSS;
    inout VDD;
    inout POLN_RX;
    inout VB;
    inout PBIAS;
    inout PS;
    inout POLN;
endmodule
`endcelldefine

`celldefine
module MIPI_Filler400 (IOVSS, IOVDD, VSS, VDD, POLN_RX, VB, PBIAS, PS, POLN);
    inout IOVSS;
    inout IOVDD;
    inout VSS;
    inout VDD;
    inout POLN_RX;
    inout VB;
    inout PBIAS;
    inout PS;
    inout POLN;
endmodule
`endcelldefine

`celldefine
module MIPI_Filler1000 (IOVSS, IOVDD, VSS, VDD, POLN_RX, VB, PBIAS, PS, POLN);
    inout IOVSS;
    inout IOVDD;
    inout VSS;
    inout VDD;
    inout POLN_RX;
    inout VB;
    inout PBIAS;
    inout PS;
    inout POLN;
endmodule
`endcelldefine

`celldefine
module MIPI_Filler2000 (IOVSS, IOVDD, VSS, VDD, POLN_RX, VB, PBIAS, PS, POLN);
    inout IOVSS;
    inout IOVDD;
    inout VSS;
    inout VDD;
    inout POLN_RX;
    inout VB;
    inout PBIAS;
    inout PS;
    inout POLN;
endmodule
`endcelldefine

`celldefine
module MIPI_Filler4000 (IOVSS, IOVDD, VSS, VDD, POLN_RX, VB, PBIAS, PS, POLN);
    inout IOVSS;
    inout IOVDD;
    inout VSS;
    inout VDD;
    inout POLN_RX;
    inout VB;
    inout PBIAS;
    inout PS;
    inout POLN;
endmodule
`endcelldefine

`celldefine
module MIPI_Filler10000 (IOVSS, IOVDD, VSS, VDD, POLN_RX, VB, PBIAS, PS, POLN);
    inout IOVSS;
    inout IOVDD;
    inout VSS;
    inout VDD;
    inout POLN_RX;
    inout VB;
    inout PBIAS;
    inout PS;
    inout POLN;
endmodule
`endcelldefine

`celldefine
module MIPI_Corner (IOVSS, IOVDD, VSS, VDD);
    inout IOVSS;
    inout IOVDD;
    inout VSS;
    inout VDD;
endmodule
`endcelldefine

`celldefine
module MIPI_CornerStop (IOVSS_A, IOVDD_A, VSS, VDD, IOVSS_B, IOVDD_B);
    inout IOVSS_A;
    inout IOVDD_A;
    inout VSS;
    inout VDD;
    inout IOVSS_B;
    inout IOVDD_B;
endmodule
`endcelldefine

`celldefine
module MIPI_CornerBreaker (IOVSS_MIPI, IOVDD_MIPI, VSS, VDD, IOVSS, IOVDD);
    inout IOVSS_MIPI;
    inout IOVDD_MIPI;
    inout VSS;
    inout VDD;
    inout IOVSS;
    inout IOVDD;
endmodule
`endcelldefine

`celldefine
module MIPI_IOPadIOVss (IOVSS, IOVDD, VSS, VDD, POLN_RX, VB, PBIAS, PS, POLN);
    inout IOVSS;
    inout IOVDD;
    inout VSS;
    inout VDD;
    inout POLN_RX;
    inout VB;
    inout PBIAS;
    inout PS;
    inout POLN;
endmodule
`endcelldefine

`celldefine
module MIPI_IOPadIOVdd (IOVSS, IOVDD, VSS, VDD, POLN_RX, VB, PBIAS, PS, POLN);
    inout IOVSS;
    inout IOVDD;
    inout VSS;
    inout VDD;
    inout POLN_RX;
    inout VB;
    inout PBIAS;
    inout PS;
    inout POLN;
endmodule
`endcelldefine

`celldefine
module MIPI_IOPadVdd (IOVSS, IOVDD, VSS, VDD, POLN_RX, VB, PBIAS, PS, POLN);
    inout IOVSS;
    inout IOVDD;
    inout VSS;
    inout VDD;
    inout POLN_RX;
    inout VB;
    inout PBIAS;
    inout PS;
    inout POLN;
endmodule
`endcelldefine

`celldefine
module MIPI_IOPadVss (IOVSS, IOVDD, VSS, VDD, POLN_RX, VB, PBIAS, PS, POLN);
    inout IOVSS;
    inout IOVDD;
    inout VSS;
    inout VDD;
    inout POLN_RX;
    inout VB;
    inout PBIAS;
    inout PS;
    inout POLN;
endmodule
`endcelldefine

`celldefine
module MIPI_IOPadAnalog (IOVSS, IOVDD, VSS, VDD, POLN_RX, VB, PBIAS, PS, POLN, PAD, PADRES);
    inout IOVSS;
    inout IOVDD;
    inout VSS;
    inout VDD;
    inout POLN_RX;
    inout VB;
    inout PBIAS;
    inout PS;
    inout POLN;
    inout PAD;
    inout PADRES;
endmodule
`endcelldefine

`celldefine
module MIPI_IOPadRX (IOVSS, IOVDD, VSS, VDD, POLN_RX, VB, PBIAS, PS, POLN, PAD, P2C, OUT);
    inout IOVSS;
    inout IOVDD;
    inout VSS;
    inout VDD;
    input POLN_RX;
    input VB;
    inout PBIAS;
    inout PS;
    inout POLN;
    inout PAD;
    output P2C;
    output OUT;
endmodule
`endcelldefine

`celldefine
module MIPI_IOPadTX (IOVSS, IOVDD, VSS, VDD, POLN_RX, VB, PBIAS, PS, POLN, PAD, IN_HS, LP_IN);
    inout IOVSS;
    inout IOVDD;
    inout VSS;
    inout VDD;
    inout POLN_RX;
    inout VB;
    input PBIAS;
    input PS;
    inout POLN;
    inout PAD;
    input IN_HS;
    input LP_IN;
endmodule
`endcelldefine

`celldefine
module MIPI_IOPadIn (IOVSS, IOVDD, VSS, VDD, POLN_RX, VB, PBIAS, PS, POLN, PAD, P2C);
    inout IOVSS;
    inout IOVDD;
    inout VSS;
    inout VDD;
    inout POLN_RX;
    inout VB;
    inout PBIAS;
    inout PS;
    inout POLN;
    inout PAD;
    output P2C;
endmodule
`endcelldefine

`celldefine
module MIPI_IOPadOut (IOVSS, IOVDD, VSS, VDD, POLN_RX, VB, PBIAS, PS, POLN, PAD, A);
    inout IOVSS;
    inout IOVDD;
    inout VSS;
    inout VDD;
    inout POLN_RX;
    inout VB;
    inout PBIAS;
    inout PS;
    inout POLN;
    inout PAD;
    input A;
endmodule
`endcelldefine

`celldefine
module MIPI_IOPadBandgap (IOVSS, IOVDD, VSS, VDD, POLN_RX, VB, PBIAS, PS, POLN, PAD, VBG);
    inout IOVSS;
    inout IOVDD;
    inout VSS;
    inout VDD;
    inout POLN_RX;
    inout VB;
    inout PBIAS;
    inout PS;
    inout POLN;
    inout PAD;
    output VBG;
endmodule
`endcelldefine
