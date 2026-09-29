// Passages d'horloge (CDC) de lm_top_l22 : horloge de mot W (fournie par le D-PHY, libre mais arrêtée entre deux
// trames quand la clock lane n'est pas continue) vers Clk Système, et reset.
// - lm_sync_reset : reset asynchrone à l'assertion, relâché de façon synchrone (SYNC bascules, 2 par défaut) dans le
//   domaine d'arrivée ;
// - lm_sync_niveau : niveau, SYNC bascules par bit (2 par défaut) ; seulement pour des bits indépendants ou lents
//   (verrou par lane) ;
// SYNC = 3 (variante SYNC3, analyse/reponses/sync3.md) : une bascule de plus, un cycle d'arrivée de latence en plus,
// temps de résolution d'une période de plus ; SYNC = 2 : RTL d'avant, au cycle près (preuve analyse/sync3/).
// - lm_sync_impulsion : impulsion d'une période du domaine de départ -> bascule qui change d'état, deux bascules, front
//   détecté dans le domaine d'arrivée ; deux impulsions doivent être séparées d'au moins trois périodes d'arrivée.
`default_nettype none

module lm_sync_reset #(
    parameter SYNC = 2              // bascules du relâchement : 2 ou 3 (SYNC3)
) (
    input  wire clk,
    input  wire rst_n,              // reset asynchrone, actif bas
    output wire rst_sync_n          // relâché SYNC fronts de clk après rst_n
);
    reg [SYNC-1:0] r;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) r <= {SYNC{1'b0}};
        else        r <= {r[SYNC-2:0], 1'b1};
    assign rst_sync_n = r[SYNC-1];
endmodule

module lm_sync_niveau #(
    parameter W    = 1,
    parameter SYNC = 2              // bascules par bit : 2 ou 3 (SYNC3)
) (
    input  wire         clk,        // domaine d'arrivée
    input  wire         rst_n,
    input  wire [W-1:0] d,          // domaine de départ
    output wire [W-1:0] q
);
    reg [W-1:0] s1, s2;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            s1 <= {W{1'b0}};
            s2 <= {W{1'b0}};
        end else begin
            s1 <= d;
            s2 <= s1;
        end
    generate
        if (SYNC >= 3) begin : trois
            reg [W-1:0] s3;         // troisième bascule, câblée directement derrière s2
            always @(posedge clk or negedge rst_n)
                if (!rst_n) s3 <= {W{1'b0}};
                else        s3 <= s2;
            assign q = s3;
        end else begin : deux
            assign q = s2;
        end
    endgenerate
endmodule

module lm_sync_impulsion (
    input  wire clk_a,              // domaine de départ
    input  wire rst_a_n,
    input  wire impulsion_a,        // une période de clk_a
    input  wire clk_b,              // domaine d'arrivée
    input  wire rst_b_n,
    output wire impulsion_b         // une période de clk_b
);
    reg bascule_a;
    always @(posedge clk_a or negedge rst_a_n)
        if (!rst_a_n)         bascule_a <= 1'b0;
        else if (impulsion_a) bascule_a <= !bascule_a;

    reg s1, s2, s3;
    always @(posedge clk_b or negedge rst_b_n)
        if (!rst_b_n) begin
            s1 <= 1'b0; s2 <= 1'b0; s3 <= 1'b0;
        end else begin
            s1 <= bascule_a;
            s2 <= s1;
            s3 <= s2;
        end
    assign impulsion_b = s2 ^ s3;
endmodule

`default_nettype wire
