// Top de test de l'ECC : llp_ecc_gen et llp_ecc_check côte à côte, entrées indépendantes.
`default_nettype none

module tb_llp_ecc (
    input  wire [23:0] i_data,
    output wire [5:0]  o_ecc,
    input  wire [31:0] i_header,
    output wire [23:0] o_data,
    output wire        o_corrected,
    output wire        o_uncorrectable
);
    llp_ecc_gen u_gen (
        .i_data (i_data),
        .o_ecc  (o_ecc)
    );

    llp_ecc_check u_check (
        .i_header        (i_header),
        .o_data          (o_data),
        .o_corrected     (o_corrected),
        .o_uncorrectable (o_uncorrectable)
    );
endmodule

`default_nettype wire
