// Règles communes de l'empaquetage des pixels (CSI-2 v1.3 §11.4), incluses dans le corps de llp_pix_rx, llp_pix_tx et
// llp_trame : codes de format, format d'un type de données, taille d'une ligne (payload_size de mipi_csi2.formats).
// Un seul endroit à toucher pour un format de plus.
//
// Taille : WC multiple du groupe en octets (3 en RAW6 et RAW12, 5 en RAW10, 7 en RAW14), non nul pour un type RAW.
// Les multiples se testent par la somme des chiffres : 4 = 1 modulo 3 (base 4), 16 = 1 modulo 5 (base 16),
// 8 = 1 modulo 7 (base 8). Un opérateur % par constante se synthétise en diviseur, bien plus profond. Exacts pour les
// 65 536 WC (vérifiés en Python).

localparam [2:0] FMT_RAW   = 3'd0;      // octets bruts : type long non image
localparam [2:0] FMT_RAW6  = 3'd1;
localparam [2:0] FMT_RAW8  = 3'd2;
localparam [2:0] FMT_RAW10 = 3'd3;
localparam [2:0] FMT_IMAGE = 3'd4;      // type image non dépaqueté (RAW7, YUV, RGB) : octets bruts
localparam [2:0] FMT_RAW12 = 3'd5;
localparam [2:0] FMT_RAW14 = 3'd6;

// Classe IMAGE de CSI-2 v1.3 (Tables 3, 10, 16, 20), comme DataTypeClass.IMAGE de mipi_csi2.packet
function automatic [2:0] format_of(input [5:0] dt);
    case (dt)
        6'h28:   format_of = FMT_RAW6;
        6'h2A:   format_of = FMT_RAW8;
        6'h2B:   format_of = FMT_RAW10;
        6'h2C:   format_of = FMT_RAW12;
        6'h2D:   format_of = FMT_RAW14;
        6'h18, 6'h19, 6'h1A, 6'h1C, 6'h1D, 6'h1E, 6'h1F,
        6'h20, 6'h21, 6'h22, 6'h23, 6'h24,
        6'h29:
                 format_of = FMT_IMAGE;
        default: format_of = FMT_RAW;
    endcase
endfunction

function automatic mult3(input [15:0] wc);
    reg [4:0] somme;                    // 8 chiffres de 0 à 3 : 24 au plus
    reg [2:0] reduite;                  // 7 au plus
    begin
        somme   = {3'd0, wc[1:0]} + {3'd0, wc[3:2]} + {3'd0, wc[5:4]} + {3'd0, wc[7:6]}
                + {3'd0, wc[9:8]} + {3'd0, wc[11:10]} + {3'd0, wc[13:12]} + {3'd0, wc[15:14]};
        reduite = {1'b0, somme[1:0]} + {1'b0, somme[3:2]} + {2'd0, somme[4]};
        mult3   = reduite == 3'd0 || reduite == 3'd3 || reduite == 3'd6;
    end
endfunction

function automatic mult5(input [15:0] wc);
    reg [5:0] somme;                    // 4 chiffres de 0 à 15 : 60 au plus
    reg [4:0] reduite;                  // 18 au plus
    begin
        somme   = {2'd0, wc[3:0]} + {2'd0, wc[7:4]} + {2'd0, wc[11:8]} + {2'd0, wc[15:12]};
        reduite = {1'b0, somme[3:0]} + {3'd0, somme[5:4]};
        mult5   = reduite == 5'd0 || reduite == 5'd5 || reduite == 5'd10 || reduite == 5'd15;
    end
endfunction

function automatic mult7(input [15:0] wc);
    reg [5:0] somme;                    // 5 chiffres de 0 à 7 et le bit 15 : 36 au plus
    reg [3:0] reduite;                  // 11 au plus
    reg [3:0] finale;                   // 8 au plus
    begin
        somme   = {3'd0, wc[2:0]} + {3'd0, wc[5:3]} + {3'd0, wc[8:6]} + {3'd0, wc[11:9]} + {3'd0, wc[14:12]}
                + {5'd0, wc[15]};
        reduite = {1'b0, somme[2:0]} + {1'b0, somme[5:3]};
        finale  = {1'b0, reduite[2:0]} + {3'd0, reduite[3]};
        mult7   = finale == 4'd0 || finale == 4'd7;
    end
endfunction

// payload_size de mipi_csi2.formats, et WC nul d'une ligne image (_Receiver._image_line)
function automatic size_bad(input [2:0] fmt, input [15:0] wc);
    case (fmt)
        FMT_RAW6, FMT_RAW12: size_bad = wc == 16'd0 || !mult3(wc);
        FMT_RAW8:            size_bad = wc == 16'd0;
        FMT_RAW10:           size_bad = wc == 16'd0 || !mult5(wc);
        FMT_RAW14:           size_bad = wc == 16'd0 || !mult7(wc);
        default:             size_bad = 1'b0;
    endcase
endfunction

// Taille d'une ligne de WC 0 à 5, seule possible quand la fin tombe au cycle de l'en-tête (au plus 3 octets suivent
// l'en-tête dans son battement) ou au suivant (plus un battement de 4 octets) : table sur WC[2:0], sans somme. Même
// verdict que size_bad pour ces WC ; RAW14 n'a aucune taille bonne sous 7. Lue par llp_pix_rx (patch 03, choix 43).
function automatic small_bad(input [2:0] fmt, input [2:0] wc);
    case (fmt)
        FMT_RAW6, FMT_RAW12: small_bad = wc != 3'd3;
        FMT_RAW8:            small_bad = wc == 3'd0;
        FMT_RAW10:           small_bad = wc != 3'd5;
        FMT_RAW14:           small_bad = 1'b1;
        default:             small_bad = 1'b0;
    endcase
endfunction
