// Aligneur L22 des 4 lanes, domaine de l'horloge de mot W : un lm_aligneur par lane, deskew de mots, puis mot de 32 bits
// vers la FIFO RX (lane p dans les bits [8p+7:8p], choix_equipe.md §4), comme la lit lm_lmf_rx.
// Référence : analyse/questions/notes/alternative_horloge_mot_libre.md §3 et §7 point 4.
//
// Deskew : toutes les lanes sont capturées sur les mêmes fronts de W, mais l'émetteur peut décaler le SoT d'une lane
// d'un mot ou plus. Une fois verrouillée, une lane livre un octet à chaque période, sans trou : il suffit de la retarder
// d'un nombre fixe de périodes. Chaque lane passe dans une ligne à retard de RETARD_MAX octets ; son retard est le
// nombre de périodes entre son premier octet et le premier octet de la dernière lane du masque à se verrouiller.
// Un mot est écrit quand chaque lane du masque a un octet à sa sortie retardée. Quand plus aucune lane du masque n'est
// en burst, les retards sont remis à zéro (les octets restants, fins de trail incomplètes, ne font pas de mot).
// Un retard au-delà de RETARD_MAX lève erreur_deskew (décalage entre lanes plus grand que la ligne à retard).
// Le masque (configuration statique, domaine de Clk Système) est échantillonné deux fois dans le domaine de W.
// `en` (27/09/2026) : validation d'entrée, un pas par mot ; à 0, tout est gelé. À 1 en permanence sur W (lm_top_l22) ;
// sur Clk Système derrière la FIFO (lm_top_l22t), un pas par mot lu. fifo_wr, err_sync et erreur_deskew ne valent
// qu'au cycle qui suit un pas.
// D2, conduite B (choix 7 et 13 de connaissances/decisions.md ; plan de correction, T7), reprise du patch mesuré et
// contre-vérifié (mesures/2026-09-27_1744_iverilog_4e451ed3_d2_croise/bruts/rtl/politique_d2.patch, POLITIQUE = 2) :
// - attente bornée : RETARD_MAX pas après le premier octet du burst, les lanes du masque encore muettes (sans 0xB8, en
//   LP, ou trop en retard) sont déclarées absentes et ignorées jusqu'à la fin du burst, même si elles se verrouillent
//   ensuite (choix 13), sans erreur_deskew ; les mots sont écrits avec les lanes présentes ;
// - burst_errone accompagne chaque mot écrit d'un burst à lane absente ; `absente` est tenu jusqu'au début du burst
//   suivant, pour que les derniers mots (vidange après fin_burst) le portent aussi ;
// - fin_errone : impulsion après le dernier mot d'un burst perdu ou incomplet (lane absente, lane sans 0xB8 selon
//   err_sync, ou burst fini avant que toutes les lanes du masque aient démarré), même quand aucun mot n'a été écrit :
//   c'est elle que porte le battement vide sot+err vers le LLP.
// POLITIQUE = 0 : comportement d'avant T7 (lane muette bloquante, erreur_deskew), gardé pour comparer.
// D1, option a (choix 5 ; plan de correction, T11), étiquettes de chaque écriture, valables avec fifo_wr :
// - fifo_wsot : premier mot écrit du burst (armé au début du burst, et non à sa fin : les mots de vidange écrits après
//   fin_burst appartiennent encore au burst qui finit) ;
// - fifo_werr : erreur bloquante du burst (burst_errone), sur tous ses mots ;
// - fifo_wsot_err : une lane présente du burst a été verrouillée à un bit près (err_sot, option D de D3) ;
// - fifo_wvide : battement vide, écrit au pas de fin_errone quand le burst perdu n'a écrit aucun mot ; il porte
//   fifo_wsot = 1 et fifo_werr = 1, sans octet. Dans SIt, l'aligneur tourne sur Clk Système et vide son pipeline sans
//   W : ce battement ne dépend d'aucun front de W.
`default_nettype none

module lm_aligneur_l22 #(
    parameter RETARD_MAX = 3,
    parameter POLITIQUE  = 2            // D2 : 2 = conduite B ; 0 = avant T7
) (
    input  wire        clk_w,
    input  wire        rst_n,
    input  wire        en,
    input  wire [3:0]  masque,
    input  wire [3:0]  recherche,       // un par lane, de la SM du PHY
    input  wire [31:0] mots,            // mot brut de la lane l dans [8l+7:8l]
    input  wire        perte,           // D11 (T14) : des mots bruts ont été perdus autour de ce mot (FIFO de tête pleine)
    output wire        fifo_wr,
    output reg  [31:0] fifo_wdata,
    output wire [3:0]  verrou,          // synched par lane
    output wire [3:0]  err_sync,
    output wire [3:0]  err_sot,         // par lane, une période : verrou pris à un bit près (ErrSotHS, option D de D3)
    output wire        erreur_deskew,
    output wire        burst_errone,    // D2 : lane du masque déclarée absente dans ce burst, vaut pour le mot écrit
    output wire        fin_errone,      // D2 : fin d'un burst perdu ou incomplet, après son dernier mot
    output wire        fifo_wsot,       // D1 (a) : premier mot du burst, ou battement vide
    output wire        fifo_werr,       // erreur bloquante du burst, sur tous ses mots et sur le battement vide
    output wire        fifo_wsot_err,   // une lane présente verrouillée à un bit près (ErrSotHS)
    output wire        fifo_wvide,      // battement vide : burst perdu sans aucun mot écrit
    output wire        inactif          // T12 (RX4) : aucun burst, rien dans les lignes à retard ni à écrire
);
    reg         ecrit, deskew, en_r;            // ecrit, deskew : résultat du dernier pas
    reg         errone;
    reg  [3:0]  absente;                        // D2 : lanes du masque déclarées absentes pour ce burst
    reg         dans_burst;                     // D2 : un burst était en cours au pas précédent
    reg  [3:0]  err_vu;                         // D2 : lanes du masque sorties sans 0xB8 pendant ce burst
    reg  [2:0]  fin_d;                          // D2 : fin d'un burst erroné, retardée après la vidange
    assign burst_errone = errone && en_r;
    assign fin_errone   = fin_d[2] && en_r;
    reg         premier;                        // D1 (a) : le prochain mot écrit est le premier du burst
    reg         sot_r, sot_err_r, vide;         // étiquettes de l'écriture du dernier pas
    reg         sot_err_burst;                  // une lane présente du burst verrouillée à un bit près
    reg         ecrit_burst;                    // un mot a été écrit dans ce burst
    reg         perte_burst;                    // D11 (T14) : perte marquée dans ce burst (ou dans sa vidange)
    reg         err_apres_perte;                // un mot marqué err a été écrit depuis la première perte du burst
    reg         err_ecrit;                      // NU2 : un mot marqué err a été écrit dans ce burst
    assign fifo_wsot     = vide || sot_r;
    assign fifo_werr     = vide || errone;
    assign fifo_wsot_err = !vide && sot_err_r;
    assign fifo_wvide    = vide;
    wire [3:0]  err_sync_pas, err_sot_pas;
    assign fifo_wr       = (ecrit || vide) && en_r;
    assign erreur_deskew = deskew && en_r;
    assign err_sync      = err_sync_pas & {4{en_r}};
    assign err_sot       = err_sot_pas & {4{en_r}};
    wire [3:0]  valide, actif;
    wire [31:0] octet;
    reg  [3:0]  masque_1, masque_w;
    reg  [8:0]  ligne [0:3][0:RETARD_MAX];      // {valide, octet}, ligne[l][0] : sortie de l'aligneur, registrée
    localparam RW = RETARD_MAX > 0 ? $clog2(RETARD_MAX + 1) : 1;   // largeur du retard (plan de correction, T5)
    localparam [RW-1:0] RMAX = RETARD_MAX;
    reg  [RW-1:0] retard [0:3];
    reg  [3:0]  vu;                             // lane déjà sortie de son premier octet dans ce burst
    reg  [3:0]  actif_d;                        // D9 : actif au pas précédent, pour le front montant par lane
    integer     l, i;

    genvar g;
    generate
        for (g = 0; g < 4; g = g + 1) begin : lane
            lm_aligneur aligneur (
                .clk_w(clk_w), .rst_n(rst_n), .en(en), .recherche(recherche[g]), .mot(mots[8*g +: 8]),
                .valide(valide[g]), .octet(octet[8*g +: 8]), .verrou(verrou[g]), .actif(actif[g]),
                .err_sync(err_sync_pas[g]), .err_sot(err_sot_pas[g])
            );
        end
    endgenerate

    // toutes les lanes présentes du masque ont livré leur premier octet : les retards sont figés
    wire [3:0] presentes     = masque_w & ~(dans_burst ? absente : 4'd0);   // absente d'un burst précédent ignoré
    wire [3:0] presentes_mot = masque_w & ~absente;                         // tenu pendant la vidange
    wire tous      = ((vu | valide) & presentes) == presentes && masque_w != 4'd0;
    // D2 : une lane vue a atteint RETARD_MAX sans que les autres soient là
    wire [3:0] au_max;
    generate
        for (g = 0; g < 4; g = g + 1) begin : max
            assign au_max[g] = masque_w[g] && (vu[g] || valide[g]) && retard[g] == RMAX;
        end
    endgenerate
    wire fin_burst = ((actif | valide) & masque_w) == 4'd0;
    wire debut     = !fin_burst && !dans_burst;
    // D11 (T14) : une perte lue pendant un burst ou sa vidange compte pour ce burst ; lue au repos, elle ne concerne que
    // des mots de repos et elle est ignorée (pas de marque sur l'en-tête du burst suivant)
    wire perte_ici = perte && (dans_burst || !fin_burst || fin_d != 3'd0);
    wire err_mot   = |(absente & masque_w) || perte_burst || perte_ici;
    wire fin_err   = fin_burst && dans_burst && (|(absente & masque_w) || (!tous && |(vu & masque_w))
                     || |err_vu || |(err_sync_pas & masque_w) || perte_burst || perte_ici);

    // sortie retardée de chaque lane, registrée (27/09/2026 : retard -> mot écrit, pire chemin après routage LibreLane
    // à 300 et 312 MHz), puis mot complet
    wire [8:0] sortie [0:3];
    reg  [8:0] sortie_r [0:3];
    wire [3:0] present;                         // la sortie retardée registrée de la lane porte un octet
    generate
        for (g = 0; g < 4; g = g + 1) begin : sortie_lane
            assign sortie[g]  = ligne[g][retard[g]];
            assign present[g] = sortie_r[g][8];
        end
    endgenerate
    wire complet = masque_w != 4'd0 && (presentes_mot & ~present) == 4'd0;

    // T12 (RX4, D7) : le masque peut changer sans toucher un mot en route
    wire [3:0] occupe;                          // un octet valide dans la ligne à retard ou la sortie registrée de la lane
    generate
        for (g = 0; g < 4; g = g + 1) begin : occupe_lane
            wire [RETARD_MAX:0] valides;
            genvar cpt;
            for (cpt = 0; cpt <= RETARD_MAX; cpt = cpt + 1) begin : etage
                assign valides[cpt] = ligne[g][cpt][8];
            end
            assign occupe[g] = sortie_r[g][8] || |valides;
        end
    endgenerate
    assign inactif = fin_burst && !dans_burst && fin_d == 3'd0 && !ecrit && !vide && occupe == 4'd0;

    always @(posedge clk_w or negedge rst_n)
        if (!rst_n) begin
            masque_1      <= 4'd0;
            masque_w      <= 4'd0;
            vu            <= 4'd0;
            actif_d       <= 4'd0;
            ecrit         <= 1'b0;
            fifo_wdata    <= 32'd0;
            deskew        <= 1'b0;
            en_r          <= 1'b0;
            errone        <= 1'b0;
            absente       <= 4'd0;
            dans_burst    <= 1'b0;
            err_vu        <= 4'd0;
            fin_d         <= 3'd0;
            premier       <= 1'b1;
            sot_r         <= 1'b0;
            sot_err_r     <= 1'b0;
            vide          <= 1'b0;
            sot_err_burst <= 1'b0;
            ecrit_burst   <= 1'b0;
            perte_burst   <= 1'b0;
            err_apres_perte <= 1'b0;
            err_ecrit     <= 1'b0;
            for (l = 0; l < 4; l = l + 1) begin
                retard[l]   <= {RW{1'b0}};
                sortie_r[l] <= 9'd0;
                for (i = 0; i <= RETARD_MAX; i = i + 1) ligne[l][i] <= 9'd0;
            end
        end else begin
          en_r <= en;
          if (en) begin
            masque_1      <= masque;
            masque_w      <= masque_1;
            ecrit         <= complet;
            deskew        <= 1'b0;
            errone        <= err_mot;
            dans_burst    <= !fin_burst;
            err_vu        <= debut ? 4'd0 : err_vu | (err_sync_pas & masque_w);
            fin_d         <= {fin_d[1:0], fin_err && POLITIQUE != 0};
            // D1 (a) : étiquettes de l'écriture de ce pas
            sot_r         <= premier;
            sot_err_r     <= sot_err_burst || |(err_sot_pas & presentes_mot);
            // battement vide : aucun mot écrit dans le burst, ou perte sans aucun mot marqué écrit depuis. Un mot
            // marqué suffit : perte_burst marque tous les mots écrits ensuite, dont le dernier du burst, et le LLP
            // rejette le burst. Une perte relue pendant la vidange (le premier mot écrit après un refus, dont le
            // mot de la dernière place libre est déjà écrit et marqué) ne rouvre pas de battement vide : sinon le LLP
            // verrait deux bursts en erreur pour un seul (relecture de T14, point 6).
            // NU2 (28/09/2026, analyse/reponses/signaux_non_utilises.md) : fin_errone (libre dans lm_top_l22t) signale
            // aussi un burst qui a écrit des mots, tous sans err, puis s'est perdu (relance d'une lane en cours de
            // burst, D9, qui finit en err_sync ou en lane absente sans qu'aucun mot ne suive) : sans battement vide,
            // le LLP ne recevait aucune marque de cette erreur.
            vide          <= fin_d[1] && (!ecrit_burst || !err_ecrit || (perte_burst && !err_apres_perte));
            if (debut) begin
                premier       <= 1'b1;
                ecrit_burst   <= 1'b0;
                // NU1 (28/09/2026, analyse/reponses/signaux_non_utilises.md) : une lane peut se verrouiller au pas même
                // où son `actif` monte (verrou au premier mot, armement tardif ou bruit) ; ce pas est le pas `debut`,
                // et son err_sot était effacé ici, alors que la sortie err_sot (libre dans lm_top_l22t) le portait.
                // `absente` date encore du burst précédent : on prend le masque.
                sot_err_burst <= |(err_sot_pas & masque_w);
                perte_burst   <= 1'b0;
                err_apres_perte <= 1'b0;
                err_ecrit     <= 1'b0;
            end else begin
                if (complet) begin
                    premier     <= 1'b0;
                    ecrit_burst <= 1'b1;
                end
                sot_err_burst <= sot_err_burst || |(err_sot_pas & presentes_mot);
                if (perte_ici) perte_burst <= 1'b1;
                if (complet && err_mot && (perte_burst || perte_ici))
                    err_apres_perte <= 1'b1;
                if (complet && err_mot)
                    err_ecrit   <= 1'b1;
            end
            for (l = 0; l < 4; l = l + 1) begin
                ligne[l][0] <= {valide[l], octet[8*l +: 8]};
                for (i = 1; i <= RETARD_MAX; i = i + 1) ligne[l][i] <= ligne[l][i-1];
                sortie_r[l]          <= sortie[l];
                fifo_wdata[8*l +: 8] <= masque_w[l] ? sortie_r[l][7:0] : 8'd0;
            end
            if (fin_burst) begin
                vu <= 4'd0;
                for (l = 0; l < 4; l = l + 1) retard[l] <= {RW{1'b0}};
            end else begin
                vu <= vu | valide;
                if (debut) absente <= 4'd0;
                // D2 : une lane partie attend les autres au plus RETARD_MAX pas ; les muettes sont alors absentes
                if (!tous && POLITIQUE != 0 && au_max != 4'd0)
                    absente <= absente | (masque_w & ~(vu | valide));
                // une lane déjà partie attend les autres une période de plus
                else if (!tous)
                    for (l = 0; l < 4; l = l + 1)
                        if (masque_w[l] && (vu[l] || valide[l])) begin
                            if (retard[l] == RMAX) deskew <= 1'b1;
                            else retard[l] <= retard[l] + 1'b1;
                        end
            end
            // D9 (plan de correction, T8) : au front montant de actif[l], nouveau burst de la lane l : son vu et son
            // retard repartent de zéro, même si une autre lane, collée en HS, empêche fin_burst. Le front descendant ne
            // convient pas : la lane la plus en avance perdrait la fin de sa ligne à retard (mesure de la relecture du
            // plan, al_t8.v). Une lane collée pour toujours relève du chien de garde (règle 5), pas de l'aligneur.
            actif_d <= actif;
            for (l = 0; l < 4; l = l + 1)
                if (actif[l] && !actif_d[l]) begin
                    vu[l]     <= 1'b0;
                    retard[l] <= {RW{1'b0}};
                end
          end
        end
endmodule

`default_nettype wire
