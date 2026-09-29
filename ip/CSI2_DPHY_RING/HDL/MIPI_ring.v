// MIPI_ring : modeles boite noire des cellules du ring MIPI (ports inout, sans fonction)
`timescale 1ns/10ps

`celldefine
module MIPI_Filler200 (IOVSS, IOVDD, VSS, VDD);
    inout IOVSS;
    inout IOVDD;
    inout VSS;
    inout VDD;
endmodule
`endcelldefine

`celldefine
module MIPI_Filler400 (IOVSS, IOVDD, VSS, VDD);
    inout IOVSS;
    inout IOVDD;
    inout VSS;
    inout VDD;
endmodule
`endcelldefine

`celldefine
module MIPI_Filler1000 (IOVSS, IOVDD, VSS, VDD);
    inout IOVSS;
    inout IOVDD;
    inout VSS;
    inout VDD;
endmodule
`endcelldefine

`celldefine
module MIPI_Filler2000 (IOVSS, IOVDD, VSS, VDD);
    inout IOVSS;
    inout IOVDD;
    inout VSS;
    inout VDD;
endmodule
`endcelldefine

`celldefine
module MIPI_Filler4000 (IOVSS, IOVDD, VSS, VDD);
    inout IOVSS;
    inout IOVDD;
    inout VSS;
    inout VDD;
endmodule
`endcelldefine

`celldefine
module MIPI_Filler10000 (IOVSS, IOVDD, VSS, VDD);
    inout IOVSS;
    inout IOVDD;
    inout VSS;
    inout VDD;
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
module CORNER_Breaker (IOVSS_MIPI, IOVDD_MIPI, VSS, VDD, IOVSS, IOVDD);
    inout IOVSS_MIPI;
    inout IOVDD_MIPI;
    inout VSS;
    inout VDD;
    inout IOVSS;
    inout IOVDD;
endmodule
`endcelldefine

`celldefine
module MIPI_IOPadIOVss (IOVSS, IOVDD, VSS, VDD);
    inout IOVSS;
    inout IOVDD;
    inout VSS;
    inout VDD;
endmodule
`endcelldefine

`celldefine
module MIPI_IOPadIOVdd (IOVSS, IOVDD, VSS, VDD);
    inout IOVSS;
    inout IOVDD;
    inout VSS;
    inout VDD;
endmodule
`endcelldefine

`celldefine
module MIPI_IOPadVdd (IOVSS, IOVDD, VSS, VDD);
    inout IOVSS;
    inout IOVDD;
    inout VSS;
    inout VDD;
endmodule
`endcelldefine

`celldefine
module MIPI_IOPadVss (IOVSS, IOVDD, VSS, VDD);
    inout IOVSS;
    inout IOVDD;
    inout VSS;
    inout VDD;
endmodule
`endcelldefine

`celldefine
module MIPI_IOPadAnalog (IOVSS, IOVDD, VSS, VDD, PAD, PADRES);
    inout IOVSS;
    inout IOVDD;
    inout VSS;
    inout VDD;
    inout PAD;
    inout PADRES;
endmodule
`endcelldefine
