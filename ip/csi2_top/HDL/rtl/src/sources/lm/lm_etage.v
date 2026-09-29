// Étage registré à poignée de main valid/ready, avec tampon de débordement (skid buffer), débit plein.
// Sert à lm_top pour que ses interfaces sortent de bascules : in_ready est une bascule, out_valid et out_data aussi.
// Deux places : la sortie, et un tampon qui prend la donnée acceptée pendant que la sortie est bloquée
// (in_ready est calculé avant de savoir que out_ready retombe). Ajouté le 27/09/2026 : après routage (LibreLane),
// lm_top échouait au coin lent dès 200 MHz sur des chemins qui finissaient sur ses sorties.
`default_nettype none

module lm_etage #(
    parameter W = 8
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         in_valid,
    output wire         in_ready,
    input  wire [W-1:0] in_data,
    output reg          out_valid,
    input  wire         out_ready,
    output reg  [W-1:0] out_data
);
    reg         tampon_vide;
    reg [W-1:0] tampon;

    assign in_ready = tampon_vide;
    wire entree = in_valid && tampon_vide;

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            out_valid   <= 1'b0;
            out_data    <= {W{1'b0}};
            tampon_vide <= 1'b1;
            tampon      <= {W{1'b0}};
        end else if (!out_valid || out_ready) begin
            // la sortie se libère : elle prend le tampon s'il est plein, sinon l'entrée
            if (!tampon_vide) begin
                out_valid   <= 1'b1;
                out_data    <= tampon;
                tampon_vide <= 1'b1;
            end else begin
                out_valid <= entree;
                if (entree) out_data <= in_data;
            end
        end else if (entree) begin
            // sortie bloquée : la donnée acceptée va dans le tampon
            tampon      <= in_data;
            tampon_vide <= 1'b0;
        end
endmodule

`default_nettype wire
