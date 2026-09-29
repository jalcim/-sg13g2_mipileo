// Variante de lm_fifo_async (27/09/2026) : mêmes ports, même comportement au cycle près sur tous les ports, rdata compris
// (FIFO vide ou non), sans latence ajoutée. Elle raccourcit le pire chemin de lm_top_l22t (SIt) à 125 et 156 MHz après
// routage LibreLane, variante « delai » (campagne mesures/2026-09-27_1626_librelane_ba916a4) :
// `fifo.rbin[2]` -> arbre de tampons (1,5 ns) -> multiplexeur de lecture 8 vers 1 sur 36 bits -> recherche_c de SIt ->
// arbre de tampons vers les 24 bits de la fenêtre d'une lane de l'aligneur. Au coin lent : +1,237 ns à 125 MHz,
// −0,363 ns à 156 MHz.
//
// Différences avec lm_fifo_async, et elles seules (côté lecture ; l'écriture est recopiée telle quelle) :
// - le mot lu est choisi par un pointeur à un seul bit à 1, sel (2^A bascules : sel[k] <=> rbin[A-1:0] == k), tenu à
//   jour au même front que rbin (rotation d'un cran par mot lu, décodage du pointeur d'écriture resynchronisé sur raz).
//   rdata = OU sur k de (sel[k] ET mem[k]) : chaque bascule de sel commande W portes au lieu des 4 W (bit 0), 2 W et W
//   multiplexeurs de rbin[A-1:0], et la sélection tient en deux niveaux de portes. rdata reste combinatoire depuis mem :
//   le mot est lu, puis pris par l'aligneur, au même front que dans lm_fifo_async ; la marge des passages d'horloge des
//   données (mémoire stable une période au moins avant d'être prise) ne change pas ;
// - empty est une bascule, vide, qui prend au front la valeur que prendra (rgray == wgray_r2) : (rgray_suiv ==
//   wgray_r1). Même valeur au même cycle. Sans elle, la comparaison combinatoire commande pas, puis l'arbre de `en` de
//   l'aligneur (environ 570 bascules) : en synthèse locale, ce chemin devient le pire de l'aligneur et le pointeur à un
//   bit seul ne gagne rien (rtl/README.md). Prix : la comparaison est placée derrière wgray_r1, première bascule de
//   resynchronisation ; le temps de résolution d'une métastabilité de wgray_r1 perd la traversée du comparateur (quelques
//   centaines de ps). wgray_r2 est gardé : il sert au raz et aux invariants ; dans SIt (raz à 0), la synthèse le retire
//   et vide est la seconde bascule de resynchronisation de wgray.
//   Patch SYNC3 (SYNC = 3, revue 28/N2) : la comparaison passe sur le dernier étage, (rgray_suiv == wgray_r2), qui
//   vaut (rgray == wgray_r3) après le front, comme empty de lm_fifo_async à SYNC = 3. wgray_r1 -> wgray_r2 n'a plus de
//   logique : le premier étage a une période entière pour résoudre ; le comparateur est sur wgray_r2 -> vide, second
//   temps de résolution. vide est la troisième bascule de resynchronisation de wgray (wgray_r3, gardé pour le raz et
//   les invariants, est retiré par la synthèse dans SIt). SYNC = 2 : RTL inchangé (comparaison sur wgray_r1).
// Coût : 2^A + 1 bascules de plus (9 pour A = 3). rbin et rgray sont gardés : rgray part vers l'écriture comme avant
// (un seul bit change par front, raz compris, comme dans lm_fifo_async depuis le plan de correction, T3) ; rbin donne
// rbin + 1.
// Équivalence prouvée : tests/fifo_p/ (preuves Yosys par induction, deux horloges libres, de la FIFO seule, de SIt et
// de SI ; bancs croisés contre lm_fifo_async, seule et dans SIt).
//
// Nom du module : lm_fifo_async_p ; avec la macro LM_FIFO_ASYNC_P_REMPLACE, ce fichier définit lm_fifo_async à la place
// de lm_fifo_async.v, pour synthétiser ou simuler un top inchangé (lm_top_l22t, lm_top_l22) avec cette variante : liste
// de sources sans lm_fifo_async.v, avec ce fichier, et la macro (VERILOG_DEFINES de LibreLane, -D d'iverilog).
//
// Reste de l'en-tête de lm_fifo_async, inchangé :
// FIFO asynchrone à deux horloges (pointeurs en code Gray, deux bascules de resynchronisation par sens), lue en « first
// word fall through » comme la FIFO RX que suppose lm_lmf_rx. Sert à lm_top_l22 : FIFO de recalage entre l'aligneur L22
// (horloge de mot W) et la LMF (Clk Système). Placement et forme de cette FIFO restent ouverts (DEC-PB-2) : c'est
// l'option la plus simple, une FIFO commune dans le Lane Management, écrite pour comparer avec et sans L22.
// - Écriture sur clk_w : wr écrit wdata ; full est prudent (vu avec les pointeurs de lecture resynchronisés).
//   Écriture sur FIFO pleine : le mot est perdu et deborde lève une période.
// - Lecture sur clk_r : rdata valable tant que empty est bas, rd dépile.
// - raz (côté lecture) : le lecteur jette tout ce qui est écrit à ce moment (le pointeur d'écriture resynchronisé est
//   pris comme cible) ; aucun signal ne traverse vers l'écriture. Le pointeur de lecture rejoint la cible par pas de 1,
//   un par cycle de clk_r, empty tenu haut : son code Gray, qui traverse vers l'écriture, ne change que d'un bit par
//   front (plan de correction, T3). Les mots écrits après la raz attendent la fin du vidage.
`default_nettype none

`ifdef LM_FIFO_ASYNC_P_REMPLACE
module lm_fifo_async #(
`else
module lm_fifo_async_p #(
`endif
    parameter W = 32,
    parameter A = 3,                    // profondeur 2^A
    parameter SYNC = 2                  // bascules de resynchronisation des pointeurs Gray : 2 ou 3 (patch SYNC3)
) (
    input  wire         rst_w_n,        // reset du domaine d'écriture (relâché de façon synchrone sur clk_w)
    input  wire         clk_w,
    input  wire         wr,
    input  wire [W-1:0] wdata,
    output wire         full,
    output reg          deborde,
    output wire         presque,        // une seule place libre, vue prudente du côté écriture (plan de correction, T14)
    input  wire         rst_r_n,        // reset du domaine de lecture (relâché de façon synchrone sur clk_r)
    input  wire         clk_r,
    input  wire         rd,
    output wire [W-1:0] rdata,
    output wire         empty,
    input  wire         raz
);
    localparam N = 1 << A;

    reg [W-1:0] mem [0:N-1];
    reg [A:0]   wbin, wgray, rbin, rgray;
    reg [A:0]   rgray_w1, rgray_w2, wgray_r1, wgray_r2;
    reg [A:0]   rgray_w3, wgray_r3;     // SYNC = 3 seulement (retirés par la synthèse si SYNC = 2)
    wire [A:0]  rgray_ws = (SYNC >= 3) ? rgray_w3 : rgray_w2;  // pointeur de lecture vu par l'écriture
    wire [A:0]  wgray_rs = (SYNC >= 3) ? wgray_r3 : wgray_r2;  // pointeur d'écriture vu par la lecture
    wire [A:0]  wgray_rp = (SYNC >= 3) ? wgray_r2 : wgray_r1;  // l'étage d'avant (vide des variantes _p et _r)
    reg [N-1:0] sel;                    // sel[k] <=> rbin[A-1:0] == k
    reg         vide;                   // == (rgray == wgray_rs) : wgray_r2 (SYNC = 2) ou wgray_r3 (SYNC = 3)

    // écriture (recopie de lm_fifo_async)
    wire [A:0] wbin_suiv = wbin + 1'b1;
    // pleine : les deux bits de poids fort du pointeur Gray diffèrent, les autres sont égaux (vaut aussi pour A = 1)
    localparam [A:0] HAUTS = 3 << (A - 1);
    assign full = (wgray ^ rgray_ws) == HAUTS;
    function [A:0] gray2bin(input [A:0] g);
        integer i;
        begin
            gray2bin[A] = g[A];
            for (i = A - 1; i >= 0; i = i - 1) gray2bin[i] = gray2bin[i+1] ^ g[i];
        end
    endfunction
    localparam [A:0] PRESQUE = (1 << A) - 1;
    assign presque = wbin - gray2bin(rgray_ws) == PRESQUE;
    always @(posedge clk_w or negedge rst_w_n)
        if (!rst_w_n) begin
            wbin <= 0; wgray <= 0; rgray_w1 <= 0; rgray_w2 <= 0; rgray_w3 <= 0; deborde <= 1'b0;
        end else begin
            rgray_w1 <= rgray;
            rgray_w2 <= rgray_w1;
            rgray_w3 <= rgray_w2;
            deborde  <= wr && full;
            if (wr && !full) begin
                mem[wbin[A-1:0]] <= wdata;
                wbin  <= wbin_suiv;
                wgray <= wbin_suiv ^ (wbin_suiv >> 1);
            end
        end

    // lecture : mot choisi par sel, ET-OU sur les 2^A mots
    reg [W-1:0] lu;
    integer     k;
    always @(*) begin
        lu = {W{1'b0}};
        for (k = 0; k < N; k = k + 1) lu = lu | (mem[k] & {W{sel[k]}});
    end
    assign rdata = lu;
    reg         purge;                  // raz en cours : rbin avance vers cible, un pas par cycle
    reg [A:0]   cible;                  // pointeur d'écriture resynchronisé, en Gray, vu à la raz
    wire        fin_purge = rgray == cible;
    assign empty = purge || vide;

    wire       avance     = purge ? !fin_purge : rd && !vide;
    wire [A:0] rbin_suiv  = rbin + {{A{1'b0}}, avance};
    wire [A:0] rgray_suiv = rbin_suiv ^ (rbin_suiv >> 1);
    wire [N-1:0] un       = {{(N-1){1'b0}}, 1'b1};
    wire [N-1:0] sel_suiv = avance ? {sel[N-2:0], sel[N-1]} : sel;
    always @(posedge clk_r or negedge rst_r_n)
        if (!rst_r_n) begin
            rbin <= 0; rgray <= 0; wgray_r1 <= 0; wgray_r2 <= 0; wgray_r3 <= 0; sel <= un; vide <= 1'b1; purge <= 1'b0; cible <= 0;
        end else begin
            wgray_r1 <= wgray;
            wgray_r2 <= wgray_r1;
            wgray_r3 <= wgray_r2;
            rbin     <= rbin_suiv;
            rgray    <= rgray_suiv;
            sel      <= sel_suiv;
            vide     <= rgray_suiv == wgray_rp;    // = (rgray == wgray_rs) après le front
            if (raz) begin
                purge <= 1'b1;
                cible <= wgray_rs;
            end else if (purge && fin_purge)
                purge <= 1'b0;
        end

`ifdef FORMAL
    // Invariants de la variante, vérifiés par la preuve de tests/fifo_p/ (read_verilog -formal) : sel décode rbin, vide
    // vaut la comparaison de lm_fifo_async. Avec eux, rdata = mem[rbin[A-1:0]] et empty = (rgray == wgray_r2), les
    // sorties de lm_fifo_async.
    always @(*) begin
        assert (sel == un << rbin[A-1:0]);
        assert (vide == (rgray == wgray_rs));
    end
`endif
endmodule

`default_nettype wire
