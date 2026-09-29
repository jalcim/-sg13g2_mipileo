// Empaquetage des pixels en émission (CSI-2 v1.3 §11.4), devant llp_tx : pixels de l'application vers la requête
// et la charge de llp_tx. Toutes les sorties sortent de bascules.
//
// Format choisi au type de données de la requête :
// - RAW6 (0x28, §11.4.1 l. 1118-1124, Figure 101) : flux de bits continu, chaque pixel poids faible d'abord
//   (l. 1124), comme _pack_bitstream de mipi_csi2.formats. 8 pixels par battement, 6 octets.
// - RAW8 (0x2A, §11.4.3) : 4 pixels par battement, un octet chacun.
// - RAW10 (0x2B, §11.4.4 l. 1148-1154, Figure 110) : 4 pixels par battement, leurs 8 bits forts puis un octet des
//   4 paires de bits faibles, pixel 0 en [1:0], comme _pack_split. 5 octets.
// - RAW12 (0x2C, §11.4.5, Figure 113) : 4 pixels par battement, deux groupes de 2 : bits [11:4] de chacun, puis
//   l'octet des 2 quartets faibles, pixel 0 en [3:0]. 6 octets.
// - RAW14 (0x2D, §11.4.6, Figure 116) : 4 pixels par battement, leurs bits [13:6], puis les 4 sextets faibles
//   concaténés poids faible d'abord sur 3 octets petit-boutistes. 7 octets.
// - Brut : tout autre type long (image non dépaquetée comprise), 4 octets par battement (case k, bits [7:0]).
//   i_req_width compte alors des octets.
// - Paquet court (type 0x00 à 0x0F) : i_req_width porte le champ de données, aucun pixel.
// Case de pixel k en [14k +: 14], pixel aligné à droite ; les bits au-dessus de sa largeur ne sont pas lus.
// i_pix_nb n'est pas suivi : le compte vient de width. Un i_pix_nb différent du compte attendu (plein, ou reste du
// dernier battement) lève o_evt_nb une période, et le battement est pris comme prévu par width.
// WC selon payload_size : width / 4 × 3 en RAW6, width en RAW8 et brut, width / 4 × 5 en RAW10, width / 2 × 3 en
// RAW12, width / 4 × 7 en RAW14. Largeur refusée (ValueError de payload_size) : 0 sur un type RAW, pas multiple de 4
// en RAW6, RAW10 ou RAW14, impaire en RAW12, ou WC au-delà de 65 535. La requête est prise, les battements annoncés par width sont pris et jetés, aucun
// paquet ne part, et o_evt_width monte une période.
// Écart à §9.11 (l. 848-854), qui permet de bourrer la ligne jusqu'au groupe : refus, comme payload_size de l'oracle.
//
// Étages :
// - A : le battement pris, déjà en octets et masqué au-delà de son nombre d'octets. Il passe dans Q au front
//   suivant, toujours : o_pix_ready garantit la place.
// - Q : file de 20 octets, le premier en [7:0]. Le mot de tête Q[31:0] est la charge présentée à llp_tx. Le
//   battement de A s'ajoute derrière les octets restants (décalage de 0 à 19 octets).
// o_pix_ready, calculé sur l'état suivant en supposant que llp_tx ne prend rien : il monte si les octets de Q et
// de A, plus un battement plein, tiennent dans 20. RAW14 (7 octets par battement) demande 18 places pour qu'aucun
// trou ne se forme (calcul du rythme, 4 octets sortis par cycle) ; 20 laissent de la marge. Le premier battement d'un paquet attend Q et A vides : ses
// octets commencent un mot neuf. Sans trou de l'application, Q garde au moins 4 octets une fois lancé, et
// llp_tx ne voit aucune pause (budget de §4.5).
// Latence : requête prise vers o_llp_req_valid, 1 cycle ; battement pris vers o_llp_pay_valid, 2 cycles.
`ifndef __LLP_PIX_TX__
`define __LLP_PIX_TX__
`default_nettype none

module llp_pix_tx (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_req_valid,
    output wire        o_req_ready,
    input  wire [1:0]  i_req_vc,
    input  wire [5:0]  i_req_dt,
    input  wire [15:0] i_req_width,     // pixels, octets en brut, champ de données d'un paquet court
    input  wire        i_pix_valid,
    output wire        o_pix_ready,
    input  wire [111:0] i_pix_data,     // 8 cases de 14 bits, pixel aligné à droite
    input  wire [3:0]  i_pix_nb,        // contrôlé : le compte vient de i_req_width, un écart lève o_evt_nb
    output wire        o_evt_width,
    output wire        o_evt_nb,
    output wire        o_llp_req_valid,
    input  wire        i_llp_req_ready,
    output wire [1:0]  o_llp_req_vc,
    output wire [5:0]  o_llp_req_dt,
    output wire [15:0] o_llp_req_wc,
    output wire        o_llp_pay_valid,
    input  wire        i_llp_pay_ready,
    output wire [31:0] o_llp_pay_data,
    output wire [2:0]  o_llp_pay_nb
);
`include "llp_pix_regles.vh"

    localparam [4:0] Q_BYTES   = 5'd20;

    // requête vers l'application et vers llp_tx
    reg        r_req_ready;
    reg        r_evt_width;
    reg        r_lr_valid;
    reg [1:0]  r_lr_vc;
    reg [5:0]  r_lr_dt;
    reg [15:0] r_lr_wc;
    // paquet en cours d'entrée
    reg [2:0]  r_fmt;
    reg [14:0] r_left;                  // battements restant à prendre, 16 384 au plus
    reg        r_first;                 // le prochain battement pris est le premier du paquet
    reg        r_drop;                  // largeur refusée : battements pris et jetés
    reg [2:0]  r_bpb;                   // octets d'un battement plein : 4 à 7
    reg [2:0]  r_last_n;                // octets du dernier battement
    reg [3:0]  r_ppb;                   // pixels d'un battement plein : 8 ou 4
    reg [3:0]  r_last_px;               // pixels du dernier battement
    reg        r_evt_nb;
    reg        r_pix_ready;
    // A
    reg        r_a_valid;
    reg [55:0] r_a_data;
    reg [2:0]  r_a_n;
    reg        r_a_last;
    // Q et mot présenté à llp_tx
    reg [159:0] r_q;
    reg [4:0]   r_qn;
    reg         r_q_last;               // Q contient le dernier octet du paquet
    reg         r_pv;
    reg [2:0]   r_pnb;

    wire        w_req_take;
    wire [2:0]  w_req_fmt;
    wire        w_req_raw;              // type RAW dépaqueté ici : taille jugée
    wire [14:0] w_req_pairs;
    wire        w_req_short;
    wire [13:0] w_req_quads;
    wire [17:0] w_req_wc;
    wire        w_req_bad;
    wire [14:0] w_req_beats;
    wire [2:0]  w_req_bpb;
    wire [2:0]  w_req_last_n;
    wire [3:0]  w_req_ppb;
    wire [3:0]  w_req_last_px;
    wire        w_lr_valid_next;
    wire        w_pix_take;
    wire        w_pix_last;
    wire [2:0]  w_pix_n;
    wire [3:0]  w_pix_px;
    reg  [55:0] w_packed;
    wire [55:0] w_mask;
    wire [14:0] w_left_next;
    wire        w_first_next;
    wire        w_drop_next;
    wire [2:0]  w_bpb_next;
    wire        w_a_valid_next;
    wire        w_pop;
    wire [4:0]  w_qn_pop;
    wire [159:0] w_q_pop;
    wire        w_q_last_pop;
    wire [159:0] w_q_next;
    wire [4:0]  w_qn_next;
    wire        w_q_last_next;
    wire [4:0]  w_held;                 // octets de Q et de A après ce front
    wire        w_pix_ready_next;

    // Requête : WC, nombre de battements et octets du dernier, largeur refusée
    assign w_req_take   = i_req_valid & r_req_ready;
    assign w_req_fmt    = format_of(i_req_dt);
    assign w_req_short  = i_req_dt[5:4] == 2'b00;
    assign w_req_raw    = w_req_fmt == FMT_RAW6 || w_req_fmt == FMT_RAW8 || w_req_fmt == FMT_RAW10
                          || w_req_fmt == FMT_RAW12 || w_req_fmt == FMT_RAW14;
    assign w_req_quads  = i_req_width[15:2];
    assign w_req_pairs  = i_req_width[15:1];
    assign w_req_wc     = w_req_fmt == FMT_RAW6  ? {3'd0, w_req_quads, 1'b0} + {4'd0, w_req_quads}
                        : w_req_fmt == FMT_RAW10 ? {2'd0, w_req_quads, 2'b00} + {4'd0, w_req_quads}
                        : w_req_fmt == FMT_RAW12 ? {2'd0, w_req_pairs, 1'b0} + {3'd0, w_req_pairs}
                        : w_req_fmt == FMT_RAW14 ? {1'b0, w_req_quads, 3'b000} - {4'd0, w_req_quads}
                        :                          {2'd0, i_req_width};
    // Types réservés (CSI-2 v1.3 Table 3 : « shall not be used ») refusés comme une largeur fausse : 0x04 à 0x07,
    // 0x13 à 0x17, 0x1B, 0x25 à 0x27, 0x2E, 0x2F, 0x38 à 0x3F, même masque que llp_rx (RESERVES), qui les rejette.
    localparam [63:0] RESERVES = 64'hFF00_C0E0_08F8_00F0;
    assign w_req_bad    = RESERVES[i_req_dt]
                          || (w_req_raw
                              && (i_req_width == 16'd0 || w_req_wc[17:16] != 2'd0
                                  || (w_req_fmt == FMT_RAW12 && i_req_width[0])
                                  || ((w_req_fmt == FMT_RAW6 || w_req_fmt == FMT_RAW10 || w_req_fmt == FMT_RAW14)
                                      && i_req_width[1:0] != 2'd0)));
    assign w_req_beats  = w_req_short          ? 15'd0
                        : w_req_fmt == FMT_RAW6 ? {2'd0, i_req_width[15:3]} + {14'd0, |i_req_width[2:0]}
                        :                         {1'b0, i_req_width[15:2]} + {14'd0, |i_req_width[1:0]};
    assign w_req_bpb    = w_req_fmt == FMT_RAW6  || w_req_fmt == FMT_RAW12 ? 3'd6
                        : w_req_fmt == FMT_RAW10 ? 3'd5
                        : w_req_fmt == FMT_RAW14 ? 3'd7 : 3'd4;
    assign w_req_last_n = w_req_fmt == FMT_RAW6  ? (i_req_width[2] ? 3'd3 : 3'd6)
                        : w_req_fmt == FMT_RAW12 ? (i_req_width[1] ? 3'd3 : 3'd6)
                        : w_req_fmt == FMT_RAW10 ? 3'd5
                        : w_req_fmt == FMT_RAW14 ? 3'd7
                        : i_req_width[1:0] == 2'd0 ? 3'd4 : {1'b0, i_req_width[1:0]};
    assign w_req_ppb     = w_req_fmt == FMT_RAW6 ? 4'd8 : 4'd4;
    assign w_req_last_px = w_req_fmt == FMT_RAW6  ? (i_req_width[2] ? 4'd4 : 4'd8)
                         : w_req_fmt == FMT_RAW12 ? (i_req_width[1] ? 4'd2 : 4'd4)
                         : w_req_fmt == FMT_RAW10 || w_req_fmt == FMT_RAW14 ? 4'd4
                         : i_req_width[1:0] == 2'd0 ? 4'd4 : {2'd0, i_req_width[1:0]};
    assign w_lr_valid_next = (w_req_take & ~w_req_bad) | (r_lr_valid & ~i_llp_req_ready);

    // Battement de pixels vers octets, masqué au-delà de son nombre d'octets
    assign w_pix_take = i_pix_valid & r_pix_ready;
    assign w_pix_last = r_left == 15'd1;
    assign w_pix_n    = w_pix_last ? r_last_n : r_bpb;
    assign w_pix_px   = w_pix_last ? r_last_px : r_ppb;

    // pixel k du battement, 14 bits
    wire [13:0] w_p0 = i_pix_data[13:0];
    wire [13:0] w_p1 = i_pix_data[27:14];
    wire [13:0] w_p2 = i_pix_data[41:28];
    wire [13:0] w_p3 = i_pix_data[55:42];
    wire [5:0]  w_p4 = i_pix_data[61:56];           // cases 4 à 7 : RAW6 seulement
    wire [5:0]  w_p5 = i_pix_data[75:70];
    wire [5:0]  w_p6 = i_pix_data[89:84];
    wire [5:0]  w_p7 = i_pix_data[103:98];
    wire [23:0] w_bas14 = {w_p3[5:0], w_p2[5:0], w_p1[5:0], w_p0[5:0]};

    always @(*)
    begin
        case (r_fmt)
            FMT_RAW6:
                w_packed = {8'd0, w_p7, w_p6, w_p5, w_p4,
                            w_p3[5:0], w_p2[5:0], w_p1[5:0], w_p0[5:0]};
            FMT_RAW10:
                w_packed = {16'd0, w_p3[1:0], w_p2[1:0], w_p1[1:0], w_p0[1:0],
                            w_p3[9:2], w_p2[9:2], w_p1[9:2], w_p0[9:2]};
            FMT_RAW12:
                w_packed = {8'd0, w_p3[3:0], w_p2[3:0], w_p3[11:4], w_p2[11:4],
                            w_p1[3:0], w_p0[3:0], w_p1[11:4], w_p0[11:4]};
            FMT_RAW14:
                w_packed = {w_bas14, w_p3[13:6], w_p2[13:6], w_p1[13:6], w_p0[13:6]};
            default:
                w_packed = {24'd0, w_p3[7:0], w_p2[7:0], w_p1[7:0], w_p0[7:0]};
        endcase
    end

    genvar octet;
    generate
        for (octet = 0; octet < 7; octet = octet + 1)
        begin : g_mask
            assign w_mask[8 * octet +: 8] = {8{w_pix_n > octet}};
        end
    endgenerate

    assign w_left_next    = w_req_take ? w_req_beats : r_left - {14'd0, w_pix_take};
    assign w_first_next   = w_req_take | (r_first & ~w_pix_take);
    assign w_drop_next    = w_req_take ? w_req_bad : r_drop;
    assign w_bpb_next     = w_req_take ? w_req_bpb : r_bpb;
    assign w_a_valid_next = w_pix_take & ~r_drop;

    // Q : le mot de tête part si llp_tx le prend, puis A s'ajoute derrière ce qui reste
    assign w_pop         = r_pv & i_llp_pay_ready;
    assign w_qn_pop      = ~w_pop ? r_qn : r_qn > 5'd4 ? r_qn - 5'd4 : 5'd0;
    assign w_q_pop       = w_pop ? {32'd0, r_q[159:32]} : r_q;
    assign w_q_last_pop  = r_q_last & ~(w_pop & r_qn <= 5'd4);
    assign w_q_next      = w_q_pop | (r_a_valid ? {104'd0, r_a_data} << {w_qn_pop, 3'b000} : 160'd0);
    assign w_qn_next     = w_qn_pop + (r_a_valid ? {2'd0, r_a_n} : 5'd0);
    assign w_q_last_next = w_q_last_pop | (r_a_valid & r_a_last);

    assign w_held           = w_qn_next + (w_a_valid_next ? {2'd0, w_pix_n} : 5'd0);
    assign w_pix_ready_next = w_left_next != 15'd0
                              && (w_drop_next
                                  || (w_first_next ? w_held == 5'd0
                                                   : {1'b0, w_held} + {3'd0, w_bpb_next} <= {1'b0, Q_BYTES}));

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
        begin
            r_req_ready <= 1'b0;
            r_evt_width <= 1'b0;
            r_lr_valid  <= 1'b0;
            r_lr_vc     <= 2'd0;
            r_lr_dt     <= 6'd0;
            r_lr_wc     <= 16'd0;
            r_fmt       <= FMT_RAW;
            r_left      <= 15'd0;
            r_first     <= 1'b0;
            r_drop      <= 1'b0;
            r_bpb       <= 3'd4;
            r_last_n    <= 3'd4;
            r_ppb       <= 4'd4;
            r_last_px   <= 4'd4;
            r_evt_nb    <= 1'b0;
            r_pix_ready <= 1'b0;
            r_a_valid   <= 1'b0;
            r_a_data    <= 56'd0;
            r_a_n       <= 3'd0;
            r_a_last    <= 1'b0;
            r_q         <= 160'd0;
            r_qn        <= 5'd0;
            r_q_last    <= 1'b0;
            r_pv        <= 1'b0;
            r_pnb       <= 3'd0;
        end
        else
        begin
            r_req_ready <= w_left_next == 15'd0 && !w_lr_valid_next;
            r_evt_width <= w_req_take & w_req_bad;
            r_lr_valid  <= w_lr_valid_next;
            if (w_req_take)
            begin
                r_lr_vc  <= i_req_vc;
                r_lr_dt  <= i_req_dt;
                r_lr_wc  <= w_req_wc[15:0];
                r_fmt    <= w_req_fmt;
                r_bpb    <= w_req_bpb;
                r_last_n <= w_req_last_n;
                r_ppb     <= w_req_ppb;
                r_last_px <= w_req_last_px;
            end
            r_left      <= w_left_next;
            r_first     <= w_first_next;
            r_drop      <= w_drop_next;
            r_pix_ready <= w_pix_ready_next;
            r_evt_nb    <= w_pix_take & ~r_drop & (i_pix_nb != w_pix_px);

            r_a_valid <= w_a_valid_next;
            if (w_pix_take)
            begin
                r_a_data <= w_packed & w_mask;
                r_a_n    <= w_pix_n;
                r_a_last <= w_pix_last;
            end

            r_q      <= w_q_next;
            r_qn     <= w_qn_next;
            r_q_last <= w_q_last_next;
            r_pv     <= w_qn_next >= 5'd4 || (w_q_last_next && w_qn_next != 5'd0);
            r_pnb    <= w_qn_next >= 5'd4 ? 3'd4 : w_qn_next[2:0];
        end
    end

    assign o_req_ready     = r_req_ready;
    assign o_pix_ready     = r_pix_ready;
    assign o_evt_width     = r_evt_width;
    assign o_evt_nb        = r_evt_nb;
    assign o_llp_req_valid = r_lr_valid;
    assign o_llp_req_vc    = r_lr_vc;
    assign o_llp_req_dt    = r_lr_dt;
    assign o_llp_req_wc    = r_lr_wc;
    assign o_llp_pay_valid = r_pv;
    assign o_llp_pay_data  = r_q[31:0];
    assign o_llp_pay_nb    = r_pnb;
endmodule

`default_nettype wire
`endif
