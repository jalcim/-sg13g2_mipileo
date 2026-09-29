// Point 2 : remise à zéro de la FIFO RX entre deux bursts (L14 : « La Fifo est réinitialisée entre deux bursts »).
// Calque de golden/variantes.py : simule_rx (REMISE_RX).
// - au_sot_suivant : la remise est faite par le PHY au SoT suivant ; le Lane Management n'émet rien ;
// - par_lecteur : le Lane Management émet fifo_raz quand le HS est retombé (statut resynchronisé) et la FIFO vide ;
//   les mots d'un burst suivant écrits avant cette remise sont perdus ;
// - jamais : aucune remise ; les bursts se suivent dans la FIFO sans séparation.
`default_nettype none

module lm_raz_rx #(
    parameter STRATEGIE = 1         // 0 au_sot_suivant ; 1 par_lecteur ; 2 jamais
) (
    input  wire clk,
    input  wire rst_n,
    input  wire hs,                 // HS des lanes du masque, resynchronisé (lm_statut_resync)
    input  wire fifo_empty,
    output reg  fifo_raz            // impulsion d'une période de Clk Système
);
    reg hs_d, arme;

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            hs_d     <= 1'b0;
            arme     <= 1'b0;
            fifo_raz <= 1'b0;
        end else begin
            hs_d     <= hs;
            fifo_raz <= 1'b0;
            if (STRATEGIE == 1) begin
                if (hs_d && !hs)
                    arme <= 1'b1;
                if (arme && !hs && fifo_empty) begin
                    fifo_raz <= 1'b1;
                    arme     <= 1'b0;
                end
            end
        end
endmodule

`default_nettype wire
