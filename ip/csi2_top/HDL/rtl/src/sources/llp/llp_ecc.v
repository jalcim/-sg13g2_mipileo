// ECC d'en-tête CSI-2 (v1.3 §9.5) : sous-ensemble 24 bits du code de Hamming modifié.
// Le mot de code fait 30 bits, données D[23:0] et parité ECC[5:0]. ECC[7:6] sont hors du code : émis à 0, ignorés
// à la réception. Tout syndrome d'erreur simple est de poids impair, une erreur double n'en imite donc aucun.
`ifndef __LLP_ECC__
`define __LLP_ECC__
`default_nettype none

// Table 5, lignes 0 à 23 : bits de parité auxquels contribue le bit de données k, rangés en [6k +: 6]
`define LLP_ECC_TABLE { \
    6'h3B, 6'h37, 6'h2F, 6'h1F, 6'h38, 6'h34, 6'h32, 6'h31, \
    6'h2C, 6'h2A, 6'h29, 6'h26, 6'h25, 6'h23, 6'h1C, 6'h1A, \
    6'h19, 6'h16, 6'h15, 6'h13, 6'h0E, 6'h0D, 6'h0B, 6'h07 }

module llp_ecc_gen (
    input  wire [23:0] i_data,          // DI en [7:0], WC en [23:8]
    output wire [5:0]  o_ecc            // ECC[5:0]
);
    localparam [143:0] TABLE = `LLP_ECC_TABLE;

    // Bits de données qui entrent dans le bit de parité parite
    function automatic [23:0] masque(input integer parite);
        integer rang;
        begin
            for (rang = 0; rang < 24; rang = rang + 1)
                masque[rang] = TABLE[6 * rang + parite];
        end
    endfunction

    genvar parite;
    generate
        for (parite = 0; parite < 6; parite = parite + 1)
        begin : g_parite
            localparam [23:0] MASQUE = masque(parite);
            assign o_ecc[parite] = ^(i_data & MASQUE);
        end
    endgenerate
endmodule

// Correction d'après un syndrome déjà calculé (ECC reçue XOR ECC recalculée) : llp_rx l'assemble octet par octet.
module llp_ecc_correct (
    input  wire [23:0] i_data,          // DI et WC reçus
    input  wire [5:0]  i_syndrome,
    output wire [23:0] o_data,          // DI et WC après correction
    output wire [23:0] o_flip,          // bit de données désigné par le syndrome, un au plus
    output wire        o_corrected,     // un bit faux, de données ou de parité, corrigé
    output wire        o_uncorrectable  // syndrome non nul qui ne désigne aucun bit
);
    localparam [143:0] TABLE = `LLP_ECC_TABLE;

    wire [23:0] w_data_faux;            // bit de données désigné par le syndrome
    wire [5:0]  w_parite_faux;          // bit de parité désigné par le syndrome

    genvar rang;
    generate
        for (rang = 0; rang < 24; rang = rang + 1)
        begin : g_data
            assign w_data_faux[rang] = i_syndrome == TABLE[6 * rang +: 6];
        end
        for (rang = 0; rang < 6; rang = rang + 1)
        begin : g_parite
            assign w_parite_faux[rang] = i_syndrome == 6'd1 << rang;
        end
    endgenerate

    assign o_data          = i_data ^ w_data_faux;
    assign o_flip          = w_data_faux;
    assign o_corrected     = |{w_data_faux, w_parite_faux};
    assign o_uncorrectable = |i_syndrome & ~o_corrected;
endmodule

module llp_ecc_check (
    input  wire [31:0] i_header,        // DI, WC, puis ECC en [31:24]
    output wire [23:0] o_data,          // DI et WC après correction
    output wire        o_corrected,     // un bit faux, de données ou de parité, corrigé
    output wire        o_uncorrectable  // syndrome non nul qui ne désigne aucun bit
);
    wire [5:0] w_ecc;

    llp_ecc_gen u_gen (
        .i_data (i_header[23:0]),
        .o_ecc  (w_ecc)
    );

    llp_ecc_correct u_correct (
        .i_data          (i_header[23:0]),
        .i_syndrome      (i_header[29:24] ^ w_ecc),
        .o_data          (o_data),
        .o_flip          (),
        .o_corrected     (o_corrected),
        .o_uncorrectable (o_uncorrectable)
    );
endmodule

`default_nettype wire
`endif
