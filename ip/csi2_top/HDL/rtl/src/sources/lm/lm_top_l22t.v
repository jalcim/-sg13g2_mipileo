// Lane Management avec L22, FIFO en tête (SIt, évaluation du 27/09/2026) : mêmes ports que lm_top_l22, qu'il sert à
// mesurer contre lui. Seul l'ordre change côté RX :
// - lm_top_l22  : mots bruts (W) -> aligneur (W) -> FIFO asynchrone (W -> Clk Système) -> LMF ;
// - lm_top_l22t : mots bruts et recherche (W) -> FIFO asynchrone de 36 bits (W -> Clk Système) -> aligneur (Clk Système,
//   un pas par mot lu) -> FIFO synchrone de 4 mots -> LMF.
// Le domaine W ne garde que l'écriture de la FIFO : un mot par période de W tant qu'une lane est en burst.
// Mots de repos (28/09/2026, fiche analyse/reponses/derive_clk_sit.md) : un mot dont `recherche` est bas sur les 4 lanes
// n'est écrit que s'il est le premier de suite (REPOS_ECRITS = 1). Écrire tous les mots, même au repos, faisait monter
// l'occupation de la FIFO sans fin en horloge continue dès que Clk Système est un peu plus lente que W : un mot perdu
// toutes les 1 / (écart × W) secondes, 32 µs à −250 ppm pour W = 125 MHz, en burst comme au repos. Un mot sauté ne
// manque pas à l'aligneur : avec `recherche` bas, lm_aligneur vide sa fenêtre et ignore le mot, c'est le pas de repos
// (recherche bas, mot nul) qu'il fait déjà quand la FIFO est vide. Le premier mot de repos est écrit : lu, il met
// `repos` à 1, et l'aligneur vide ensuite son pipeline par des pas de repos, sans W (vidage inchangé).
// Le test porte sur les lanes d'Enable (correction de 27/N2, choix 33) : Enable est resynchronisé sur W par deux
// bascules ; une lane hors d'Enable dont la SM ne serait pas éteinte (HSPR tenu haut) ne fait plus écrire les mots.
// Vidage sans W : quand le dernier mot lu a `recherche` bas sur toutes les lanes du masque (fin de burst écrite dans la
// FIFO) et que la FIFO est vide, l'aligneur fait des pas sur des mots de repos (recherche bas), comme si W tournait
// encore : les derniers octets sortent de son pipeline même si W s'est arrêtée juste après la chute de HS.
// Clk Système plus lente que W : comme pour lm_top_l22, la FIFO ne prend de retard que pendant un burst (mots écrits
// × écart relatif) et se vide entre deux bursts ; elle déborde si ce retard dépasse sa réserve (environ 3 mots sur 8).
// Remise à zéro de la FIFO RX (point 2, REMISE_RX) : sans objet ici, fifo_rx_raz de lm_top n'est pas branchée. L'aligneur
// sépare déjà les bursts (il n'écrit rien hors d'un burst verrouillé) et vide son pipeline seul ; la remise, tirée de la
// chute de HS du mot de statut, arriverait avant les derniers mots du burst encore en route et les jetterait (mesuré,
// tests/arret_w.py).
// D7, RX4 (choix 16 ; plan de correction, T12 ; livrable rtl/variantes/lm_top_l22t_rx.v, MASQUE_CONFIG = 1) : le masque
// des lanes du burst est Enable, resynchronisé par deux bascules, et tout le RX (aligneur, repos, LMF) ne le prend qu'au
// repos : aligneur inactif (aucun burst, lignes à retard vides, rien à écrire) et tampon vide. Le livrable comptait
// CALME pas sans `recherche` ; un burst du nouvel Enable arrivé avant ces pas était alors lu avec l'ancien masque, et
// perdu sans signal (tb_chaine_lm_l22t_arret_32_8). Tant que le dernier mot lu porte `recherche` haut (W arrêtée avant
// la fin du burst), l'aligneur reste en burst : la queue sort à la reprise de W avec son masque
// (analyse/questions_ouvertes/perte_silencieuse_clk_post.md). Les pas de repos (vidage sans W) s'arrêtent dès qu'une
// lane de l'ancien masque ou du nouvel Enable a `recherche` haut : ils ne s'intercalent jamais dans un burst. Un burst
// dont le premier mot est écrit avant la prise du nouvel Enable porte err sur tous ses mots. L'entrée `masque` n'est
// plus lue. La LDF (TX) suit Enable resynchronisé sans attendre le repos du RX (lm_top, ENABLE_RX_MASQUE = 1).
// Borne de « jamais silencieux » : un Enable changé pendant le trafic, au plus environ 5 mots de W après la montée de
// `recherche` brute, arrive alors que le RX, qui n'a pas encore lu cette montée, est au repos : il prend le nouvel
// Enable, et le burst en route est lu avec le nouveau masque, faux ou invisible, sans err (relecture de T12 : 26 bursts
// sur 1 200 changements au hasard). Hors norme : Enable est statique pendant le trafic (spec/interface_lm_llp.md §1.3).
// Passages d'horloge : données et recherche par la FIFO ; reset, un synchroniseur par domaine ; Enable vers W, deux
// bascules (Enable est statique, choix 33) ; débordement de la FIFO,
// collant sur W puis deux bascules. verrou, err_sync et erreur_deskew naissent dans le domaine de Clk Système.
`default_nettype none

module lm_top_l22t #(
    parameter REMISE_TAILLE = 0,    // point 6
    parameter LANE_ABSENTE  = 1,    // point 26
    parameter REMISE_RX     = 1,    // point 2
    parameter CODAGE        = 0,    // point 3 ; statut du choix 3 par défaut (montage figé, choix 28)
    parameter STATUT_W      = 3,
    parameter HS_BIT        = 2,
    parameter ETAT_LSB      = 0,
    parameter ETAT_W        = 3,
    parameter FIFO_A        = 3,    // FIFO asynchrone de 2^FIFO_A mots
    parameter RECHERCHE_SYNC = 1,   // 1 : recherche passe par deux bascules sur W (SM asynchrone de Lionel, L11)
    parameter REPOS_ECRITS  = 1,    // mots de repos écrits après une chute de recherche (1 à 15) ; 0 : tous écrits
    parameter SYNC          = 3     // SYNC3 (analyse/reponses/sync3.md) : bascules de chaque synchroniseur (recherche
                                    // vers W, pointeurs Gray, statut, Enable, débordement, resets) ; 2 : RTL d'avant
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire [3:0]            enable,
    input  wire [3:0]            masque,        // RX4 (T12) : non lue, gardée pour les bancs
    input  wire                  tx_in_valid,
    output wire                  tx_in_ready,
    input  wire [31:0]           tx_in_data,
    input  wire [2:0]            tx_in_nb,
    input  wire                  tx_in_last,
    input  wire [16:0]           tx_in_total,
    output wire                  fifo_tx_wr,
    output wire [31:0]           fifo_tx_wdata,
    output wire [3:0]            fifo_tx_wlanes,
    output wire                  fifo_tx_fin,
    input  wire                  fifo_tx_full,
    output wire [67:0]           tx_tailles,
    output wire                  tx_tailles_valides,
    output wire                  tx_erreur,
    input  wire                  clk_w,
    input  wire [31:0]           mots,          // domaine W
    input  wire [3:0]            recherche,     // domaine W (ou SM du PHY, RECHERCHE_SYNC)
    output wire [3:0]            verrou,        // domaine Clk Système
    output wire [3:0]            err_sync,      // domaine Clk Système, une période
    output wire                  erreur_deskew, // domaine Clk Système, une période
    output wire                  erreur_fifo,   // domaine Clk Système, collante jusqu'au reset
    output wire                  rx_out_valid,
    output wire [31:0]           rx_out_data,
    output wire [2:0]            rx_out_nb,
    output wire                  rx_out_sot,        // D1 (a) : premier battement du burst (spec/interface_lm_llp.md)
    output wire                  rx_out_err,        // erreur bloquante du burst ; battement vide : nb = 0, sot, err
    output wire                  rx_out_sot_err,    // ErrSotHS sur le battement sot
    output wire                  rx_erreur_config,
    output wire                  rx_erreur_burst,
    input  wire [4*STATUT_W-1:0] statut_phy,
    output wire [4*STATUT_W-1:0] statut,
    output wire [4*ETAT_W-1:0]   etat
);
    wire        rst_w_n, rst_s_n, deborde_w;
    wire [3:0]  recherche_w;
    wire        b_empty, b_rd, s_empty, s_place, s_rd, a_wr;
    wire [36:0] b_rdata;                               // {perte, recherche, mots}
    wire        presque_w;
    wire [31:0] a_wdata;
    wire [35:0] s_rdata;                               // {vide, sot_err, err, sot, mot}
    wire        a_wsot, a_werr, a_wsot_err, a_wvide;

    lm_sync_reset #(.SYNC(SYNC)) sync_rst_w (.clk(clk_w), .rst_n(rst_n), .rst_sync_n(rst_w_n));
    lm_sync_reset #(.SYNC(SYNC)) sync_rst_s (.clk(clk),   .rst_n(rst_n), .rst_sync_n(rst_s_n));

    generate
        if (RECHERCHE_SYNC) begin : recherche_resync
            lm_sync_niveau #(.W(4), .SYNC(SYNC)) sync (.clk(clk_w), .rst_n(rst_w_n), .d(recherche), .q(recherche_w));
        end else begin : recherche_directe
            assign recherche_w = recherche;
        end
    endgenerate

    // domaine W : un mot brut et sa recherche par période, tant qu'une lane est en burst, puis REPOS_ECRITS mots de repos.
    // recherche_w sort de bascules sur W (RECHERCHE_SYNC) : wr n'ajoute qu'une porte OU et le compteur devant la FIFO.
    // Un mot de repos ne compte que s'il est pris (FIFO non pleine) : si la FIFO déborde à la fin d'un burst, le mot de
    // repos refusé est retenté au front suivant. Sans cela, aucun mot à `recherche` bas n'atteindrait l'aligneur avant le
    // burst suivant : pas de vidage, et les deux bursts se suivraient sans repos dans l'aligneur.
    wire full_w;
    // Correction 27/N2 (28/09/2026, co-simulation de la revue avec le golden SR8, patch en_burst_enable.patch) : le test
    // de burst ne porte plus sur les 4 lanes, mais sur les lanes d'Enable. Une lane hors d'Enable dont la SM reste en
    // HS-Prpr (HSPR haut, SM active ou entrée LP flottante lue en LP-00), ou restée coincée en HS, faisait écrire tous les
    // mots de repos, et P54 revenait (horloge continue, Clk Système plus lente que W). Enable est statique (choix 4 :
    // quatre broches) : SYNC bascules sur W (lm_sync_niveau, comme Enable sur Clk Système ; revue 43/N10). À Enable constant,
    // en_burst est identique au cycle près à |recherche_w dès que les lanes hors d'Enable ont `recherche` bas (équivalence
    // prouvée pour Enable = 1111 : analyse/cosim_llp/equivalence_en_burst.py).
    wire [3:0] enable_w;
    lm_sync_niveau #(.W(4), .SYNC(SYNC)) sync_enable_w (.clk(clk_w), .rst_n(rst_w_n), .d(enable), .q(enable_w));
    wire       en_burst = |(recherche_w & enable_w);
    reg  [3:0] repos_vus;                              // mots de repos écrits depuis la dernière chute, saturé
    wire       wr_w = REPOS_ECRITS == 0 || en_burst || repos_vus < REPOS_ECRITS;
    always @(posedge clk_w or negedge rst_w_n)
        if (!rst_w_n)                repos_vus <= REPOS_ECRITS;  // au reset : repos, rien à écrire
        else if (en_burst)           repos_vus <= 4'd0;
        else if (wr_w && !full_w)    repos_vus <= repos_vus + 4'd1;
    // D11 (choix 6 ; plan de correction, T14) : sans rx_out_ready, la FIFO ne déborde que si Clk Système est plus lente
    // que W ; la perte est alors marquée dans le flux. Le mot écrit dans la dernière place libre, et le premier mot écrit
    // après un mot refusé, portent la marque (37e bit) : un trou suit ou précède toujours un mot marqué.
    // Avec les mots de repos sautés, `perdu` ne change qu'aux écritures (même règle que lm_top_l22, T14) : un cycle sans
    // écriture sur FIFO pleine ne perd rien, et la marque attend le prochain mot écrit.
    reg  perdu;                                        // un mot a été refusé depuis le dernier mot écrit
    always @(posedge clk_w or negedge rst_w_n)
        if (!rst_w_n)  perdu <= 1'b0;
        else if (wr_w) perdu <= full_w;
    lm_fifo_async #(.W(37), .A(FIFO_A), .SYNC(SYNC)) fifo (
        .rst_w_n(rst_w_n), .clk_w(clk_w), .wr(wr_w), .wdata({presque_w || perdu, recherche_w, mots}), .full(full_w),
        .deborde(deborde_w), .presque(presque_w),
        .rst_r_n(rst_s_n), .clk_r(clk), .rd(b_rd), .rdata(b_rdata), .empty(b_empty), .raz(1'b0)
    );

    // domaine Clk Système : un pas de l'aligneur par mot lu, ou par mot de repos une fois la fin de burst lue
    wire [3:0] masque_eff, lanes_repos;
    reg  repos;                                        // dernier mot lu : recherche bas sur les lanes du masque
    wire vide_ok = b_empty && repos;
    wire pas     = s_place && (!b_empty || vide_ok);
    assign b_rd  = s_place && !b_empty;
    always @(posedge clk or negedge rst_s_n)
        if (!rst_s_n) repos <= 1'b1;
        else if (b_rd) repos <= (b_rdata[35:32] & lanes_repos) == 4'd0;

    wire [31:0] mots_c      = b_empty ? 32'd0 : b_rdata[31:0];
    wire [3:0]  recherche_c = b_empty ? 4'd0  : b_rdata[35:32];

    // RX4 (D7, T12) : masque = Enable resynchronisé, pris seulement au repos du RX. Au reset, le RX est au repos : le
    // masque suit Enable dès le premier cycle.
    wire [3:0] enable_s;
    reg  [3:0] masque_fige;
    wire       a_inactif;
    lm_sync_niveau #(.W(4), .SYNC(SYNC)) sync_enable (.clk(clk), .rst_n(rst_s_n), .d(enable), .q(enable_s));
    assign lanes_repos = masque_fige | enable_s;
    wire rx_repos = a_inactif && s_empty && repos;
    always @(posedge clk or negedge rst_s_n)
        if (!rst_s_n) masque_fige <= 4'd0;
        else          masque_fige <= masque_eff;
    assign masque_eff = rx_repos ? enable_s : masque_fige;
    // Un burst qui commence avant que le nouvel Enable soit pris est lu avec l'ancien masque : il porte err sur tous ses
    // mots, jamais silencieux (analyse/questions_ouvertes/perte_silencieuse_clk_post.md).
    wire config_attente = enable_s != masque_eff;
    reg  config_burst;
    always @(posedge clk or negedge rst_s_n)
        if (!rst_s_n)             config_burst <= 1'b0;
        else if (a_wr && a_wsot)  config_burst <= config_attente;
    wire a_werr_c = a_werr || (a_wsot ? config_attente : config_burst);

    lm_aligneur_l22 aligneur (
        .clk_w(clk), .rst_n(rst_s_n), .en(pas), .masque(masque_eff), .recherche(recherche_c), .mots(mots_c),
        .perte(b_rd && b_rdata[36]),
        .fifo_wr(a_wr), .fifo_wdata(a_wdata), .verrou(verrou), .err_sync(err_sync), .err_sot(), .erreur_deskew(erreur_deskew),
        .burst_errone(), .fin_errone(),
        .fifo_wsot(a_wsot), .fifo_werr(a_werr), .fifo_wsot_err(a_wsot_err), .fifo_wvide(a_wvide),
        .inactif(a_inactif)
    );

    // un pas n'a lieu qu'avec place au tampon : une écriture, battement vide compris, n'y est jamais refusée
    lm_fifo_sync #(.W(36), .A(2)) tampon (
        .clk(clk), .rst_n(rst_s_n), .wr(a_wr), .wdata({a_wvide, a_wsot_err, a_werr_c, a_wsot, a_wdata}), .place(s_place),
        .rd(s_rd), .rdata(s_rdata), .empty(s_empty), .raz(1'b0)
    );

    // débordement de la FIFO asynchrone : collant sur W, puis SYNC bascules
    reg deborde_vu;
    always @(posedge clk_w or negedge rst_w_n)
        if (!rst_w_n) deborde_vu <= 1'b0;
        else          deborde_vu <= deborde_vu | deborde_w;
    lm_sync_niveau #(.W(1), .SYNC(SYNC)) sync_fifo (.clk(clk), .rst_n(rst_s_n), .d(deborde_vu), .q(erreur_fifo));

    lm_top #(
        .REMISE_TAILLE(REMISE_TAILLE), .LANE_ABSENTE(LANE_ABSENTE), .REMISE_RX(REMISE_RX), .CODAGE(CODAGE),
        .STATUT_W(STATUT_W), .HS_BIT(HS_BIT), .ETAT_LSB(ETAT_LSB), .ETAT_W(ETAT_W), .ENABLE_RX_MASQUE(1), .SYNC(SYNC)
    ) lm (
        // la LMF prend masque_eff comme Enable (ENABLE_RX_MASQUE) : sinon elle rejetterait la queue d'un burst lue entre
        // le changement d'Enable et le repos (erreur_config, masque hors Enable). La LDF (TX) suit Enable resynchronisé,
        // sans attendre le repos du RX (relecture de T12, point 2).
        .clk(clk), .rst_n(rst_s_n), .enable(enable_s), .masque(masque_eff),
        .tx_in_valid(tx_in_valid), .tx_in_ready(tx_in_ready), .tx_in_data(tx_in_data), .tx_in_nb(tx_in_nb),
        .tx_in_last(tx_in_last), .tx_in_total(tx_in_total),
        .fifo_tx_wr(fifo_tx_wr), .fifo_tx_wdata(fifo_tx_wdata), .fifo_tx_wlanes(fifo_tx_wlanes),
        .fifo_tx_fin(fifo_tx_fin), .fifo_tx_full(fifo_tx_full),
        .tx_tailles(tx_tailles), .tx_tailles_valides(tx_tailles_valides), .tx_erreur(tx_erreur),
        .fifo_rx_empty(s_empty), .fifo_rx_rd(s_rd), .fifo_rx_rdata(s_rdata[31:0]), .fifo_rx_rlanes(masque_eff),
        .fifo_rx_rsot(s_rdata[32]), .fifo_rx_rerr(s_rdata[33]), .fifo_rx_rsot_err(s_rdata[34]), .fifo_rx_rvide(s_rdata[35]),
        .fifo_rx_raz(),
        .rx_out_valid(rx_out_valid), .rx_out_data(rx_out_data), .rx_out_nb(rx_out_nb),
        .rx_out_sot(rx_out_sot), .rx_out_err(rx_out_err), .rx_out_sot_err(rx_out_sot_err),
        .rx_erreur_config(rx_erreur_config), .rx_erreur_burst(rx_erreur_burst),
        .statut_phy(statut_phy), .statut(statut), .etat(etat)
    );
endmodule

`default_nettype wire
