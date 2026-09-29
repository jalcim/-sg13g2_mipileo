// Lane Distribution Function : paquet du module CSI-2 -> mots de la FIFO TX du PHY, et taille de chaque lane.
// Calque de golden : mots_fifo_tx (répartition CSI-2 v1.3 §8.1, un octet par lane physique, choix_equipe.md §4 et §5),
// et variantes.py : encode_tailles (a_trancher.md, point 6).
//
// Clk Système (choix_equipe.md §1 et §8). Conventions de modèle, non tranchées dans la spec :
// - entrée : jusqu'à 4 octets du paquet par battement, octet k du battement dans [8k+7:8k] (interface LLP TBD) ;
// - in_total, taille du paquet, est lu avec le premier battement ;
// - FIFO TX : fifo_wr écrit fifo_wdata ; fifo_wlanes dit quelles lanes portent un octet (None du golden),
//   fifo_fin marque le dernier mot du paquet (signaux TBD, points 1 et 5) ;
// - Enable fixe pendant un paquet ; il est échantillonné dans un registre (pris en compte au cycle suivant), ce qui
//   coupe les chemins combinatoires de l'entrée enable vers les sorties (synthese/README.md) ; le décodage des lanes
//   (N, lanes physiques, erreur) est registré à son tour (27/09/2026) : il était en tête du pire chemin de lm_top à
//   300 MHz (enable -> N -> tampon -> in_ready). Configuration prise en compte deux cycles après son changement.
`default_nettype none

module lm_ldf_tx #(
    parameter REMISE_TAILLE = 0     // point 6 : 0 registres (sortie tailles) ; 1 entete_fifo (un mot par lane en tête)
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [3:0]  enable,
    // module CSI-2
    input  wire        in_valid,
    output wire        in_ready,
    input  wire [31:0] in_data,
    input  wire [2:0]  in_nb,       // octets valides dans le battement, 1 à 4 ; 0 et 5 à 7 : battement invalide
    input  wire        in_last,     // dernier battement du paquet
    input  wire [16:0] in_total,
    // FIFO TX du PHY
    output reg         fifo_wr,
    output reg  [31:0] fifo_wdata,
    output reg  [3:0]  fifo_wlanes,
    output reg         fifo_fin,
    input  wire        fifo_full,
    // taille par lane (variante registres) : tailles[17p+16:17p], valables tant que tailles_valides est haut
    output reg  [67:0] tailles,     // registre : pas de chemin combinatoire des entrées à cette sortie
    output reg         tailles_valides,
    output reg         erreur,      // Enable invalide (aucune lane, N = 3) : rien n'est accepté
    output reg         entree_invalide  // une période (plan de correction, T9 et T15) : battement pris avec in_nb hors de
                                        // 1 à 4 (ses octets sont jetés, in_last compte), paquet fermé sans mot pour
                                        // fifo_fin, ou octets du paquet différents de in_total au dernier battement
);
    localparam REPOS = 2'd0, ENTETE = 2'd1, DONNEES = 2'd2, CALCUL = 2'd3;

    reg [1:0]  etat;
    reg [63:0] tampon;              // octets du paquet en attente, le plus ancien dans [7:0]
    reg [3:0]  cnt;                 // octets dans le tampon, 0 à 8
    reg        fin_vu;              // dernier battement reçu
    reg [1:0]  h;                   // mot d'en-tête en cours (variante entete_fifo)

    wire [2:0]  n_c;
    wire [7:0]  physique_c, logique_c;
    wire        erreur_c;
    reg  [2:0]  n;
    reg  [7:0]  physique, logique;
    wire [67:0] tailles_calculees;
    // Tailles calculées en deux temps (27/09/2026) : la division TOTAL / N et l'ajout d'un octet aux premières lanes
    // étaient en tête du pire chemin de lm_top à 300 MHz. Le premier battement n'est pas consommé en REPOS, in_total y
    // reste stable : REPOS passe par CALCUL, qui prend les tailles du registre tailles_r (un cycle de plus par paquet).
    reg  [67:0] tailles_r;

    reg  [3:0]  enable_r;

    lm_lanes_actives lanes (.enable(enable_r), .n(n_c), .physique(physique_c), .logique(logique_c), .erreur(erreur_c));
    lm_tailles calcul (.enable(enable_r), .total(in_total), .tailles(tailles_calculees), .erreur());

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            enable_r <= 4'd0;
            n        <= 3'd0;
            tailles_r <= 68'd0;
            physique <= 8'd0;
            logique  <= 8'd0;
            erreur   <= 1'b1;
        end else begin
            enable_r <= enable;
            n        <= n_c;
            tailles_r <= tailles_calculees;
            physique <= physique_c;
            logique  <= logique_c;
            erreur   <= erreur_c;
        end

    // Un mot de données prend N octets du tampon, ou le reste en fin de paquet.
    // Le contenu du mot (mot_nb) ne dépend pas de fifo_full : seule l'écriture en dépend (chemin court, synthese/README.md).
    wire [3:0] n4     = {1'b0, n};
    wire       pret   = etat == DONNEES && cnt != 4'd0 && (cnt >= n4 || fin_vu);
    wire [3:0] mot_nb = !pret ? 4'd0 : (cnt >= n4 ? n4 : cnt);
    wire [3:0] prise  = fifo_full ? 4'd0 : mot_nb;
    wire [3:0] reste  = cnt - prise;

    // Prêt sur le seul remplissage courant (27/09/2026) : au plus 4 octets en tampon, un battement de 4 tient dans les 8.
    // Plus prudent que « reste <= 4 », sans perte de débit (un mot prend N octets par cycle, un battement en apporte 4),
    // et sans le chemin n -> mot_nb -> prise -> reste -> in_ready, pire chemin de lm_top à 300 MHz.
    assign in_ready = etat == DONNEES && !fin_vu && cnt <= 4'd4;
    wire entree = in_valid && in_ready;
    // D15 (plan de correction, T9) : in_ready ne dépend pas de in_nb ; un battement invalide est pris, ses octets jetés
    wire       nb_ok  = in_nb != 3'd0 && in_nb <= 3'd4;
    wire [2:0] nb_eff = nb_ok ? in_nb : 3'd0;

    wire [31:0] masque_in = 32'hFFFF_FFFF >> (8 * (4 - nb_eff));
    wire [63:0] in_etendu = {32'd0, in_data & masque_in};

    reg [1:0] p;
    integer   i;

    always @* begin
        fifo_wr     = 1'b0;
        fifo_wdata  = 32'd0;
        fifo_wlanes = 4'd0;
        fifo_fin    = 1'b0;
        p           = 2'd0;
        if (etat == ENTETE) begin
            // bits [31:30] : lane physique ; bits [16:0] : taille (golden : encode_tailles, entete_fifo)
            p           = physique[2*h +: 2];
            fifo_wr     = !fifo_full;
            fifo_wdata  = {p, 13'd0, tailles[17*p +: 17]};
            fifo_wlanes = 4'hF;
        end else if (mot_nb != 4'd0) begin
            // octet j*N + i du paquet sur la lane logique i, placée sur sa lane physique. Écrit par lane physique : la lane
            // p prend l'octet de sa lane logique, un mux 4:1 commandé par la configuration registrée (27/09/2026 : la
            // boucle par lane logique donnait une chaîne de priorités, pire chemin de lm_top à 300 MHz).
            fifo_wr = !fifo_full;
            for (i = 0; i < 4; i = i + 1)
                if (enable_r[i] && {2'd0, logique[2*i +: 2]} < mot_nb) begin
                    fifo_wdata[8*i +: 8] = tampon[8*logique[2*i +: 2] +: 8];
                    fifo_wlanes[i]       = 1'b1;
                end
            fifo_fin = fin_vu && cnt == mot_nb;
        end
    end

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            etat            <= REPOS;
            tailles         <= 68'd0;
            tampon          <= 64'd0;
            cnt             <= 4'd0;
            fin_vu          <= 1'b0;
            h               <= 2'd0;
            tailles_valides <= 1'b0;
        end else case (etat)
            REPOS:
                if (in_valid && !erreur)
                    etat <= CALCUL;
            CALCUL: begin
                tailles         <= tailles_r;
                tailles_valides <= 1'b1;
                h               <= 2'd0;
                etat            <= REMISE_TAILLE ? ENTETE : DONNEES;
            end
            ENTETE:
                if (!fifo_full) begin
                    h <= h + 2'd1;
                    if ({1'b0, h} == n - 3'd1)
                        etat <= DONNEES;
                end
            default: begin
                // l'entrée est placée à cnt (registre) avant le décalage : même résultat que « (tampon >> prise) |
                // (entrée << reste) », les octets au-dessus de cnt étant nuls, sans la soustraction reste = cnt - prise
                // en série (27/09/2026 : cnt -> tampon, pire chemin de lm_top après routage LibreLane)
                tampon <= (tampon | (entree ? in_etendu << (8 * cnt) : 64'd0)) >> (8 * prise);
                cnt    <= reste + (entree ? {1'b0, nb_eff} : 4'd0);
                if (entree && in_last)
                    fin_vu <= 1'b1;
                // fin du paquet : dernier mot écrit ; ou rien à écrire (dernier battement sans octet valide, tampon
                // vide), le paquet se ferme sans fifo_fin et entree_invalide le signale
                if (fin_vu && ((prise != 4'd0 && reste == 4'd0) || cnt == 4'd0)) begin
                    fin_vu          <= 1'b0;
                    tailles_valides <= 1'b0;
                    etat            <= REPOS;
                end
            end
        endcase
    // T15 : octets pris dans le paquet, comparés au total annoncé (in_total, stable en REPOS, lu avec le premier battement)
    reg  [16:0] total_annonce, octets_pris;
    wire [16:0] octets_fin = octets_pris + {14'd0, nb_eff};
    wire        total_faux = entree && in_last && octets_fin != total_annonce;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            total_annonce <= 17'd0;
            octets_pris   <= 17'd0;
        end else if (etat == REPOS) begin
            total_annonce <= in_total;
            octets_pris   <= 17'd0;
        end else if (entree)
            octets_pris   <= octets_fin;

    always @(posedge clk or negedge rst_n)
        if (!rst_n) entree_invalide <= 1'b0;
        else        entree_invalide <= (entree && !nb_ok) || (etat == DONNEES && fin_vu && cnt == 4'd0) || total_faux;
endmodule

`default_nettype wire
