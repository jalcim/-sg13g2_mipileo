// Aligneur de référence depuis le plan de correction (analyse/plan_corrections_revue_lm.md, T6) : reprise de
// rtl/propositions/lm_aligneur.v (session web, 27/09/2026), réglages par défaut = option D de D3 seule (choix 12 ter de
// connaissances/decisions.md). Golden : golden/aligneur_l22.py (aligne, aligne_temps) ; mesures et réglages :
// analyse/reponses/fenetre_zeros.md, golden/aligneur_fz.py, rtl/tests/propositions/.
//
// Aligneur L22, une lane : cherche le 0xB8 dans les mots bruts du PHY et livre les octets alignés. Domaine de W (ou de
// Clk Système avec `en`, lm_top_l22t). Mot brut de 8 bits par pas, bit 0 reçu le premier. Latence : 3 pas.
//
// Option D (golden/aligneur_d3.py, option D), TOLERANCE = 1 :
// - motif de 16 bits, 8 zéros puis 0xB8, cherché sur les 8 décalages d'une fenêtre de 24 bits (3 mots) ;
// - correspondance exacte d'abord, sinon à un bit près (D-PHY v1.1 Table 5, RX-HS-Sync : « any single bit error
//   allowed ») ; plus petit décalage ; err_sot (ErrSotHS, une période) si le verrou est pris à un bit près ;
// - recherche bornée : elle se ferme si rien n'est trouvé au mot qui apporte le 2e bit à 1 compté, ni aux 2 mots
//   suivants ; le burst finit alors en err_sync (ErrSotSyncHS).
// TOLERANCE = 0 donne l'option E (correspondance exacte seulement).
// Correction FENETRE_ZEROS (chaque mécanisme réglable ; tout à 0, comportement des options D et E mesurées en D3) :
// - VALIDES : nombre de bits de fin du motif qui doivent avoir été reçus depuis la montée de `recherche`. À 16, un
//   décalage n'est comparé que si ses 16 bits ont été reçus : les bits vidés ne passent plus pour des zéros. À 0, la
//   fenêtre vidée compte comme 24 zéros (options D et E de D3, et RTL de référence).
// - PORTE : les bits à 1 ne comptent pour la fermeture qu'après PORTE zéros reçus d'affilée (le HS-zero) ; les bits
//   parasites capturés avant le HS-zero (settle, `recherche` en avance, âge du mot) ne ferment plus la recherche.
//   PORTE_MOTS : si la porte ne s'est pas ouverte au PORTE_MOTS-ième mot reçu, la recherche se ferme (0xB8 manqué :
//   `recherche` arrivée après le HS-zero). PORTE = 0 : pas de porte, tous les bits à 1 comptent.
// - VERROU_PORTE = 1 : le verrou lui-même n'est pris qu'une fois la porte ouverte, c'est-à-dire après PORTE zéros reçus
//   d'affilée : une charge qui contient « 8 zéros puis 0xB8 » avec moins de PORTE zéros devant (`recherche` arrivée
//   après le 0xB8, numéro de trame 0x00B8 d'un FS) ne verrouille plus. 0 : le verrou ne dépend que du motif.
//   Mesuré (campagne 2026-09-27_1909_..._d_hszero) : PORTE = 11 laisse passer « 00 B8 » (11 zéros) ; 16 et 20 non.
// - TOL_ZEROS (option D) : un verrou à un bit près n'est pris qu'après TOL_ZEROS zéros reçus d'affilée depuis la montée
//   de `recherche` (variante de repli du 27/09/2026) ; les verrous exacts ne changent pas. 0 : tolérance dès la montée.
// Réglages par défaut : option D seule (TOLERANCE = 1, tout le reste à 0), décision du 27/09/2026 : `recherche` est
// placée par le compteur d'armement dans [G + L_d − 9 UI ; S − 13 UI + L_d[ (G = 85 ns + 6 UI, S = 145 ns + 10 UI,
// depuis le début de T_HS-PREPARE ; L_d, âge du mot quand W le capte). Borne basse mesurée le 28/09/2026
// (tests/armement/borne_basse.py : L_d de 0 à 16 UI, 250 à 1500 Mb/s, settle aléatoire, tout à 1 ou adverse) : plus
// tôt, le mot capté à la montée contient des bits du settle, la fenêtre vidée et la tolérance en font un faux verrou,
// ou ferment la recherche avant le 0xB8. « Jamais avant G » ne suffit donc pas dès L_d > 9 UI (t_r = G + 1 UI,
// L_d = 12 UI : jusqu'à 2,4 % de faux et 9,2 % de manqués) ; t_r ≥ G + L_d suffit, avec 9 UI de marge.
// Option documentée « porte 16 » : VALIDES = 16, PORTE = 16, PORTE_MOTS = 5, VERROU_PORTE = 1. Elle rend sans danger un
// armement hors fenêtre (avant G, ou après le 0xB8) et un récepteur HS encore bruité après G ; en échange, il faut 16
// zéros reçus avant le premier bit à 1 du 0xB8 : `recherche` doit monter au plus tard vers S − 29 UI + L_d, et peut
// monter avant G (bruit toléré tant que la porte s'ouvre dans les 5 premiers mots).
// Hypothèses : PORTE et TOL_ZEROS valent 0 ou de 8 à 31 (une porte ne s'ouvre qu'au premier bit à 1 d'un mot, ou sur un
// mot nul) ; PORTE_MOTS de 0 à 15.
`default_nettype none

module lm_aligneur #(
    parameter TOLERANCE    = 1,
    parameter VALIDES      = 0,
    parameter PORTE        = 0,
    parameter PORTE_MOTS   = 0,
    parameter VERROU_PORTE = 0,
    parameter TOL_ZEROS    = 0
) (
    input  wire       clk_w,
    input  wire       rst_n,
    input  wire       en,
    input  wire       recherche,
    input  wire [7:0] mot,
    output reg        valide,
    output reg  [7:0] octet,
    output reg        verrou,           // 0xB8 trouvé, décalage figé (synched)
    output reg        actif,            // burst en cours, vu de l'étage 3
    output reg        err_sync,         // fin de burst sans verrou (ErrSotSyncHS), une période
    output reg        err_sot           // verrou pris à un bit près (ErrSotHS), une période ; toujours 0 si TOLERANCE = 0
);
    localparam [15:0] MOTIF = 16'hB800;             // bits 0 à 7 : zéros ; bits 8 à 15 : 0xB8
    localparam        RUN_W = 5;                     // PORTE, TOL_ZEROS <= 31
    localparam        RUN_MAX = PORTE > TOL_ZEROS ? PORTE : TOL_ZEROS;

    reg [23:0] fenetre, fenetre_2;
    reg        recherche_1, recherche_2;
    reg [1:0]  nmots;                   // mots reçus dans la fenêtre depuis la montée de recherche (saturé à 3)
    reg [7:0]  egal, proche;            // par décalage : exact ; à un bit près (TOLERANCE seulement), bits valides
    reg [2:0]  decalage;
    // fermeture (option D, avec porte)
    reg [RUN_W-1:0] run;                // zéros reçus d'affilée (saturé à PORTE)
    reg        porte;                   // PORTE zéros reçus d'affilée depuis la montée de recherche
    reg [3:0]  age;                     // mots reçus depuis la montée (saturé à 15)
    reg        porte_2;
    reg        tol_ok, tol_2;          // TOL_ZEROS zéros reçus d'affilée depuis la montée de recherche
    reg        un_1, deux_1, deux_2;    // un, deux bits à 1 comptés (après la porte)
    reg        tard_1, tard_2;          // porte fermée au PORTE_MOTS-ième mot
    reg [1:0]  compte;
    reg        ferme;

    // ------------------------------------------------------------------ étage 1, combinatoire : fermeture
    function [3:0] zeros_tete;           // bits à 0 avant le premier 1 (dans l'ordre de réception), 8 si mot nul
        input [7:0] m;
        integer i;
        begin
            zeros_tete = 4'd8;
            for (i = 7; i >= 0; i = i - 1)
                if (m[i]) zeros_tete = i[3:0];
        end
    endfunction
    function [3:0] zeros_queue;          // bits à 0 après le dernier 1, 8 si mot nul
        input [7:0] m;
        integer i;
        begin
            zeros_queue = 4'd8;
            for (i = 0; i <= 7; i = i + 1)
                if (m[i]) zeros_queue = 4'd7 - i[3:0];
        end
    endfunction

    wire [5:0] run_tete  = {1'b0, run} + {2'b0, zeros_tete(mot)};
    // seuils au moins égaux à 1 : à 0, le terme de tête vaut déjà 1, et la comparaison à 0 serait constante
    localparam PORTE_1 = PORTE > 0 ? PORTE : 1, TOL_ZEROS_1 = TOL_ZEROS > 0 ? TOL_ZEROS : 1;
    wire       ouvre     = (PORTE == 0) || porte || run_tete >= PORTE_1;   // porte ouverte au premier 1 du mot
    wire       a_un      = ouvre && mot != 8'd0;
    wire       a_deux    = ouvre && (mot & (mot - 8'd1)) != 8'd0;
    wire [5:0] run_suiv  = mot == 8'd0 ? {1'b0, run} + 6'd8 : {2'b0, zeros_queue(mot)};
    localparam RUN_MAX_1 = RUN_MAX > 0 ? RUN_MAX : 1;
    wire [RUN_W-1:0] run_sat = RUN_MAX == 0 ? {RUN_W{1'b0}} :
                               run_suiv >= RUN_MAX_1 ? RUN_MAX_1[RUN_W-1:0] : run_suiv[RUN_W-1:0];
    wire       tol_ouvre = TOL_ZEROS == 0 || tol_ok || run_tete >= TOL_ZEROS_1;
    wire       tard_c    = PORTE != 0 && PORTE_MOTS != 0 && !ouvre && {1'b0, age} + 5'd1 >= PORTE_MOTS;

    // ------------------------------------------------------------------ étage 2, combinatoire : les 8 comparaisons
    reg [7:0]  egal_c, proche_c;
    reg [15:0] ecart;
    integer    k;
    always @(*)
        for (k = 0; k < 8; k = k + 1) begin
            ecart       = fenetre[k +: 16] ^ MOTIF;
            // décalage k comparé si ses VALIDES derniers bits ont été reçus : k + 16 - VALIDES >= 24 - 8 * nmots
            egal_c[k]   = ecart == 16'd0 && k + 8 * nmots >= 8 + VALIDES;
            proche_c[k] = TOLERANCE != 0 && (ecart & (ecart - 16'd1)) == 16'd0 && k + 8 * nmots >= 8 + VALIDES;
        end

    // ------------------------------------------------------------------ étage 3, combinatoire : priorités
    reg        trouve, trouve_p;
    reg [2:0]  k_trouve, k_proche;
    integer    p;
    always @(*) begin
        trouve   = 1'b0;
        trouve_p = 1'b0;
        k_trouve = 3'd0;
        k_proche = 3'd0;
        for (p = 7; p >= 0; p = p - 1) begin
            if (egal[p]) begin
                trouve   = 1'b1;
                k_trouve = p[2:0];
            end
            if (proche[p]) begin
                trouve_p = 1'b1;
                k_proche = p[2:0];
            end
        end
    end

    always @(posedge clk_w or negedge rst_n)
        if (!rst_n) begin
            fenetre     <= 24'd0;
            fenetre_2   <= 24'd0;
            recherche_1 <= 1'b0;
            recherche_2 <= 1'b0;
            nmots       <= 2'd0;
            egal        <= 8'd0;
            proche      <= 8'd0;
            decalage    <= 3'd0;
            run         <= {RUN_W{1'b0}};
            porte       <= 1'b0;
            age         <= 4'd0;
            porte_2     <= 1'b0;
            tol_ok      <= 1'b0;
            tol_2       <= 1'b0;
            un_1        <= 1'b0;
            deux_1      <= 1'b0;
            deux_2      <= 1'b0;
            tard_1      <= 1'b0;
            tard_2      <= 1'b0;
            compte      <= 2'd0;
            ferme       <= 1'b0;
            verrou      <= 1'b0;
            actif       <= 1'b0;
            valide      <= 1'b0;
            octet       <= 8'd0;
            err_sync    <= 1'b0;
            err_sot     <= 1'b0;
        end else if (en) begin
            // étage 1
            fenetre     <= recherche ? {mot, fenetre[23:8]} : 24'd0;
            nmots       <= !recherche ? 2'd0 : nmots == 2'd3 ? 2'd3 : nmots + 2'd1;
            recherche_1 <= recherche;
            run         <= recherche ? run_sat : {RUN_W{1'b0}};
            porte       <= recherche && (porte || ouvre || (PORTE != 0 && run_suiv >= PORTE));
            tol_ok      <= recherche && (tol_ouvre || run_suiv >= TOL_ZEROS);
            age         <= !recherche ? 4'd0 : age == 4'd15 ? 4'd15 : age + 4'd1;
            un_1        <= recherche && (un_1 || a_un);
            deux_1      <= recherche && (deux_1 || (un_1 && a_un) || a_deux);
            tard_1      <= recherche && (tard_1 || tard_c);
            // étage 2
            egal        <= egal_c;
            proche      <= proche_c;
            fenetre_2   <= fenetre;
            recherche_2 <= recherche_1;
            deux_2      <= deux_1;
            porte_2     <= porte;
            tol_2       <= tol_ok;
            tard_2      <= tard_1;
            // étage 3
            valide      <= 1'b0;
            err_sync    <= 1'b0;
            err_sot     <= 1'b0;
            if (!recherche_2) begin
                err_sync <= actif && !verrou;
                actif    <= 1'b0;
                verrou   <= 1'b0;
                compte   <= 2'd0;
                ferme    <= 1'b0;
            end else begin
                actif <= 1'b1;
                if (!verrou) begin
                    if (!ferme) begin
                        if ((trouve || (trouve_p && (TOL_ZEROS == 0 || tol_2))) && (VERROU_PORTE == 0 || porte_2)) begin
                            verrou   <= 1'b1;
                            decalage <= trouve ? k_trouve : k_proche;
                            err_sot  <= !trouve;
                        end else if (compte == 2'd2 || tard_2)
                            ferme    <= 1'b1;
                        if (deux_2 || compte != 2'd0)
                            compte   <= compte + 2'd1;
                    end
                end else begin
                    valide <= 1'b1;
                    octet  <= fenetre_2[decalage + 8 +: 8];
                end
            end
        end
endmodule

`default_nettype wire
