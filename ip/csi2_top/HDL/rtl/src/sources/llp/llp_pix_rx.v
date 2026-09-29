// Dépaquetage des pixels en réception (CSI-2 v1.3 §11.4), derrière llp_rx : octets de charge vers pixels.
// Toutes les sorties sortent de bascules. Un étage, latence de 1 cycle depuis les sorties de llp_rx : dépaquetage et
// sorties ; le reste de RAW6, RAW10, RAW12 et RAW14 boucle d'un cycle au suivant. La taille (llp_pix_regles.vh) n'est
// pas jugée sur le chemin des entrées : le WC de la ligne est rangé à l'en-tête (r_wc), et la somme de chiffres va de
// cette bascule à r_bad, lu à la fin de la ligne (revue de llp-pixel, patch 03, choix 43). Une fin au cycle de
// l'en-tête ou au suivant n'est possible qu'avec un WC de 0 à 5 : une table sur WC[2:0] la juge (small_bad).
//
// Format choisi au type de données de l'en-tête (o_sol_fmt) :
// - RAW6 (0x28, §11.4.1 l. 1118-1124, Figure 101) : flux de bits continu, chaque pixel poids faible d'abord,
//   « exception to general CSI-2 rule byte wise LSB first » (l. 1124). Le pixel k occupe les bits 6k à 6k + 5 de
//   la charge lue en petit-boutiste, comme _unpack_bitstream de mipi_csi2.formats. Un pixel sort dès que ses 6 bits
//   sont arrivés : au plus 6 pixels par cycle (4 bits de reste + 32 bits reçus). Le reste vaut 0, 2 ou 4 bits :
//   reste + 8 × octets est toujours pair, et 6 × pixels aussi.
// - RAW8 (0x2A, §11.4.3) : un octet par pixel.
// - RAW10 (0x2B, §11.4.4 l. 1148-1154, Figure 110) : 4 octets de poids forts, puis un octet des 4 paires de poids
//   faibles, pixel 0 en [1:0], comme _unpack_split. Les 4 pixels sortent quand le 5e octet du groupe arrive.
// - RAW12 (0x2C, §11.4.5, Figure 113) : 2 octets de poids forts, puis un octet des 2 quartets faibles, pixel 0 en
//   [3:0]. Au plus 2 groupes de 3 octets par cycle (2 octets de reste + 4 reçus) : 4 pixels.
// - RAW14 (0x2D, §11.4.6, Figure 116) : 4 octets de poids forts, puis les 4 sextets faibles concaténés poids faible
//   d'abord sur 3 octets petit-boutistes, pixel 0 en [5:0]. 6 octets de reste + 4 reçus : un groupe de 7 au plus.
// - Image non dépaquetée (o_sol_fmt = 4) : type de la classe image autre que RAW6 à RAW14 (RAW7, YUV, RGB), un octet
//   par case, taille non jugée. L'application sait ainsi qu'une ligne image lui arrive en octets.
// - Brut (o_sol_fmt = 0) : tout autre type long, un octet par case.
// Case de pixel : 14 bits, pixel aligné à droite, case k en [14k +: 14], cases au-delà de o_pix_nb à 0.
// La ligne sort avant son verdict : l'application la garde jusqu'à o_eol et la jette si o_eol_status n'est pas 0.
// Une taille de charge qui n'est pas un multiple du groupe (ou un WC nul en RAW) donne o_eol_status = 4 sur une
// ligne dont le CRC est bon ; les octets d'un groupe incomplet ne sortent jamais.
// Ordre au même cycle, comme llp_rx : o_eol d'une ligne ouverte avant ce cycle passe avant o_sol ou o_short. Sans
// ligne ouverte avant ce cycle, o_eol ferme la ligne de o_sol du même cycle (WC nul ou paquet très court).
`ifndef __LLP_PIX_RX__
`define __LLP_PIX_RX__
`default_nettype none

module llp_pix_rx (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_hdr_valid,
    input  wire [1:0]  i_hdr_vc,
    input  wire [5:0]  i_hdr_dt,
    input  wire [15:0] i_hdr_wc,
    input  wire        i_hdr_short,
    input  wire        i_hdr_ecc_corrected, // o_hdr_ecc_corrected de llp_rx
    input  wire        i_hdr_sot_err,       // o_hdr_sot_err de llp_rx
    input  wire        i_pay_valid,
    input  wire [31:0] i_pay_data,      // octets tassés vers [7:0], à 0 au-delà de i_pay_nb (llp_rx)
    input  wire [2:0]  i_pay_nb,
    input  wire        i_end_valid,
    input  wire [1:0]  i_end_status,
    output reg         o_sol,
    output reg  [1:0]  o_sol_vc,
    output reg  [5:0]  o_sol_dt,
    output reg  [15:0] o_sol_wc,
    output reg  [2:0]  o_sol_fmt,
    output reg         o_sol_ecc_corrected, // en-tête de la ligne corrigé par l'ECC
    output reg         o_sol_sot_err,       // burst de la ligne marqué rx_out_sot_err (R11)
    output reg         o_pix_valid,
    output reg  [2:0]  o_pix_nb,
    output reg  [83:0] o_pix_data,
    output reg         o_eol,
    output reg  [2:0]  o_eol_status,
    output reg         o_short_valid,
    output reg  [1:0]  o_short_vc,
    output reg  [5:0]  o_short_dt,
    output reg  [15:0] o_short_data,
    output reg         o_short_ecc_corrected,
    output reg         o_short_sot_err
);
`include "llp_pix_regles.vh"

    // pixels complets dans tot bits de RAW6, tot de 0 à 37
    function automatic [2:0] raw6_count(input [5:0] tot);
        if (tot >= 6'd36)      raw6_count = 3'd6;
        else if (tot >= 6'd30) raw6_count = 3'd5;
        else if (tot >= 6'd24) raw6_count = 3'd4;
        else if (tot >= 6'd18) raw6_count = 3'd3;
        else if (tot >= 6'd12) raw6_count = 3'd2;
        else if (tot >= 6'd6)  raw6_count = 3'd1;
        else                   raw6_count = 3'd0;
    endfunction

    reg        r_open;                  // ligne ouverte : en-tête long publié, fin pas encore
    reg [2:0]  r_fmt;
    reg [15:0] r_wc;                    // WC de la ligne ouverte
    reg        r_neuf;                  // cycle qui suit l'en-tête long : r_bad pas encore calculé
    reg        r_bad;                   // taille de la ligne ouverte hors groupe, valable 2 cycles après l'en-tête
    reg [47:0] r_res;                   // reste : bits de RAW6, octets de RAW10, RAW12, RAW14, premier en [0]
    reg [2:0]  r_res_n;                 // 0, 2 ou 4 bits en RAW6 ; octets : 0 à 4 (RAW10), 0 à 2 (RAW12), 0 à 6 (RAW14)

    wire        w_hdr_long;
    wire [2:0]  w_hdr_fmt;
    wire        w_hdr_bad;
    wire        w_end_own;
    wire        w_end_bad;
    wire [2:0]  w_fmt;
    wire [47:0] w_res;
    wire [2:0]  w_res_n;
    wire [31:0] w_data;
    wire [2:0]  w_nb;
    // RAW6
    reg  [36:0] w_comb6;
    wire [5:0]  w_tot6;
    wire [2:0]  w_np6;
    wire [2:0]  w_left6;                // reste en bits, modulo 8 : 0 à 5
    reg  [4:0]  w_res6;
    wire [83:0] w_pix6;
    // RAW10
    reg  [63:0] w_comb10;
    wire [3:0]  w_tot10;
    wire        w_grp10;
    wire [83:0] w_pix10;
    // RAW12
    reg  [47:0] w_comb12;
    wire [2:0]  w_tot12;
    wire [1:0]  w_grp12;                // groupes complets, 0 à 2
    wire [83:0] w_pix12;
    reg  [15:0] w_res12;
    // RAW14
    reg  [79:0] w_comb14;
    wire [3:0]  w_tot14;
    wire        w_grp14;
    wire [23:0] w_bas14;                // les 4 sextets faibles, pixel 0 en [5:0]
    wire [83:0] w_pix14;
    // RAW8 et brut
    wire [83:0] w_pix8;
    // choix
    reg  [2:0]  w_np;
    reg  [83:0] w_pix;
    reg  [47:0] w_res_next;
    reg  [2:0]  w_res_n_next;

    assign w_hdr_long = i_hdr_valid & ~i_hdr_short;
    assign w_hdr_fmt  = format_of(i_hdr_dt);
    // Au cycle de l'en-tête, seule la table des petits WC est sur le chemin des entrées (fin au même cycle : WC <= 1) ;
    // la somme de chiffres part de r_wc, une bascule, vers r_bad. Une fin en état 1, 2 ou 3 passe avant, quel que
    // soit le WC.
    assign w_hdr_bad  = small_bad(w_hdr_fmt, i_hdr_wc[2:0]);
    // La fin d'un cycle d'en-tête long ferme la nouvelle ligne seulement si aucune ligne n'était ouverte avant
    assign w_end_own  = w_hdr_long & ~r_open;
    assign w_end_bad  = w_end_own ? w_hdr_bad : r_neuf ? small_bad(r_fmt, r_wc[2:0]) : r_bad;

    // La charge d'un cycle d'en-tête long appartient à la nouvelle ligne : reste vide, format du nouvel en-tête
    assign w_fmt   = w_hdr_long ? w_hdr_fmt : r_fmt;
    assign w_res   = w_hdr_long ? 48'd0 : r_res;
    assign w_res_n = w_hdr_long ? 3'd0 : r_res_n;
    assign w_data  = i_pay_valid ? i_pay_data : 32'd0;
    assign w_nb    = i_pay_valid ? i_pay_nb : 3'd0;

    // RAW6 : reste de 0, 2 ou 4 bits, puis les octets reçus. Les cas 1, 3 et 5 ne servent pas (reste pair)
    always @(*)
    begin
        case (w_res_n)
            3'd1:    w_comb6 = {4'd0, w_data, w_res[0]};
            3'd2:    w_comb6 = {3'd0, w_data, w_res[1:0]};
            3'd3:    w_comb6 = {2'd0, w_data, w_res[2:0]};
            3'd4:    w_comb6 = {1'd0, w_data, w_res[3:0]};
            3'd5:    w_comb6 = {w_data, w_res[4:0]};
            default: w_comb6 = {5'd0, w_data};
        endcase
    end

    assign w_tot6 = {3'd0, w_res_n} + {w_nb, 3'd0};
    assign w_np6  = raw6_count(w_tot6);
    assign w_left6 = w_tot6[2:0] - {w_np6[0], 2'b00} - {w_np6[1:0], 1'b0};    // tot - 6 np

    always @(*)
    begin
        case (w_np6)
            3'd1:    w_res6 = w_comb6[10:6];
            3'd2:    w_res6 = w_comb6[16:12];
            3'd3:    w_res6 = w_comb6[22:18];
            3'd4:    w_res6 = w_comb6[28:24];
            3'd5:    w_res6 = w_comb6[34:30];
            3'd6:    w_res6 = {4'd0, w_comb6[36]};
            default: w_res6 = w_comb6[4:0];
        endcase
    end

    genvar slot;
    generate
        for (slot = 0; slot < 6; slot = slot + 1)
        begin : g_pix6
            assign w_pix6[14 * slot +: 14] = w_np6 > slot ? {8'd0, w_comb6[6 * slot +: 6]} : 14'd0;
        end
    endgenerate

    // RAW10 : reste de 0 à 4 octets, puis les octets reçus ; un groupe de 5 au plus par cycle
    always @(*)
    begin
        case (w_res_n)
            3'd1:    w_comb10 = {24'd0, w_data, w_res[7:0]};
            3'd2:    w_comb10 = {16'd0, w_data, w_res[15:0]};
            3'd3:    w_comb10 = {8'd0, w_data, w_res[23:0]};
            3'd4:    w_comb10 = {w_data, w_res[31:0]};
            default: w_comb10 = {32'd0, w_data};
        endcase
    end

    assign w_tot10 = {1'b0, w_res_n} + {1'b0, w_nb};
    assign w_grp10 = w_tot10 >= 4'd5;
    assign w_pix10 = {28'd0,
                      4'd0, w_comb10[31:24], w_comb10[39:38],
                      4'd0, w_comb10[23:16], w_comb10[37:36],
                      4'd0, w_comb10[15:8],  w_comb10[35:34],
                      4'd0, w_comb10[7:0],   w_comb10[33:32]};

    // RAW12 : reste de 0 à 2 octets, puis les octets reçus ; deux groupes de 3 au plus par cycle
    always @(*)
    begin
        case (w_res_n)
            3'd1:    w_comb12 = {8'd0, w_data, w_res[7:0]};
            3'd2:    w_comb12 = {w_data, w_res[15:0]};
            default: w_comb12 = {16'd0, w_data};
        endcase
    end

    assign w_tot12 = w_res_n + w_nb;
    assign w_grp12 = w_tot12 >= 3'd6 ? 2'd2 : w_tot12 >= 3'd3 ? 2'd1 : 2'd0;
    assign w_pix12 = {28'd0,
                      w_grp12[1] ? {2'd0, w_comb12[39:32], w_comb12[47:44]} : 14'd0,
                      w_grp12[1] ? {2'd0, w_comb12[31:24], w_comb12[43:40]} : 14'd0,
                      {2'd0, w_comb12[15:8], w_comb12[23:20]},
                      {2'd0, w_comb12[7:0],  w_comb12[19:16]}};

    always @(*)
    begin
        case (w_grp12)
            2'd1:    w_res12 = w_comb12[39:24];
            2'd2:    w_res12 = 16'd0;
            default: w_res12 = w_comb12[15:0];
        endcase
    end

    // RAW14 : reste de 0 à 6 octets, puis les octets reçus ; un groupe de 7 au plus par cycle
    always @(*)
    begin
        case (w_res_n)
            3'd1:    w_comb14 = {40'd0, w_data, w_res[7:0]};
            3'd2:    w_comb14 = {32'd0, w_data, w_res[15:0]};
            3'd3:    w_comb14 = {24'd0, w_data, w_res[23:0]};
            3'd4:    w_comb14 = {16'd0, w_data, w_res[31:0]};
            3'd5:    w_comb14 = {8'd0, w_data, w_res[39:0]};
            3'd6:    w_comb14 = {w_data, w_res[47:0]};
            default: w_comb14 = {48'd0, w_data};
        endcase
    end

    assign w_tot14 = {1'b0, w_res_n} + {1'b0, w_nb};
    assign w_grp14 = w_tot14 >= 4'd7;
    assign w_bas14 = w_comb14[55:32];
    assign w_pix14 = {28'd0,
                      w_comb14[31:24], w_bas14[23:18],
                      w_comb14[23:16], w_bas14[17:12],
                      w_comb14[15:8],  w_bas14[11:6],
                      w_comb14[7:0],   w_bas14[5:0]};

    // RAW8 et brut : un octet par case
    assign w_pix8 = {28'd0, 6'd0, w_data[31:24], 6'd0, w_data[23:16], 6'd0, w_data[15:8], 6'd0, w_data[7:0]};

    always @(*)
    begin
        case (w_fmt)
            FMT_RAW6:
            begin
                w_np         = w_np6;
                w_pix        = w_pix6;
                w_res_next   = {43'd0, w_res6};
                w_res_n_next = w_left6;
            end
            FMT_RAW10:
            begin
                w_np         = w_grp10 ? 3'd4 : 3'd0;
                w_pix        = w_grp10 ? w_pix10 : 84'd0;
                w_res_next   = w_grp10 ? {24'd0, w_comb10[63:40]} : {16'd0, w_comb10[31:0]};
                w_res_n_next = w_grp10 ? w_tot10[2:0] - 3'd5 : w_tot10[2:0];
            end
            FMT_RAW12:
            begin
                w_np         = {w_grp12, 1'b0};             // 2 pixels par groupe
                w_pix        = w_grp12 != 2'd0 ? w_pix12 : 84'd0;
                w_res_next   = {32'd0, w_res12};
                w_res_n_next = w_tot12 - {w_grp12, 1'b0} - {1'b0, w_grp12};
            end
            FMT_RAW14:
            begin
                w_np         = w_grp14 ? 3'd4 : 3'd0;
                w_pix        = w_grp14 ? w_pix14 : 84'd0;
                w_res_next   = w_grp14 ? {24'd0, w_comb14[79:56]} : w_comb14[47:0];
                w_res_n_next = w_grp14 ? w_tot14[2:0] - 3'd7 : w_tot14[2:0];
            end
            default:
            begin
                w_np         = w_nb;
                w_pix        = w_pix8;
                w_res_next   = 48'd0;
                w_res_n_next = 3'd0;
            end
        endcase
    end

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
        begin
            r_open        <= 1'b0;
            r_fmt         <= FMT_RAW;
            r_wc          <= 16'd0;
            r_neuf        <= 1'b0;
            r_bad         <= 1'b0;
            r_res         <= 48'd0;
            r_res_n       <= 3'd0;
            o_sol         <= 1'b0;
            o_sol_vc      <= 2'd0;
            o_sol_dt      <= 6'd0;
            o_sol_wc      <= 16'd0;
            o_sol_fmt     <= FMT_RAW;
            o_sol_ecc_corrected   <= 1'b0;
            o_sol_sot_err         <= 1'b0;
            o_short_ecc_corrected <= 1'b0;
            o_short_sot_err       <= 1'b0;
            o_pix_valid   <= 1'b0;
            o_pix_nb      <= 3'd0;
            o_pix_data    <= 84'd0;
            o_eol         <= 1'b0;
            o_eol_status  <= 3'd0;
            o_short_valid <= 1'b0;
            o_short_vc    <= 2'd0;
            o_short_dt    <= 6'd0;
            o_short_data  <= 16'd0;
        end
        else
        begin
            o_sol         <= w_hdr_long;
            o_short_valid <= i_hdr_valid & i_hdr_short;
            // o_sol_* décrivent la ligne jusqu'à son o_eol : un en-tête court ne les touche pas
            if (w_hdr_long)
            begin
                o_sol_vc  <= i_hdr_vc;
                o_sol_dt  <= i_hdr_dt;
                o_sol_wc  <= i_hdr_wc;
                o_sol_fmt <= w_hdr_fmt;
                // Drapeaux de l'en-tête (choix 34 : sot_err et ECC corrigée ensemble font un paquet « douteux », à
                // juger par l'application)
                o_sol_ecc_corrected <= i_hdr_ecc_corrected;
                o_sol_sot_err       <= i_hdr_sot_err;
            end
            if (i_hdr_valid && i_hdr_short)
            begin
                o_short_vc   <= i_hdr_vc;
                o_short_dt   <= i_hdr_dt;
                o_short_data <= i_hdr_wc;
                o_short_ecc_corrected <= i_hdr_ecc_corrected;
                o_short_sot_err       <= i_hdr_sot_err;
            end
            if (w_hdr_long)
            begin
                r_fmt <= w_hdr_fmt;
                r_wc  <= i_hdr_wc;
            end
            r_neuf <= w_hdr_long;
            r_bad  <= size_bad(r_fmt, r_wc);        // de bascule à bascule ; lu à partir de 2 cycles après l'en-tête
            r_open <= w_hdr_long ? ~(i_end_valid & ~r_open) : r_open & ~i_end_valid;

            o_pix_valid <= i_pay_valid & (w_np != 3'd0);
            o_pix_nb    <= i_pay_valid ? w_np : 3'd0;
            o_pix_data  <= i_pay_valid ? w_pix : 84'd0;
            if (i_pay_valid)
            begin
                r_res   <= w_res_next;
                r_res_n <= w_res_n_next;
            end
            else if (w_hdr_long)
            begin
                r_res   <= 48'd0;
                r_res_n <= 3'd0;
            end

            o_eol        <= i_end_valid;
            o_eol_status <= i_end_status != 2'd0 ? {1'b0, i_end_status} : w_end_bad ? 3'd4 : 3'd0;
        end
    end
endmodule

`default_nettype wire
`endif
