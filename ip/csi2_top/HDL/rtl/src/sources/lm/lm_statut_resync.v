// Point 3 : resynchronisation du mot de statut d'une lane sur Clk Système, et décodage de l'état de la SM.
// Calque de golden/variantes.py : resynchronise (double lecture), de_gray (choix_equipe.md §3).
// Deux bascules par bit, puis une valeur n'est retenue que si deux lectures successives sont égales.
// Champs du mot de statut TBD (point 3) : largeur et position de l'état sont des paramètres.
`default_nettype none

module lm_statut_resync #(
    parameter W        = 8,         // largeur du mot de statut
    parameter CODAGE   = 1,         // état de la SM : 0 binaire ; 1 Gray (à faire valider par Lionel)
    parameter ETAT_LSB = 0,
    parameter ETAT_W   = 8,
    parameter SYNC     = 2          // bascules avant la double lecture : 2 (s1, s2), ou 3 (s1, s2, s2b ; SYNC3)
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire [W-1:0]      statut_phy,    // domaine du PHY
    output reg  [W-1:0]      statut,        // valeur retenue, domaine Clk Système
    output wire [ETAT_W-1:0] etat           // état de la SM, décodé
);
    reg  [W-1:0] s1, s2, s3;
    wire [W-1:0] s2_lu;             // sortie du synchroniseur : s2 (SYNC = 2) ou s2b (SYNC = 3)

    generate
        if (SYNC >= 3) begin : trois
            reg [W-1:0] s2b;        // troisième bascule, câblée directement derrière s2
            always @(posedge clk or negedge rst_n)
                if (!rst_n) s2b <= {W{1'b0}};
                else        s2b <= s2;
            assign s2_lu = s2b;
        end else begin : deux
            assign s2_lu = s2;
        end
    endgenerate

    // double lecture : s3 est la lecture d'avant de la sortie du synchroniseur
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            s1     <= {W{1'b0}};
            s2     <= {W{1'b0}};
            s3     <= {W{1'b0}};
            statut <= {W{1'b0}};
        end else begin
            s1 <= statut_phy;
            s2 <= s1;
            s3 <= s2_lu;
            if (s2_lu == s3)
                statut <= s2_lu;
        end

    wire [ETAT_W-1:0] champ = statut[ETAT_LSB +: ETAT_W];

    genvar b;
    generate
        if (CODAGE == 1) begin : gray
            for (b = 0; b < ETAT_W; b = b + 1) begin : bit_
                assign etat[b] = ^champ[ETAT_W-1:b];
            end
        end else begin : binaire
            assign etat = champ;
        end
    endgenerate
endmodule

`default_nettype wire
