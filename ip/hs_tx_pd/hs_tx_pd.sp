* HS_TX_PD : pre-driver d une paire HS-TX (MIPI_IOPadTX P et N), cellules standard sg13g2, domaine coeur 1,2 V (29/09/2026)
* Entrees (top_tx / tx_data_lane) : D = dout (donnee HS serie), OE = hs_oe, LPP / LPN = lp_p / lp_n
* Sorties vers les bornes des deux plots :
*   HSP -> IN_HS du plot P = OE & /D   (la derivation de P tire P en bas : P suit D)
*   HSN -> IN_HS du plot N = OE &  D
*   LPINP -> LP_IN du plot P = /(LPP & /OE)   (etage LP du plot = inverseur : P suit LPP ; OE=1 -> LP_IN=1 -> sortie LP a 0)
*   LPINN -> LP_IN du plot N = /(LPN & /OE)
* OE = 0 : HSP = HSN = 0, derivations bloquees (etat S00 du banc HS_TX, DES17).
* Charge : grille de la derivation XMN, 162,7 um / 0,13 um par plot (~0,4 pF) -> sg13g2_inv_16 en sortie.
* Chemins equilibres : D -> 3 x inv_1 (P) / buf_2 (N) -> nand2_2 (avec OE) -> inv_16.

.subckt hs_tx_pd D OE LPP LPN HSP HSN LPINP LPINN VDD VSS
*                         Y/X   A    B    VDD VSS
XDB1   DB1  D          VDD VSS  sg13g2_inv_1
XDB2   DB2  DB1        VDD VSS  sg13g2_inv_1
XDB    DB   DB2        VDD VSS  sg13g2_inv_1
XDT    DT   D          VDD VSS  sg13g2_buf_2
XNP    NP   DB   OE    VDD VSS  sg13g2_nand2_2
XNN    NN   DT   OE    VDD VSS  sg13g2_nand2_2
XOP    HSP  NP         VDD VSS  sg13g2_inv_16
XON    HSN  NN         VDD VSS  sg13g2_inv_16
XOEB   OEB  OE         VDD VSS  sg13g2_inv_1
XLP    LPINP LPP  OEB  VDD VSS  sg13g2_nand2_2
XLN    LPINN LPN  OEB  VDD VSS  sg13g2_nand2_2
.ends hs_tx_pd
