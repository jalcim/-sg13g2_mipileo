-- sr16_mot.vhd -- PROPOSITION (Claude, 27/09/2026) : SR16 + registre de mot + /4, coupe A de L22 (mipi-lane,
-- 3_digital/spec/choix_equipe.md §11, analyse/questions/lionel/L30.md). A valider par Lionel.
-- SR16 = deux rangees de 8 TLATCH (comme SR8 = deux rangees de 4) : le golden SR8 a W = 8, 8 bits de mot.
-- Niveau latch, comme sr8_golden.vhd : chaque affectation sous "CLK = ..." est un TLATCH CML, sans remise a zero.
--   * /4 : compteur de Johnson a 2 bascules (4 latches : m0, m1 transparents CLK bas, s0, s1 transparents CLK haut).
--     Ses 4 etats sont tous dans le cycle : il n'a pas besoin de remise a zero (un anneau a jeton de 4 en aurait
--     besoin : 16 etats dont 4 valides). Phase quelconque : l'aligneur cherche le 0xB8 sur les 8 decalages.
--   * registre de mot : 8 latches de tenue, meme principe que sr8_quartets.vhd : chaine A (srab) prise pendant
--     un CLK haut sur 4, fermee au front descendant ; chaine B (srbb) pendant le CLK bas qui suit, fermee au front
--     montant. Validations : EN_A = m0 et non m1 (stable pendant CLK haut), EN_B = s0 et non s1 (stable pendant
--     CLK bas) ; horloge des latches de tenue = CLK ET EN_A, /CLK ET EN_B (portes CML, GATE2).
--   * CLK_W = non m1 : W = CLK / 4, front montant au milieu de la fenetre ou MOT est stable (7 UI sur 8 ; m1 monte
--     a l ouverture des latches B, non m1 deux periodes de CLK plus tard).
-- MOT(0) est le bit recu le premier, MOT(7) le dernier (interface choix_equipe.md §11 : mots[8p+7:8p], bit 0 le premier).
library ieee;
use ieee.std_logic_1164.all;

entity SR16 is
  port (
    DIN   : in  std_logic;
    CLK   : in  std_logic;                        -- horloge HS : un bit par front
    MOT   : out std_logic_vector(7 downto 0);     -- mot tenu, bit 0 recu le premier
    CLK_W : out std_logic                         -- W = CLK / 4
  );
end entity SR16;

architecture GOLDEN of SR16 is
  constant W : integer := 8;
  signal sraa, srab, srba, srbb : std_logic_vector(W/2-1 downto 0);
  signal ha, hb : std_logic_vector(W/2-1 downto 0);
  -- '0' initial : simulation seulement (les 4 etats du Johnson sont dans le cycle)
  signal m0, m1, s0, s1 : std_logic := '0';
  signal en_a, en_b : std_logic;
begin
  -- SR16 (golden SR8 a W = 8)
  process (CLK, DIN, sraa, srab, srba, srbb)
  begin
    if CLK = '0' then
      sraa <= DIN & srab(W/2-1 downto 1);
      srbb <= srba;
    else
      srab <= sraa;
      srba <= DIN & srbb(W/2-1 downto 1);
    end if;
  end process;

  -- /4 Johnson : s0 s1 = 00 -> 10 -> 11 -> 01 -> 00 aux fronts montants
  process (CLK, m0, m1, s0, s1)
  begin
    if CLK = '0' then
      m0 <= not s1;
      m1 <= s0;
    else
      s0 <= m0;
      s1 <= m1;
    end if;
  end process;

  en_a <= m0 and not m1;      -- porte CML, change au front descendant
  en_b <= s0 and not s1;      -- porte CML, change au front montant

  process (CLK, en_a, en_b, srab, srbb)
  begin
    if CLK = '1' and en_a = '1' then
      ha <= srab;
    end if;
    if CLK = '0' and en_b = '1' then
      hb <= srbb;
    end if;
  end process;

  g_mot : for i in 0 to W/2-1 generate
    MOT(2*i)   <= ha(i);
    MOT(2*i+1) <= hb(i);
  end generate;
  CLK_W <= not m1;           -- inversion = paire croisee en CML ; m1 descend au front descendant du milieu de la fenetre
end architecture GOLDEN;
