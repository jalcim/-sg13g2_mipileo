-- sr16_tx.vhd -- PROPOSITION (Claude, 28/09/2026) : SR16 TX = serialiseur 8 -> 1, miroir de sr16_mot.vhd (RX).
-- A valider par Lionel.
-- Niveau latch, comme sr16_mot.vhd : chaque affectation sous "CLK = ..." (ou "CLK_W = ...") est un TLATCH CML, sans RAZ.
-- Ce qui s'inverse par rapport au RX :
--   * le strobe CLK_W est recu (le RX l'emet) : front montant au milieu de la fenetre ou MOT est stable, comme le
--     CLK_W du RX. Pas de /4 : c'est le strobe qui donne la phase du mot.
--   * registre de mot : 8 bascules clockees par CLK_W (16 latches, maitre CLK_W bas, esclave CLK_W haut). MOT n'a
--     besoin d'etre stable qu'autour du front montant de CLK_W ; la sortie h reste stable 8 UI.
--   * synchro du strobe dans le domaine CLK : q = CLK_W echantillonne au front montant (p, q), t = q retarde d'une
--     periode (r, t). ld_a = q et non t : haut une periode, pris par les maitres A au front montant suivant.
--     ld_b = ld_a retarde d'une demi-periode (latch transparent CLK bas) : pris par les maitres B au front descendant.
--     Phase de CLK_W quelconque mais fixe (CLK_W = CLK/4 venu d'ailleurs) : latence fixe. Si le front de CLK_W
--     tombe sur un front montant de CLK, p peut etre metastable : latence +-1 periode, a tenir par le placement.
--   * chaines A et B : registres a decalage a chargement parallele (MUX2 CML devant chaque maitre, sauf la queue :
--     29/09, layout SR16_TX.py, ma(3) / mb(3) prennent h(6) / h(7) en permanence au lieu de '0' hors chargement ;
--     la queue ne sort jamais avant le chargement suivant, 4 decalages par mot). A = bits pairs,
--     bascules au front montant ; B = bits impairs, bascules au front descendant. Chargement A puis B une demi-periode
--     plus tard, puis 3 decalages chacun : 4 periodes de CLK = 8 UI = une periode de CLK_W.
--   * sortie : MUX2 CML, DOUT = A pendant CLK bas, B pendant CLK haut. Chaque chaine est choisie pendant la
--     demi-periode ou elle ne change pas (elle change au front ou le mux la quitte) : pas de course.
-- MOT(0) est emis le premier, MOT(7) le dernier (LSB en premier, [1] §6.1.2 ; 0xB8 -> 00011101).
library ieee;
use ieee.std_logic_1164.all;

entity SR16_TX is
  port (
    MOT   : in  std_logic_vector(7 downto 0);     -- mot a emettre, bit 0 emis le premier
    CLK_W : in  std_logic;                        -- strobe W = CLK / 4, front montant au milieu de la fenetre de MOT
    CLK   : in  std_logic;                        -- horloge HS : un bit par front
    DOUT  : out std_logic
  );
end entity SR16_TX;

architecture GOLDEN of SR16_TX is
  constant W : integer := 8;
  signal hm, h : std_logic_vector(W-1 downto 0);            -- registre de mot : maitres, esclaves
  signal ma, sa, mb, sb : std_logic_vector(W/2-1 downto 0); -- chaines A (pairs) et B (impairs)
  signal p, q, r, t, lb : std_logic;
  signal ld_a : std_logic;
begin
  -- registre de mot, clocke par le strobe recu
  process (CLK_W, MOT, hm)
  begin
    if CLK_W = '0' then
      hm <= MOT;
    else
      h <= hm;
    end if;
  end process;

  -- synchro du strobe
  process (CLK, CLK_W, p, q, r, ld_a)
  begin
    if CLK = '0' then
      p  <= CLK_W;
      r  <= q;
      lb <= ld_a;
    else
      q <= p;
      t <= r;
    end if;
  end process;

  ld_a <= q and not t;       -- porte CML, change au front montant

  -- chaines a chargement parallele : MUX2 CML devant chaque maitre, sauf la queue (h6, h7 en permanence)
  process (CLK, ld_a, lb, h, sa, sb, ma, mb)
  begin
    if CLK = '0' then
      for i in 0 to W/2-1 loop
        if ld_a = '1' or i = W/2-1 then ma(i) <= h(2*i);   -- queue : h6 en permanence, sans MUX2 (29/09)
        else ma(i) <= sa(i+1);
        end if;
      end loop;
      sb <= mb;
    else
      sa <= ma;
      for i in 0 to W/2-1 loop
        if lb = '1' or i = W/2-1 then mb(i) <= h(2*i+1);   -- queue : h7 en permanence, sans MUX2 (29/09)
        else mb(i) <= sb(i+1);
        end if;
      end loop;
    end if;
  end process;

  DOUT <= sa(0) when CLK = '0' else sb(0);   -- MUX2 CML de sortie
end architecture GOLDEN;
