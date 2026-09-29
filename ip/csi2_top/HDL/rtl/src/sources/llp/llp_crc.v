// CRC-16 de la charge CSI-2 (v1.3 §9.6, figure 54) : polynôme x^16 + x^12 + x^5 + 1 réfléchi (0x8408),
// registre C[15:0] initialisé à 0xFFFF en début de paquet, octets pris dans l'ordre, bit de poids faible d'abord.
`ifndef __LLP_CRC__
`define __LLP_CRC__
`default_nettype none

module llp_crc_step (
    input  wire [15:0] i_crc,           // registre avant ces octets
    input  wire [31:0] i_data,          // octet k en [8k +: 8], le premier en [7:0]
    input  wire [2:0]  i_nb,            // octets pris à partir de l'octet 0, de 0 à 4 ; au-delà de 4, traité comme 4
    output wire [15:0] o_crc            // registre après ces octets
);
    localparam [15:0] POLY = 16'h8408;

    function automatic [15:0] crc_octet(input [15:0] crc_avant, input [7:0] octet);
        integer rang;
        begin
            crc_octet = crc_avant;
            for (rang = 0; rang < 8; rang = rang + 1)
                crc_octet = (crc_octet >> 1) ^ ((crc_octet[0] ^ octet[rang]) ? POLY : 16'h0000);
        end
    endfunction

    // Registre après nb octets, pris un à un : sert seulement à calculer les masques ci-dessous
    function automatic [15:0] crc_octets(input [15:0] crc_avant, input [31:0] octets, input integer nb);
        integer rang;
        begin
            crc_octets = crc_avant;
            for (rang = 0; rang < nb; rang = rang + 1)
                crc_octets = crc_octet(crc_octets, octets[8 * rang +: 8]);
        end
    endfunction

    // Le registre après nb octets est linéaire en i_crc et en ces octets : bits de {i_data, i_crc} dont dépend son
    // bit sortie. Chaque bit se calcule alors en un seul XOR équilibré, au lieu de quatre octets enchaînés.
    function automatic [47:0] masque(input integer nb, input [3:0] sortie);
        integer rang;
        reg [15:0] image;
        begin
            for (rang = 0; rang < 48; rang = rang + 1)
            begin
                image = rang < 16 ? crc_octets(16'd1 << rang, 32'd0, nb) : crc_octets(16'd0, 32'd1 << (rang - 16), nb);
                masque[rang] = image[sortie];
            end
        end
    endfunction

    wire [79:0] w_crc_nb;               // [16k +: 16] : registre après k octets, k de 0 à 4

    genvar rang_nb, rang_bit;
    generate
        for (rang_nb = 0; rang_nb < 5; rang_nb = rang_nb + 1)
        begin : g_nb
            for (rang_bit = 0; rang_bit < 16; rang_bit = rang_bit + 1)
            begin : g_bit
                localparam [47:0] MASQUE = masque(rang_nb, rang_bit);
                assign w_crc_nb[16 * rang_nb + rang_bit] = ^({i_data, i_crc} & MASQUE);
            end
        end
    endgenerate

    assign o_crc = i_nb > 3'd4 ? w_crc_nb[64 +: 16] : w_crc_nb[16 * i_nb +: 16];
endmodule

`default_nettype wire
`endif
