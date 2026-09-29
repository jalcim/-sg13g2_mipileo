// Lane Merging Function : mots de la FIFO RX du PHY -> flux d'octets livré au module CSI-2.
// Calque de golden : fusionne_rx (LM RX mince, choix_equipe.md §1, §2, §5 et §6),
// et variantes.py : fusionne_rx_variante (a_trancher.md, point 26).
//
// Clk Système (choix_equipe.md §1). Conventions de modèle, non tranchées dans la spec :
// - FIFO RX lue en « first word fall through » : fifo_rdata valable tant que fifo_empty est bas, fifo_rd dépile
//   (signaux et latence TBD, point 1) ;
// - fifo_rlanes dit quelles lanes portent un octet dans le mot (None du golden, codage TBD, point 1) ;
// - sortie : jusqu'à 4 octets par battement, octet k dans [8k+7:8k], out_nb octets valides (interface LLP TBD).
// Pas de signal de fin de burst : le module CSI-2 compte les mots (L14, choix_equipe.md §2). Trail livré.
// Configuration invalide ou burst rejeté : la FIFO est vidée et rien n'est livré (golden : exception).
// Enable et masque sont échantillonnés dans des registres (pris en compte au cycle suivant), ce qui coupe les chemins
// combinatoires de ces entrées vers les sorties (synthese/README.md) ; le décodage des lanes lues (N, lanes physiques,
// erreur) est registré à son tour (27/09/2026, pire chemin de lm_top à 300 MHz). Configuration prise en compte deux
// cycles après son changement.
`default_nettype none

module lm_lmf_rx #(
    parameter LANE_ABSENTE = 1      // point 26 : 0 erreur ; 1 selon_masque ; 2 selon_enable
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [3:0]  enable,
    input  wire [3:0]  masque,      // masque des lanes actives, venu de la SM (Q04, L15), fixe pendant le burst
    // FIFO RX du PHY
    input  wire        fifo_empty,
    output wire        fifo_rd,
    input  wire [31:0] fifo_rdata,
    input  wire [3:0]  fifo_rlanes,
    input  wire        fifo_rsot,       // D1 (a) : premier mot du burst (ou battement vide)
    input  wire        fifo_rerr,       // erreur bloquante du burst
    input  wire        fifo_rsot_err,   // une lane verrouillée à un bit près (ErrSotHS)
    input  wire        fifo_rvide,      // battement vide : aucun octet
    // module CSI-2
    output reg         out_valid,
    output reg  [31:0] out_data,
    output reg  [2:0]  out_nb,
    output reg         out_sot,     // premier battement du burst (spec/interface_lm_llp.md §2.2)
    output reg         out_err,     // erreur bloquante du burst, sur tous ses battements (§2.5)
    output reg         out_sot_err, // sur le battement out_sot seulement : ErrSotHS, avertissement (§2.6)
    output wire        erreur_config,   // masque hors des Enables, ou lanes lues invalides (aucune, N = 3)
    output wire        erreur_burst     // variante erreur : lane activée absente du masque
);
    localparam [7:0] OCTET_INVALIDE = 8'h00;    // golden : variantes.OCTET_INVALIDE

    reg  [3:0] enable_r, masque_r;

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            enable_r <= 4'd0;
            masque_r <= 4'd0;
        end else begin
            enable_r <= enable;
            masque_r <= masque;
        end

    // lanes lues, dans l'ordre des lanes logiques (golden : lanes_logiques_rx)
    wire [3:0] lues = (LANE_ABSENTE == 1) ? masque_r : enable_r;
    wire [2:0] n_c;
    wire [7:0] physique_c;
    wire       erreur_lanes_c;
    reg  [2:0] n;
    reg  [7:0] physique;
    reg        erreur_lanes;

    lm_lanes_actives lanes (.enable(lues), .n(n_c), .physique(physique_c), .logique(), .erreur(erreur_lanes_c));

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            n            <= 3'd0;
            physique     <= 8'd0;
            erreur_lanes <= 1'b1;
        end else begin
            n            <= n_c;
            physique     <= physique_c;
            erreur_lanes <= erreur_lanes_c;
        end

    assign erreur_config = erreur_lanes || (masque_r & ~enable_r) != 4'd0;
    assign erreur_burst  = LANE_ABSENTE == 0 && masque_r != enable_r;
    wire   rejet         = erreur_config || erreur_burst;

    // D11 (choix 6 ; plan de correction, T14) : pas de contre-pression en RX, le LLP prend chaque battement valide
    assign fifo_rd = !fifo_empty;

    // Compaction : octets des lanes logiques 0 à N-1, dans l'ordre.
    wire porte = (masque_r & fifo_rlanes) != 4'd0;    // au moins une lane du masque porte un octet
    reg [31:0] paquet;
    reg [2:0]  k;
    reg [1:0]  p;
    integer    i;

    always @* begin
        paquet = 32'd0;
        k      = 3'd0;
        p      = 2'd0;
        for (i = 0; i < 4; i = i + 1)
            if (i < n) begin
                p = physique[2*i +: 2];
                if (masque_r[p]) begin
                    if (fifo_rlanes[p]) begin
                        paquet[8*k +: 8] = fifo_rdata[8*p +: 8];
                        k = k + 3'd1;
                    end
                end else if (porte) begin               // selon_enable : champ d'une lane absente du masque
                    paquet[8*k +: 8] = OCTET_INVALIDE;
                    k = k + 3'd1;
                end
            end
    end

    // sot d'un mot qui ne sort pas (aucun octet d'une lane du masque) : reporté sur le battement suivant du burst
    reg  sot_attente;
    wire sort = !rejet && (k != 3'd0 || fifo_rvide);
    wire sot  = fifo_rsot || sot_attente;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            out_valid   <= 1'b0;
            out_data    <= 32'd0;
            out_nb      <= 3'd0;
            out_sot     <= 1'b0;
            out_err     <= 1'b0;
            out_sot_err <= 1'b0;
            sot_attente <= 1'b0;
        end else if (fifo_rd) begin
            out_valid   <= sort;
            out_data    <= fifo_rvide ? 32'd0 : paquet;
            out_nb      <= fifo_rvide ? 3'd0 : k;
            out_sot     <= sot;
            out_err     <= fifo_rerr;
            out_sot_err <= sot && fifo_rsot_err;
            sot_attente <= sot && !sort;
        end else
            out_valid <= 1'b0;
endmodule

`default_nettype wire
