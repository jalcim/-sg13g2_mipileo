// Variante de lm_fifo_sync (28/09/2026) : mêmes ports, même comportement au cycle près sur tous les ports, sans latence
// ajoutée. Elle coupe le chemin de lm_top_l22t (SIt) qui devient le pire une fois la FIFO asynchrone corrigée
// (lm_fifo_async_p.v) : `tampon.n` (compteur) -> comparaison `place = (n <= 2^A - 2)` -> `s_place` -> `pas = s_place &&
// (!b_empty || vide_ok)` -> `aligneur.en`, qui commande environ 570 bascules de lm_aligneur_l22, et `b_rd`, qui avance la
// FIFO asynchrone. Mesures :
// - R5 (campagne mesures/2026-09-27_2023_librelane_630d92e8), broches ordonnées : tampon.n[2] -> registre, +1,349 et
//   +1,285 ns à 8 ns au coin lent (ancien SDC) ;
// - synthèse locale avec lm_fifo_async_p : environ 2,08 ns, le pire de l'aligneur (analyse/reponses/NOTES_ARRET_fifo.md).
//
// Différence avec lm_fifo_sync, et elle seule : place est une bascule, place_r, qui prend au front la valeur que prendra
// (n <= 2^A - 2) : (n_suiv <= 2^A - 2), où n_suiv est la valeur que n prend au même front. Même valeur au même cycle,
// comme `vide` dans lm_fifo_async_p.v. La comparaison passe derrière le front : place ne traverse plus que la bascule.
// Le reste (mémoire, pointeurs, n, empty, rdata, raz) est recopié de lm_fifo_sync.v ; n prend n_suiv, qui réécrit sans
// la changer l'affectation d'origine.
// Coût : une bascule. Le chemin qui charge place_r est celui qui charge n, plus la comparaison (rd de la LMF -> lit ->
// n_suiv) ; de l'aligneur, il ne prend que fifo_wr, qui ne dépend que de ses registres (ecrit, vide, en_r).
// Dans SIt, la LMF lit le tampon dès qu'il n'est pas vide : il ne contient jamais plus d'un mot et place vaut toujours 1
// (prouvé, tests/fifo_sync_p/). La variante n'en dépend pas : elle reste juste si une contre-pression revient.
// Équivalence prouvée : tests/fifo_sync_p/ (preuves Yosys par induction de la FIFO seule et de SIt, avec et sans
// lm_fifo_async_p ; mutants).
//
// Nom du module : lm_fifo_sync_p ; avec la macro LM_FIFO_SYNC_P_REMPLACE, ce fichier définit lm_fifo_sync à la place de
// lm_fifo_sync.v, pour synthétiser ou simuler un top inchangé (lm_top_l22t) avec cette variante : liste de sources sans
// lm_fifo_sync.v, avec ce fichier, et la macro (VERILOG_DEFINES de LibreLane, -D d'iverilog).
//
// Reste de l'en-tête de lm_fifo_sync, inchangé :
// Petite FIFO synchrone (une horloge), lue en « first word fall through » comme la FIFO RX que suppose lm_lmf_rx.
// Sert à lm_top_l22t : tampon entre l'aligneur L22, sur Clk Système, et la LMF. `place` dit qu'un mot de plus peut
// encore arriver après le cycle courant (contre-pression de l'aligneur, qui livre un mot au cycle qui suit un pas).
// raz vide la FIFO de ce qu'elle contient ; un mot écrit au même cycle est gardé (même règle que lm_fifo_async :
// seuls les mots déjà visibles du lecteur sont jetés).
`default_nettype none

`ifdef LM_FIFO_SYNC_P_REMPLACE
module lm_fifo_sync #(
`else
module lm_fifo_sync_p #(
`endif
    parameter W = 32,
    parameter A = 2                     // profondeur 2^A
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         wr,
    input  wire [W-1:0] wdata,
    output wire         place,          // au moins deux places libres
    input  wire         rd,
    output wire [W-1:0] rdata,
    output wire         empty,
    input  wire         raz
);
    reg [W-1:0] mem [0:(1<<A)-1];
    reg [A-1:0] pw, pr;
    reg [A:0]   n;
    reg         place_r;                // == (n <= 2^A - 2)

    assign empty = n == 0;
    assign rdata = mem[pr];
    assign place = place_r;

    wire lit    = rd && !empty;
    wire ecrit  = wr && (n != (1 << A) || lit || raz);
    // valeur de n après le front (raz : le mot écrit à ce cycle devient le seul)
    wire [A:0] n_suiv = raz ? {{A{1'b0}}, ecrit} : n + {{A{1'b0}}, ecrit} - {{A{1'b0}}, lit};

    always @(posedge clk) if (ecrit) mem[pw] <= wdata;

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            pw      <= 0;
            pr      <= 0;
            n       <= 0;
            place_r <= 1'b1;                // n = 0 : 0 <= 2^A - 2 pour A >= 1
        end else begin
            n       <= n_suiv;
            place_r <= n_suiv <= (1 << A) - 2;  // = (n <= 2^A - 2) après le front
            if (raz) begin
                if (ecrit) pw <= pw + 1'b1;
                pr <= pw;
            end else begin
                if (ecrit) pw <= pw + 1'b1;
                if (lit)   pr <= pr + 1'b1;
            end
        end

`ifdef FORMAL
    // Invariant de la variante, vérifié par la preuve de tests/fifo_sync_p/ (read_verilog -formal) : place_r vaut la
    // comparaison de lm_fifo_sync. Avec lui, place = (n <= 2^A - 2), la sortie de lm_fifo_sync.
    always @(*) assert (place_r == (n <= (1 << A) - 2));
`endif
endmodule

`default_nettype wire
