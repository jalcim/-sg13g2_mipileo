// Renvoi RX -> TX (prompt 056) : marquage des trames (N4) et compteurs, sans broche, par un paquet court générique
// (DT 0x08 à 0x0F, CSI-2 « Generic Short Packet ») sur un VC réservé, au plus un par trame, après chaque FE de
// llp_trame. Le niveau actif (N1, N2 ou N3) le glisse entre deux paquets.
//
// Champ de données (16 bits) :
//   [15]    trame_fe_ok de la trame fermée (aucune erreur de trame)
//   [14:13] VC de cette trame
//   [12]    une erreur d'en-tête de trame (trame_err_hdr) depuis le statut précédent
//   [11]    une erreur de fin de ligne (trame_err_end)
//   [10]    une perte (trame_loss)
//   [9]     un burst_error tardif (trame_late)
//   [8]     un paquet perdu, bourré ou marqué par le renvoi
//   [7:0]   compteur k, saturé à 255 ; k tourne de 0 à 7 d'un statut au suivant, et le DT vaut 0x08 + k :
//           0 ECC non corrigeable, 1 CRC, 2 tronqués, 3 bursts en erreur, 4 types réservés, 5 sot_err (llp_top),
//           6 trames en erreur (llp_trame), 7 paquets perdus par le renvoi.
// Un FE qui arrive avant que le statut précédent soit parti le remplace (au plus un statut en attente).
`default_nettype none

module renvoi_statut #(
    parameter STATUT = 1,               // 0 : aucun statut
    parameter CNT_W  = 16
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              i_actif,   // renvoi en cours (N1 à N3)
    input  wire              i_fe,
    input  wire              i_fe_ok,
    input  wire [1:0]        i_fe_vc,
    input  wire              i_err_hdr,
    input  wire              i_err_end,
    input  wire              i_loss,
    input  wire              i_late,
    input  wire              i_renvoi,
    input  wire [8*CNT_W-1:0] i_cnt,    // compteur k en [CNT_W*k +: CNT_W]
    output wire              o_valid,
    input  wire              i_ready,
    output wire [5:0]        o_dt,
    output wire [15:0]       o_data
);
    generate
        if (STATUT != 0) begin : g_statut
            reg        r_valid;
            reg [15:0] r_data;
            reg [2:0]  r_k;
            reg [4:0]  r_acc;

            wire [CNT_W-1:0] w_cnt = i_cnt[CNT_W*r_k +: CNT_W];
            wire [7:0]       w_sat = |w_cnt[CNT_W-1:8] ? 8'hFF : w_cnt[7:0];
            wire [4:0]       w_evt = {i_err_hdr, i_err_end, i_loss, i_late, i_renvoi};

            assign o_valid = r_valid;
            assign o_dt    = {3'b001, r_k - {2'b00, r_valid}};
            assign o_data  = r_data;

            always @(posedge clk or negedge rst_n)
                if (!rst_n) begin
                    r_valid <= 1'b0;
                    r_data  <= 16'd0;
                    r_k     <= 3'd0;
                    r_acc   <= 5'd0;
                end else if (!i_actif) begin
                    r_valid <= 1'b0;
                    r_acc   <= 5'd0;
                end else begin
                    if (r_valid & i_ready)
                        r_valid <= 1'b0;
                    if (i_fe) begin
                        r_valid <= 1'b1;
                        r_data  <= {i_fe_ok, i_fe_vc, r_acc | w_evt, w_sat};
                        r_k     <= r_k + 3'd1;
                        r_acc   <= 5'd0;
                    end else
                        r_acc <= r_acc | w_evt;
                end
        end else begin : g_sans
            assign o_valid = 1'b0;
            assign o_dt    = 6'd0;
            assign o_data  = 16'd0;
            wire w_non_lus = &{1'b0, clk, rst_n, i_actif, i_fe, i_fe_ok, i_fe_vc, i_err_hdr, i_err_end, i_loss, i_late,
                               i_renvoi, i_cnt, i_ready};
        end
    endgenerate
endmodule

`default_nettype wire
