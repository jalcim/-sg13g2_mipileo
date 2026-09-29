// Renvoi RX -> TX (prompt 056), niveaux N2 et N3 : marquage des paquets longs reçus en erreur, entre la sortie TX du
// LLP (tx_in_* de llp_top) et le tampon. llp_tx recalcule le CRC sur la charge qu'on lui donne : sur une charge fausse
// (CRC faux au RX, paquet tronqué puis bourré), le paquet renvoyé serait juste. Ici, le dernier octet d'un paquet long
// (CRC[15:8], toujours dans le battement tx_in_last, llp_tx.v) est inversé si le RX a rendu ce paquet en erreur : le
// CRC renvoyé est faux, jamais « réparé ».
//
// Verdicts : un par paquet long, dans l'ordre, poussés par renvoi_n2 ou renvoi_n3 à la fin RX du paquet (i_verdict,
// i_mauvais). Un paquet est long si son total n'est pas 4 (paquet court : 4 octets, llp_tx.v). Le dernier battement
// d'un paquet long attend son verdict (aucun cas connu : la fin RX précède de plusieurs cycles la sortie du CRC de
// llp_tx). Paquets courts : passent tels quels.
`default_nettype none

module renvoi_marque (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_verdict,
    input  wire        i_mauvais,
    input  wire        i_valid,
    output wire        o_ready,
    input  wire [31:0] i_data,
    input  wire [2:0]  i_nb,
    input  wire        i_last,
    input  wire [16:0] i_total,
    output wire        o_valid,
    input  wire        i_ready,
    output wire [31:0] o_data,
    output wire [2:0]  o_nb,
    output wire        o_last,
    output wire [16:0] o_total,
    output wire        o_evt_marque,    // un paquet sort marqué (une période)
    output wire        o_debord         // verdict perdu : file pleine (jamais attendu)
);
    reg  [3:0] r_file;                  // verdicts, le plus ancien en [0]
    reg  [2:0] r_n;

    wire       w_long  = i_total != 17'd4;
    wire       w_fin   = i_last & w_long;
    wire       w_bloq  = w_fin & (r_n == 3'd0);
    wire       w_prend = o_valid & i_ready & w_fin;
    wire       w_marq  = w_fin & r_file[0];
    wire [31:0] w_masque = 32'hFF << {i_nb - 3'd1, 3'b000};

    assign o_valid = i_valid & ~w_bloq;
    assign o_ready = i_ready & ~w_bloq;
    assign o_data  = w_marq ? i_data ^ w_masque : i_data;
    assign {o_nb, o_last, o_total} = {i_nb, i_last, i_total};
    assign o_evt_marque = w_prend & r_file[0];
    assign o_debord = i_verdict & (r_n == 3'd4) & ~w_prend;

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            r_file <= 4'd0;
            r_n    <= 3'd0;
        end else begin
            case ({i_verdict & ~o_debord, w_prend})
                2'b10: begin
                    r_file[r_n[1:0]] <= i_mauvais;
                    r_n <= r_n + 3'd1;
                end
                2'b01: begin
                    r_file <= {1'b0, r_file[3:1]};
                    r_n <= r_n - 3'd1;
                end
                2'b11: begin
                    r_file <= {1'b0, r_file[3:1]};
                    r_file[r_n[1:0] - 2'd1] <= i_mauvais;
                end
                default: ;
            endcase
        end
endmodule

`default_nettype wire
