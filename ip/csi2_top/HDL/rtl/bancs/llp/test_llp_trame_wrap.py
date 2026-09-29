"""Banc de llp_trame avec FRAME_WRAP = 1 (top tb_llp_trame) : numéro de trame modulo 256.

Règle du mode, supposée pour l'IMX219 et non confirmée par une capture (README) : 0 est un numéro ordinaire, accepté
après 0xFF ; la remise à 1 reste permise ; un numéro au-delà de 0xFF est une erreur. Le modèle n'a pas ce mode : le
banc remplace mipi_csi2.rx._frame_number_expected par la même règle, puis compare comme test_llp_trame.
"""
import random

import cocotb
from cocotb.clock import Clock

import mipi_csi2.rx as modele_rx
from test_llp_trame import PERIODE_NS, Flux, joue, remplit, trame


def attendus_modulo_256(last, lost=0):
    """Numéros acceptés après ``last`` : last + 1 à last + lost + 1 modulo 256, ou une remise de 1 à lost + 1."""
    apres = [(last + pas) % 256 for pas in range(1, lost + 2)]
    return tuple(dict.fromkeys([*apres, *range(1, lost + 2)]))


@cocotb.test()
async def test_modulo_256(dut):
    """0xFE, 0xFF, 0, 1, puis remises, sauts, numéros au-delà de 0xFF, avec et sans paquets perdus."""
    modele_rx._frame_number_expected = attendus_modulo_256
    Clock(dut.clk, PERIODE_NS, unit="ns").start()
    for nb_lanes in (1, 2, 4):
        flux = Flux(random.Random(random.getrandbits(64)), nb_lanes)
        flux.parasites()
        rng = flux.rng
        paquets = []
        for vc, suite in ((0, [0xFE, 0xFF, 0, 1, 2]), (1, [0xFF, 1, 2, 0x100, 3]), (2, [0, 1, 2, 4, 0]),
                          (3, [5, 6, 1, 0x1FF, 7])):
            for numero in suite:
                paquets += trame(rng, vc, numero, avec_ls=False, embarquees=0)
        remplit(flux, paquets, ("propre",) * 8 + ("ecc2", "err_milieu", "vide"))
        await joue(dut, flux, f"modulo 256, N = {nb_lanes}")
