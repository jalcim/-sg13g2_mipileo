# SDC du chip_top : AUCUN registre, AUCUNE logique CMOS. Le seul chemin est
# analogique (plot -> suiveur HBT -> plot) et la STA n'y mesure rien de
# physique : les pads analogiques sont abstraits dans leur Liberty
# (timing_model_type abstracted, valeurs a 1000) et le macro n'a pas de lib.
# Ce fichier existe parce que le flow exige un SDC ; il se limite a l'horloge
# virtuelle, sans contrainte de transition ni de charge.
#
# Son predecesseur etait le SDC du HalfAdder de cmos5l_26a : il contraignait
# ha_a_PAD/ha_b_PAD/ha_s_PAD/ha_c_PAD, ports absents de ce chip - six
# « Warning 366: port not found » par corner - et son set_max_transition
# global produisait 5 fausses violations de slew sur les pins des pads
# analogiques (mesure du 07/09/2026, RUN_2026-09-06_22-41-05).
#
# Ce qui RESTE apres ce nettoyage, et qui ne vient pas d'ici : 2 violations de
# slew sur sig_in_pad/pad et sig_out_pad/pad (RUN_2026-09-07_21-15-03), limite
# 3,5 ns posee par la Liberty IO du PDK sur le pin `pad`, slew « calcule » de
# 200 ns par un modele abstrait sans driver. Artefact de bibliotheque, checker
# non bloquant par defaut (MAX_SLEW_VIOLATION_CORNERS). A laisser visible.
current_design $::env(DESIGN_NAME)
set_units -time ns
create_clock -name __VIRTUAL_CLK__ -period $::env(CLOCK_PERIOD)
