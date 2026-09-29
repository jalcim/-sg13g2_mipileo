// Armement de `recherche` par un compteur sur Clk Système, une lane (armement retenu le 27/09/2026 : compteur, Clk
// Système à 125 MHz, N = 13 ; tempo_recherche.md et campagne 2026-09-27_1919_iverilog_4c9dc955_compteur de la
// branche claude/l22-synchro-b8). Une instance par lane ; instancié par aucun top pour l'instant.
//
// - hspr : LP-00 détecté par la SM LP du PHY (HSPR), asynchrone ; il retombe au retour en LP (LP-11, fin du burst) ;
// - deux bascules sur Clk Système (lm_sync_niveau de lm_cdc.v) : HSPR resynchronisé, 1 à 2 périodes après HSPR ;
// - un décompteur, chargé tant que HSPR resynchronisé est bas ;
// - `recherche` : registre (sans glitch), monte N périodes après HSPR resynchronisé, retombe avec lui.
//
// Latences, T = période de Clk Système, t_d = instant où HSPR monte ou retombe (vérifiées par tb_lm_armement.v) :
// - montée : t_d + (N + 1) T à t_d + (N + 2) T, soit 112 à 120 ns après HSPR pour N = 13 à 125 MHz ;
// - chute : t_d + 2 T à t_d + 3 T.
// Une borne est atteinte exactement seulement si HSPR change exactement sur un front de Clk Système (métastabilité).
// `recherche` va ensuite vers l'entrée recherche de lm_top_l22t (SIt) ou lm_top_l22 (SI), qui le repasse par deux
// bascules sur W (RECHERCHE_SYNC = 1) ; SIt l'écrit dans la FIFO avec les mots. La fenêtre d'armement est définie à
// l'arrivée sur ces deux bascules : ce passage y est déjà compté. Avec l'option D de D3 (lm_aligneur.v), elle vaut
// [G + L_d − 9 UI ; S − 12 UI + L_d[ (G = 85 ns + 6 UI, S = 145 ns + 10 UI, depuis le début de T_HS-PREPARE ; L_d,
// âge du mot quand W le capte). Borne basse mesurée le 28/09/2026 (tests/armement/borne_basse.py) ; celle de la revue,
// G − 12 UI + L_d, et la règle « pas avant G » du choix 9 datent d'avant la tolérance d'un bit, et ne suffisent pas.
// À 125 MHz et N = 13 (montée 112 ns après HSPR au plus tôt), la borne basse tient, latence de HSPR nulle, pour
// L_d ≤ 30 UI à 1000 Mb/s, 22 UI à 728 Mb/s, 15 UI à 456 Mb/s et 9 UI à 250 Mb/s par lane
// (analyse/questions_ouvertes/armement_borne_basse.md).
//
// Consigne : N = N_DEFAUT (13) si PROGRAMMABLE = 0 ; sinon l'entrée `consigne` (registre de configuration, statique
// pendant un burst ; 0 vaut 1). N se règle selon le débit par lane, L_d et la fréquence de Clk Système.
// Clk Système doit tourner pendant tout le SoT.
`default_nettype none

module lm_armement #(
    parameter LARGEUR      = 6,                 // largeur du décompteur (N jusqu'à 2^LARGEUR - 1)
    parameter N_DEFAUT     = 13,                // périodes de Clk Système après HSPR resynchronisé
    parameter PROGRAMMABLE = 0,                 // 1 : N pris sur l'entrée consigne
    parameter SYNC         = 2                  // bascules de HSPR : 2, ou 3 (SYNC3 : montée et chute de `recherche`
                                                // un cycle de Clk Système plus tard ; N se recale, voir sync3.md)
) (
    input  wire               clk,              // Clk Système
    input  wire               rst_n,            // reset asynchrone, relâché sur clk (lm_sync_reset)
    input  wire [LARGEUR-1:0] consigne,         // utilisée si PROGRAMMABLE = 1
    input  wire               hspr,             // asynchrone
    output reg                recherche         // domaine Clk Système, registre
);
    localparam [LARGEUR-1:0] N_FIXE = N_DEFAUT;
    wire                hspr_s;
    wire [LARGEUR-1:0]  n = PROGRAMMABLE ? consigne : N_FIXE;
    reg  [LARGEUR-1:0]  reste;

    lm_sync_niveau #(.W(1), .SYNC(SYNC)) sync (.clk(clk), .rst_n(rst_n), .d(hspr), .q(hspr_s));

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            reste     <= {LARGEUR{1'b0}};
            recherche <= 1'b0;
        end else if (!hspr_s) begin
            reste     <= n;
            recherche <= 1'b0;
        end else begin
            if (reste != {LARGEUR{1'b0}}) reste <= reste - 1'b1;
            recherche <= (reste <= 1);              // N-ième front où HSPR resynchronisé est vu haut
        end
endmodule

`default_nettype wire
