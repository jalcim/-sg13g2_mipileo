// Lanes activées par l'Enable, compactées en lanes logiques 0 à N-1 dans l'ordre croissant des lanes physiques.
// Calque de golden/lane_management.py : lanes_actives (configuration.md, choix_equipe.md §5).
// Combinatoire.
`default_nettype none

module lm_lanes_actives (
    input  wire [3:0] enable,       // un bit par lane physique (Q10, L28)
    output reg  [2:0] n,            // nombre de lanes activées
    output reg  [7:0] physique,     // physique[2i+1:2i] : lane physique de la lane logique i, pour i < n
    output reg  [7:0] logique,      // logique[2p+1:2p] : lane logique de la lane physique p, si elle est activée
    output wire       erreur        // aucune lane activée, ou N = 3 (reporté en bonus, Q11) : golden lève une exception
);
    integer p;

    always @* begin
        n        = 3'd0;
        physique = 8'd0;
        logique  = 8'd0;
        for (p = 0; p < 4; p = p + 1)
            if (enable[p]) begin
                physique[2*n +: 2] = p[1:0];
                logique[2*p +: 2]  = n[1:0];
                n = n + 3'd1;
            end
    end

    assign erreur = (n == 3'd0) || (n == 3'd3);
endmodule

`default_nettype wire
