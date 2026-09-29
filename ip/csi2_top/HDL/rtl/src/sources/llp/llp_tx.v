// Tête TX du LLP CSI-2 : fabrique le paquet (en-tête et ECC, charge, CRC-16) et le passe au Lane Management par
// battements de 4 octets, poignée de main tx_in_valid / tx_in_ready (spec d'interface LM-LLP, §4).
// Toutes les sorties sortent de bascules : aucun chemin combinatoire ne va d'une entrée à une sortie.
//
// Découpage, un étage par front :
// - H, en-tête : la requête acceptée est rangée telle quelle. L'ECC et total se calculent de H vers O.
// - P, charge : tampon de rattrapage de deux mots, principal et débordement, comme lm_etage. o_pay_ready est
//   calculé un cycle en avance : débordement vide au cycle suivant, et mots restant à prendre. llp_tx compte les
//   mots d'après le WC de la requête et marque chaque mot à l'entrée : premier, dernier, octets pris.
// - C : le mot passe de P à C, et le CRC avance de ce mot au même front. Sur ce chemin, l'arbre de XOR de
//   llp_crc_step seul, derrière le choix de 0xFFFF pour le premier mot.
// - O, sorties o_tx_* : le battement suivant est l'en-tête, le mot de C avec le CRC collé derrière ses octets, ou
//   le reste du CRC qui n'y a pas tenu. Des multiplexeurs seulement, aucun calcul de CRC.
// Latence : requête courte vers o_tx_valid, 2 cycles ; mot de charge pris vers o_tx_valid, 3 cycles.
// L'en-tête d'un paquet long n'est chargé qu'une fois son premier mot dans P ou C : la sortie ne marque ensuite de
// pause que si l'application laisse un trou dans la charge. Le budget de pause (§4.5) est tout entier à elle.
// La charge d'un paquet n'est prise qu'après sa requête, la requête suivante qu'une fois toute cette charge prise.
`ifndef __LLP_TX__
`define __LLP_TX__
`default_nettype none

module llp_tx #(
    parameter INIT_CYCLES = 20000       // cycles entre la chute de tx_init et o_init_done, de 1 à 32 768 (§4.6)
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_req_valid,
    output wire        o_req_ready,
    input  wire [1:0]  i_req_vc,
    input  wire [5:0]  i_req_dt,        // 0x00 à 0x0F : paquet court
    input  wire [15:0] i_req_wc,        // WC du paquet long, champ de données du paquet court
    input  wire        i_pay_valid,
    output wire        o_pay_ready,
    input  wire [31:0] i_pay_data,      // premier octet en [7:0]
    input  wire [2:0]  i_pay_nb,        // non lu : llp_tx compte la charge d'après le WC
    output wire        o_init_done,
    output wire        o_tx_valid,
    input  wire        i_tx_ready,
    output wire [31:0] o_tx_data,
    output wire [2:0]  o_tx_nb,
    output wire        o_tx_last,
    output wire [16:0] o_tx_total,
    output wire        o_tx_init
);
    localparam [1:0] PH_HDR  = 2'd0;    // O attend l'en-tête du paquet suivant
    localparam [1:0] PH_PAY  = 2'd1;    // O prend les mots de C
    localparam [1:0] PH_TAIL = 2'd2;    // O émet le reste du CRC

    // tx_init et attente de la fin de l'initialisation D-PHY
    reg        r_tx_init;
    reg [14:0] r_init_cnt;
    reg        r_init_done;
    // H : en-tête accepté
    reg        r_req_ready;
    reg        r_hdr_full;
    reg [1:0]  r_hdr_vc;
    reg [5:0]  r_hdr_dt;
    reg [15:0] r_hdr_wc;
    reg        r_hdr_short;
    reg        r_hdr_nopay;             // paquet court, ou long de WC nul
    // compte de la charge à prendre
    reg        r_pay_ready;
    reg [14:0] r_left;                  // mots restant à prendre, 16 384 au plus
    reg        r_first;                 // le prochain mot pris est le premier de sa charge
    reg [2:0]  r_rest;                  // octets du dernier mot, 1 à 4
    // P : mot principal (pm) et débordement (ps)
    reg        r_pm_valid;
    reg [31:0] r_pm_data;
    reg [2:0]  r_pm_nb;
    reg        r_pm_first;
    reg        r_pm_last;
    reg        r_ps_valid;
    reg [31:0] r_ps_data;
    reg [2:0]  r_ps_nb;
    reg        r_ps_first;
    reg        r_ps_last;
    // C
    reg        r_c_valid;
    reg [31:0] r_c_data;
    reg [2:0]  r_c_nb;
    reg        r_c_last;
    reg [15:0] r_crc;                   // CRC de la charge jusqu'au mot de C compris
    // O
    reg        r_tx_valid;
    reg [31:0] r_tx_data;
    reg [2:0]  r_tx_nb;
    reg        r_tx_last;
    reg [16:0] r_tx_total;
    reg [1:0]  r_phase;
    reg [15:0] r_tail;                  // reste du CRC, premier octet en [7:0]
    reg [2:0]  r_tail_nb;

    wire        w_init_end;
    wire        w_init_next;
    wire        w_req_take;
    wire        w_pay_take;
    wire [14:0] w_req_words;
    wire [14:0] w_left_next;
    wire        w_in_last;
    wire [2:0]  w_in_nb;
    wire        w_o_free;
    wire        w_hdr_go;
    wire        w_c_go;
    wire        w_tail_go;
    wire        w_c_free;
    wire        w_p_go;
    wire        w_pm_free;
    wire        w_ps_next;
    wire        w_hdr_full_next;
    wire [5:0]  w_ecc;
    wire [31:0] w_hdr_word;
    wire [16:0] w_total;
    wire [15:0] w_crc;
    wire        w_c_end;
    wire [31:0] w_c_word;
    wire [2:0]  w_c_nb;
    wire [15:0] w_c_tail;
    wire [2:0]  w_c_tail_nb;

    // tx_init tombe au premier front après le reset ; o_init_done monte INIT_CYCLES cycles plus tard
    assign w_init_end  = {17'd0, r_init_cnt} == INIT_CYCLES - 1;
    assign w_init_next = r_init_done | (~r_tx_init & w_init_end);

    assign w_req_take  = i_req_valid & r_req_ready;
    assign w_pay_take  = i_pay_valid & r_pay_ready;
    assign w_req_words = i_req_dt[5:4] == 2'b00 ? 15'd0 : {1'b0, i_req_wc[15:2]} + {14'd0, |i_req_wc[1:0]};
    assign w_left_next = w_req_take ? w_req_words : r_left - {14'd0, w_pay_take};
    assign w_in_last   = r_left == 15'd1;
    assign w_in_nb     = w_in_last ? r_rest : 3'd4;

    // Avancement des étages, de la sortie vers l'entrée
    assign w_o_free  = ~r_tx_valid | i_tx_ready;
    assign w_hdr_go  = w_o_free & (r_phase == PH_HDR) & r_hdr_full & (r_hdr_nopay | r_c_valid | r_pm_valid);
    assign w_c_go    = w_o_free & (r_phase == PH_PAY) & r_c_valid;
    assign w_tail_go = w_o_free & (r_phase == PH_TAIL);
    assign w_c_free  = ~r_c_valid | w_c_go;
    assign w_p_go    = r_pm_valid & w_c_free;
    assign w_pm_free = ~r_pm_valid | w_p_go;
    assign w_ps_next = ~w_pm_free & (r_ps_valid | w_pay_take);
    assign w_hdr_full_next = w_req_take | (r_hdr_full & ~w_hdr_go);

    // En-tête : DI, WC poids faible, WC poids fort, ECC avec ECC[7:6] = 0
    llp_ecc_gen u_ecc (
        .i_data ({r_hdr_wc, r_hdr_vc, r_hdr_dt}),
        .o_ecc  (w_ecc)
    );

    assign w_hdr_word = {2'b00, w_ecc, r_hdr_wc, r_hdr_vc, r_hdr_dt};
    assign w_total    = r_hdr_short ? 17'd4 : {1'b0, r_hdr_wc} + 17'd6;

    llp_crc_step u_crc (
        .i_crc  (r_pm_first ? 16'hFFFF : r_crc),
        .i_data (r_pm_data),
        .i_nb   (r_pm_nb),
        .o_crc  (w_crc)
    );

    // Mot de C vers O : le CRC suit les octets du dernier mot, sans bourrage ; ce qui ne tient pas part après
    assign w_c_end     = r_c_last & (r_c_nb <= 3'd2);
    assign w_c_word    = ~r_c_last      ? r_c_data
                       : r_c_nb == 3'd1 ? {8'h00, r_crc, r_c_data[7:0]}
                       : r_c_nb == 3'd2 ? {r_crc, r_c_data[15:0]}
                       : r_c_nb == 3'd3 ? {r_crc[7:0], r_c_data[23:0]}
                       :                  r_c_data;
    assign w_c_nb      = w_c_end ? r_c_nb + 3'd2 : 3'd4;
    assign w_c_tail    = r_c_nb == 3'd3 ? {8'h00, r_crc[15:8]} : r_crc;
    assign w_c_tail_nb = r_c_nb == 3'd3 ? 3'd1 : 3'd2;

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
        begin
            r_tx_init   <= 1'b1;
            r_init_cnt  <= 15'd0;
            r_init_done <= 1'b0;
            r_req_ready <= 1'b0;
            r_hdr_full  <= 1'b0;
            r_hdr_vc    <= 2'd0;
            r_hdr_dt    <= 6'd0;
            r_hdr_wc    <= 16'd0;
            r_hdr_short <= 1'b0;
            r_hdr_nopay <= 1'b0;
            r_pay_ready <= 1'b0;
            r_left      <= 15'd0;
            r_first     <= 1'b0;
            r_rest      <= 3'd0;
            r_pm_valid  <= 1'b0;
            r_pm_data   <= 32'd0;
            r_pm_nb     <= 3'd0;
            r_pm_first  <= 1'b0;
            r_pm_last   <= 1'b0;
            r_ps_valid  <= 1'b0;
            r_ps_data   <= 32'd0;
            r_ps_nb     <= 3'd0;
            r_ps_first  <= 1'b0;
            r_ps_last   <= 1'b0;
            r_c_valid   <= 1'b0;
            r_c_data    <= 32'd0;
            r_c_nb      <= 3'd0;
            r_c_last    <= 1'b0;
            r_crc       <= 16'd0;
            r_tx_valid  <= 1'b0;
            r_tx_data   <= 32'd0;
            r_tx_nb     <= 3'd0;
            r_tx_last   <= 1'b0;
            r_tx_total  <= 17'd0;
            r_phase     <= PH_HDR;
            r_tail      <= 16'd0;
            r_tail_nb   <= 3'd0;
        end
        else
        begin
            r_tx_init <= 1'b0;
            if (!r_tx_init && !r_init_done)
                r_init_cnt <= r_init_cnt + 15'd1;
            r_init_done <= w_init_next;

            // H et compte de la charge
            r_req_ready <= w_init_next & (w_left_next == 15'd0) & ~w_hdr_full_next;
            r_pay_ready <= ~w_ps_next & (w_left_next != 15'd0);
            r_hdr_full  <= w_hdr_full_next;
            r_left      <= w_left_next;
            if (w_req_take)
            begin
                r_hdr_vc    <= i_req_vc;
                r_hdr_dt    <= i_req_dt;
                r_hdr_wc    <= i_req_wc;
                r_hdr_short <= i_req_dt[5:4] == 2'b00;
                r_hdr_nopay <= i_req_dt[5:4] == 2'b00 || i_req_wc == 16'd0;
                r_rest      <= i_req_wc[1:0] == 2'd0 ? 3'd4 : {1'b0, i_req_wc[1:0]};
            end
            if (w_req_take || w_pay_take)
                r_first <= w_req_take;

            // P : le principal prend le débordement s'il est plein, sinon l'entrée ; bloqué, le débordement la prend
            if (w_pm_free)
            begin
                r_pm_valid <= r_ps_valid | w_pay_take;
                if (r_ps_valid)
                    {r_pm_data, r_pm_nb, r_pm_first, r_pm_last} <= {r_ps_data, r_ps_nb, r_ps_first, r_ps_last};
                else if (w_pay_take)
                    {r_pm_data, r_pm_nb, r_pm_first, r_pm_last} <= {i_pay_data, w_in_nb, r_first, w_in_last};
            end
            else if (w_pay_take)
                {r_ps_data, r_ps_nb, r_ps_first, r_ps_last} <= {i_pay_data, w_in_nb, r_first, w_in_last};
            r_ps_valid <= w_ps_next;

            // C : le CRC avance du mot qui entre
            if (w_c_free)
            begin
                r_c_valid <= w_p_go;
                if (w_p_go)
                begin
                    r_c_data <= r_pm_data;
                    r_c_nb   <= r_pm_nb;
                    r_c_last <= r_pm_last;
                    r_crc    <= w_crc;
                end
            end

            // O : un battement de plus dès que le précédent est pris, tenu sinon
            if (w_o_free)
            begin
                r_tx_valid <= w_hdr_go | w_c_go | w_tail_go;
                if (w_hdr_go)
                begin
                    r_tx_data  <= w_hdr_word;
                    r_tx_nb    <= 3'd4;
                    r_tx_last  <= r_hdr_short;
                    r_tx_total <= w_total;
                    r_phase    <= r_hdr_short ? PH_HDR : r_hdr_nopay ? PH_TAIL : PH_PAY;
                    r_tail     <= 16'hFFFF;     // CRC d'une charge vide, émis si WC = 0
                    r_tail_nb  <= 3'd2;
                end
                else if (w_c_go)
                begin
                    r_tx_data <= w_c_word;
                    r_tx_nb   <= w_c_nb;
                    r_tx_last <= w_c_end;
                    r_phase   <= ~r_c_last ? PH_PAY : w_c_end ? PH_HDR : PH_TAIL;
                    r_tail    <= w_c_tail;
                    r_tail_nb <= w_c_tail_nb;
                end
                else if (w_tail_go)
                begin
                    r_tx_data <= {16'h0000, r_tail};
                    r_tx_nb   <= r_tail_nb;
                    r_tx_last <= 1'b1;
                    r_phase   <= PH_HDR;
                end
            end
        end
    end

    assign o_req_ready = r_req_ready;
    assign o_pay_ready = r_pay_ready;
    assign o_init_done = r_init_done;
    assign o_tx_valid  = r_tx_valid;
    assign o_tx_data   = r_tx_data;
    assign o_tx_nb     = r_tx_nb;
    assign o_tx_last   = r_tx_last;
    assign o_tx_total  = r_tx_total;
    assign o_tx_init   = r_tx_init;
endmodule

`default_nettype wire
`endif
