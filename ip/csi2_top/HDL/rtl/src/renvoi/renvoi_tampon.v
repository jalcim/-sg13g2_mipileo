// Renvoi RX -> TX (prompt 056) : tampon élastique devant l'entrée TX du LM (tx_in_*), sur Clk Système.
// Le flux renvoyé ne peut pas s'arrêter (le RX n'a pas de contre-pression, D11) ; ce tampon absorbe ce que la LDF ne
// prend pas : le départ de chaque paquet (CALCUL, puis N mots d'en-tête de tailles, REMISE_TAILLE = 1) et le plein de
// la FIFO TX quand l'horloge RX est plus rapide que Clock TX. Sa sortie suit la poignée de main de tx_in_*.
//
// Préremplissage (PREREMPLI, en octets) : le premier battement d'un paquet n'est présenté au LM que quand le tampon
// tient au moins PREREMPLI octets, ou le dernier battement du paquet. Le PHY TX part dès qu'un mot de données est dans
// la FIFO TX (départ non_vide, a_trancher_5) : ce qui est retenu ici entre dans la FIFO TX d'un coup, et s'ajoute
// à l'avance prise pendant le SoT. 0 : aucun préremplissage.
//
// o_max : remplissage maximal (battements) depuis le reset, pour les bancs.
`default_nettype none

module renvoi_tampon #(
    parameter PROF      = 16,           // battements, puissance de 2
    parameter PREREMPLI = 0             // octets
) (
    input  wire        clk,
    input  wire        rst_n,
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
    output reg  [$clog2(PROF):0] o_max
);
    localparam A = $clog2(PROF);

    reg  [52:0]  r_mem [0:PROF-1];
    reg  [A-1:0] r_lec, r_ecr;
    reg  [A:0]   r_n;                   // battements
    reg  [A+2:0] r_octets;              // octets
    reg  [A:0]   r_fins;                // derniers battements de paquet dans le tampon
    reg          r_premier;             // le prochain battement sorti est le premier de son paquet

    wire         w_entre = i_valid & o_ready;
    wire         w_sort  = o_valid & i_ready;
    wire [52:0]  w_tete  = r_mem[r_lec];
    wire         w_libre = !r_premier || PREREMPLI == 0 || r_fins != {(A+1){1'b0}}
                           || {{(29-A){1'b0}}, r_octets} >= PREREMPLI;

    assign o_ready = r_n != PROF[A:0];
    assign o_valid = r_n != {(A+1){1'b0}} && w_libre;
    assign {o_data, o_nb, o_last, o_total} = w_tete;

    always @(posedge clk)
        if (w_entre)
            r_mem[r_ecr] <= {i_data, i_nb, i_last, i_total};

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            r_lec     <= {A{1'b0}};
            r_ecr     <= {A{1'b0}};
            r_n       <= {(A+1){1'b0}};
            r_octets  <= {(A+3){1'b0}};
            r_fins    <= {(A+1){1'b0}};
            r_premier <= 1'b1;
            o_max     <= {(A+1){1'b0}};
        end else begin
            if (w_entre)
                r_ecr <= r_ecr + 1'b1;
            if (w_sort) begin
                r_lec     <= r_lec + 1'b1;
                r_premier <= o_last;
            end
            r_n      <= r_n + {{A{1'b0}}, w_entre} - {{A{1'b0}}, w_sort};
            r_octets <= r_octets + (w_entre ? {{A{1'b0}}, i_nb} : {(A+3){1'b0}})
                                 - (w_sort ? {{A{1'b0}}, o_nb} : {(A+3){1'b0}});
            r_fins   <= r_fins + {{A{1'b0}}, w_entre & i_last} - {{A{1'b0}}, w_sort & o_last};
            if (r_n > o_max)
                o_max <= r_n;
        end
endmodule

`default_nettype wire
