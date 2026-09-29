// Taille de chaque lane, indexée par lane physique : ⌊TOTAL/N⌋ octets, plus un pour les TOTAL mod N premières
// lanes logiques (L20, interface_tx.md §2). Calque de golden : tailles_par_lane, indexé comme mots_fifo_tx.
// Combinatoire. N = 1, 2 ou 4 : la division est un décalage.
// Les quotients et leurs incréments ne dépendent que de TOTAL : ils se calculent en parallèle du décodage d'Enable, qui
// ne fait plus que sélectionner (27/09/2026 : l'incrément en série derrière le décodage était le pire chemin de lm_top
// à 300 MHz). Avec N = 1, le reste est nul : pas d'incrément.
`default_nettype none

module lm_tailles (
    input  wire [3:0]  enable,
    input  wire [16:0] total,        // octets du paquet ; au plus 4 + 65535 + 2 (golden : TAILLE_MAX_LANE)
    output reg  [67:0] tailles,      // tailles[17p+16:17p] : taille de la lane physique p, 0 si elle est éteinte
    output wire        erreur        // configuration d'Enable invalide (lm_lanes_actives)
);
    wire [2:0] n;
    wire [7:0] physique, logique;

    lm_lanes_actives lanes (.enable(enable), .n(n), .physique(physique), .logique(logique), .erreur(erreur));

    wire [16:0] q2 = total >> 1, q4 = total >> 2;
    wire [16:0] q2p = q2 + 17'd1, q4p = q4 + 17'd1;
    integer     p;

    always @* begin
        tailles = 68'd0;
        for (p = 0; p < 4; p = p + 1)
            if (enable[p])
                case (n)
                    3'd2:    tailles[17*p +: 17] = logique[2*p +: 2] < {1'b0, total[0]} ? q2p : q2;
                    3'd4:    tailles[17*p +: 17] = logique[2*p +: 2] < total[1:0] ? q4p : q4;
                    default: tailles[17*p +: 17] = total;
                endcase
    end
endmodule

`default_nettype wire
