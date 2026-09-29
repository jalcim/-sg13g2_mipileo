"""Balayage de graines du banc de llp_trame (top tb_llp_trame) : nb variable et mélange, une graine par flux.

Chaque graine fixe tout le flux (random.Random(graine)) : un écart se rejoue avec la même graine. Un écart ne
s'arrête pas au premier : il est écrit dans BALAYAGE_SORTIE (graine, scénario, message), et le balayage continue.
Variables : BALAYAGE_DEBUT (0), BALAYAGE_NB (20 : le balayage court de run_llp.py), BALAYAGE_SORTIE
(balayage_trame.txt dans le dossier de simulation). Le test échoue s'il a trouvé au moins un écart.
"""
import os
import random

import cocotb
from cocotb.clock import Clock

from test_llp_rx import GENRES_COUPE, GENRES_ENTETE, GENRES_ERREUR
from test_llp_trame import PERIODE_NS, Flux, joue, remplit, trames_defauts

GENRES = ("propre",) * 6 + GENRES_ENTETE + GENRES_ERREUR + GENRES_COUPE + ("crc", "type_reserve")


def flux_de(graine):
    """nb variable (1 à 4 octets par battement) pour les graines paires, mélange à N = 1 à 4 pour les impaires."""
    rng = random.Random(graine)
    if graine % 2 == 0:
        flux = Flux(rng, None)
        flux.parasites()
        remplit(flux, trames_defauts(rng, 60), ("propre",) * 6 + GENRES_ERREUR + GENRES_COUPE + ("crc",))
        return flux, "nb variable"
    lanes = rng.randint(1, 4)
    flux = Flux(rng, lanes)
    flux.parasites()
    remplit(flux, trames_defauts(rng, 80, (0, 1, 2, 3)), GENRES)
    return flux, f"mélange N = {lanes}"


@cocotb.test()
async def test_balayage(dut):
    """Graines BALAYAGE_DEBUT à BALAYAGE_DEBUT + BALAYAGE_NB - 1 ; écarts consignés, puis échec s'il y en a."""
    debut = int(os.environ.get("BALAYAGE_DEBUT", "0"))
    nb = int(os.environ.get("BALAYAGE_NB", "20"))
    sortie = os.environ.get("BALAYAGE_SORTIE", "balayage_trame.txt")
    Clock(dut.clk, PERIODE_NS, unit="ns").start()
    ecarts = 0
    with open(sortie, "a", encoding="utf-8") as journal:
        for graine in range(debut, debut + nb):
            flux, scenario = flux_de(graine)
            try:
                await joue(dut, flux, f"graine {graine}, {scenario}")
                journal.write(f"OK {graine} {scenario}\n")
            except AssertionError as erreur:
                ecarts += 1
                journal.write(f"ECART {graine} {scenario} : {erreur}\n")
            journal.flush()
    assert ecarts == 0, f"{ecarts} écarts sur {nb} graines, détail dans {sortie}"
