-- sr16_mot.vhd -- PROPOSITION (Claude, 27/09/2026) : SR16 + registre de mot + /4, coupe A de L22 (mipi-lane,
-- 3_digital/spec/choix_equipe.md §11, analyse/questions/lionel/L30.md). A valider par Lionel.
-- 28/09 : decoupe en deux entites (Lionel) et top a 4 lanes :
--   DIV4     lane clock : /4 et validations, un seul pour toutes les lanes ;
--   SERDES16 lane data  : SR16 + registre de mot ;
--   SR16     top : 1 lane clock (DIV4) + N lanes data (SERDES16) sur la meme horloge et les memes validations.
--   Le /4 etant commun, toutes les lanes coupent leurs mots au meme instant : des 0xB8 emis ensemble sont vus au
--   meme rang de bit dans le meme mot sur toutes les lanes.
-- SR16 = deux rangees de 8 TLATCH (comme SR8 = deux rangees de 4) : le golden SR8 a W = 8, 8 bits de mot.
-- Niveau latch, comme sr8_golden.vhd : chaque affectation sous "CLK = ..." est un TLATCH CML, sans remise a zero.
--   * /4 : compteur de Johnson a 2 bascules (4 latches : m0, m1 transparents CLK bas, s0, s1 transparents CLK haut).
--     Ses 4 etats sont tous dans le cycle : il n'a pas besoin de remise a zero (un anneau a jeton de 4 en aurait
--     besoin : 16 etats dont 4 valides). Phase quelconque : l'aligneur cherche le 0xB8 sur les 8 decalages.
--   * registre de mot : 8 latches de tenue, meme principe que sr8_quartets.vhd : chaine A (srab) prise pendant
--     un CLK haut sur 4, fermee au front descendant ; chaine B (srbb) pendant le CLK bas qui suit, fermee au front
--     montant. Validations : EN_A = m0 et non m1 (stable pendant CLK haut), EN_B = s0 et non s1 (stable pendant
--     CLK bas) ; horloge des latches de tenue = CLK ET EN_A, /CLK ET EN_B (portes CML, GATE2, dans chaque lane).
--   * CLK_W = non m1 : W = CLK / 4, front montant au milieu de la fenetre ou MOT est stable (7 UI sur 8 ; m1 monte
--     a l ouverture des latches B, non m1 deux periodes de CLK plus tard).
-- MOT(0) est le bit recu le premier, MOT(7) le dernier (interface choix_equipe.md §11 : mots[8p+7:8p], bit 0 le premier).
-- Top : MOT(8p+7 downto 8p) = mot de la lane p.
library ieee;
use ieee.std_logic_1164.all;

-- lane clock : /4 Johnson et validations des registres de mot
entity DIV4 is
  port (
    CLK   : in  std_logic;                        -- horloge HS
    EN_A  : out std_logic;                        -- validation chaine A, stable pendant CLK haut
    EN_B  : out std_logic;                        -- validation chaine B, stable pendant CLK bas
    CLK_W : out std_logic                         -- W = CLK / 4
  );
end entity DIV4;

architecture GOLDEN of DIV4 is
  -- '0' initial : simulation seulement (les 4 etats du Johnson sont dans le cycle)
  signal m0, m1, s0, s1 : std_logic := '0';
begin
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

  EN_A  <= m0 and not m1;    -- porte CML, change au front descendant
  EN_B  <= s0 and not s1;    -- porte CML, change au front montant
  CLK_W <= not m1;           -- inversion = paire croisee en CML ; m1 descend au front descendant du milieu de la fenetre
end architecture GOLDEN;

library ieee;
use ieee.std_logic_1164.all;

-- lane data : SR16 + registre de mot
entity SERDES16 is
  port (
    DIN   : in  std_logic;
    CLK   : in  std_logic;                        -- horloge HS : un bit par front
    EN_A  : in  std_logic;                        -- de DIV4
    EN_B  : in  std_logic;                        -- de DIV4
    MOT   : out std_logic_vector(7 downto 0)      -- mot tenu, bit 0 recu le premier
  );
end entity SERDES16;

architecture GOLDEN of SERDES16 is
  constant W : integer := 8;
  signal sraa, srab, srba, srbb : std_logic_vector(W/2-1 downto 0);
  signal ha, hb : std_logic_vector(W/2-1 downto 0);
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

  process (CLK, EN_A, EN_B, srab, srbb)
  begin
    if CLK = '1' and EN_A = '1' then
      ha <= srab;
    end if;
    if CLK = '0' and EN_B = '1' then
      hb <= srbb;
    end if;
  end process;

  g_mot : for i in 0 to W/2-1 generate
    MOT(2*i)   <= ha(i);
    MOT(2*i+1) <= hb(i);
  end generate;
end architecture GOLDEN;

library ieee;
use ieee.std_logic_1164.all;

-- top : 1 lane clock + N lanes data
entity SR16 is
  generic (N : positive := 4);
  port (
    DIN   : in  std_logic_vector(N-1 downto 0);   -- une entree par lane data
    CLK   : in  std_logic;                        -- horloge HS, de la lane clock
    MOT   : out std_logic_vector(8*N-1 downto 0); -- MOT(8p+7 downto 8p) = lane p, bit 0 recu le premier
    CLK_W : out std_logic                         -- W = CLK / 4, commun aux lanes
  );
end entity SR16;

architecture GOLDEN of SR16 is
  signal en_a, en_b : std_logic;
begin
  lane_clk : entity work.DIV4(GOLDEN) port map (CLK => CLK, EN_A => en_a, EN_B => en_b, CLK_W => CLK_W);

  g_lane : for p in 0 to N-1 generate
    lane_d : entity work.SERDES16(GOLDEN)
      port map (DIN => DIN(p), CLK => CLK, EN_A => en_a, EN_B => en_b, MOT => MOT(8*p+7 downto 8*p));
  end generate;
end architecture GOLDEN;
