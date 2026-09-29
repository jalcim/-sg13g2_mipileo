"""Banc de llp_pix_rx seul (top llp_pix_rx) : jugement de taille sur tous les WC, contre mipi_csi2.formats.

Pour RAW6, RAW8, RAW10, RAW12, RAW14 et un type image non dépaqueté (RAW7), les 65 536 WC passent. Une ligne tous les
2 cycles : son en-tête long arrive avec la fin de la ligne précédente (ouverte avant ce cycle, elle se ferme d'abord),
2 cycles après l'en-tête de celle-ci. Depuis le patch 03 (choix 43), la somme de chiffres part du WC rangé à l'en-tête
et son verdict vaut à partir de 2 cycles après lui : une fin plus tôt n'est possible qu'avec un WC de 0 à 5, que juge
une table (test_petits_wc, fins au cycle de l'en-tête pour WC 0 et 1, au suivant pour WC 0 à 5). L'état de fin tiré au
hasard (0 à 3) vérifie la priorité : l'état de llp_rx passe avant l'état 4. Attendu, LATENCE cycles plus tard :
- o_eol_status = état de llp_rx s'il n'est pas 0, sinon 4 si payload_size refuse le WC (ou WC nul), sinon 0 ;
- o_sol_fmt : 1, 2, 3, 5, 6, ou 4 pour le type non dépaqueté.
Avant le patch 03 (étage d'entrée de e52f4c40, latence 2), le banc mettait l'en-tête et sa fin au même cycle pour
tous les WC, ce que llp_rx ne publie que pour un WC de 0 ou 1.
"""
import random
from collections import deque

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge

import modele_llp  # noqa: F401  (met mipi_csi2 dans sys.path)
from mipi_csi2.formats import payload_size, raw_format_by_data_type

PERIODE_NS = 8
LATENCE = 1
TYPES = {0x28: 1, 0x2A: 2, 0x2B: 3, 0x2C: 5, 0x2D: 6, 0x29: 4}     # 0x29 (RAW7) : image non dépaquetée
ENTREES = ("i_hdr_valid", "i_hdr_vc", "i_hdr_dt", "i_hdr_wc", "i_hdr_short", "i_pay_valid", "i_pay_data",
           "i_pay_nb", "i_end_valid", "i_end_status")


def taille_refusee(dt, wc):
    """payload_size en octets : la largeur en pixels n'existe que pour un WC multiple du groupe."""
    fmt = raw_format_by_data_type(dt)
    if fmt is None:
        return False
    if wc == 0 or wc % fmt.bytes_per_group:
        return True
    largeur = wc // fmt.bytes_per_group * fmt.pixels_per_group
    return payload_size(fmt.name, largeur) != wc


async def demarre(dut):
    Clock(dut.clk, PERIODE_NS, unit="ns").start()
    for nom in ENTREES:
        getattr(dut, nom).value = 0
    dut.rst_n.value = 0
    for _ in range(3):
        await FallingEdge(dut.clk)
    dut.rst_n.value = 1


async def joue(dut, cycles):
    """cycles : liste de (hdr, wc, fin, état, attendu) ; attendu (o_sol, o_eol, o_eol_status si o_eol, o_sol_fmt)
    comparé LATENCE cycles plus tard."""
    attendus = deque([None] * LATENCE)
    for hdr, wc, fin, etat, attendu in list(cycles) + [(0, 0, 0, 0, None)] * LATENCE:
        await FallingEdge(dut.clk)
        voulu = attendus.popleft()
        if voulu is not None:
            obtenu = (int(dut.o_sol.value), int(dut.o_eol.value),
                      int(dut.o_eol_status.value) if int(dut.o_eol.value) else 0, int(dut.o_sol_fmt.value))
            assert obtenu == voulu[:4], f"0x{int(dut.i_hdr_dt.value):02X}, {voulu[4]} : obtenu {obtenu}, attendu {voulu[:4]}"
        dut.i_hdr_valid.value = hdr
        dut.i_end_valid.value = fin
        dut.i_end_status.value = etat
        if hdr:
            dut.i_hdr_vc.value = random.randrange(4)
            dut.i_hdr_wc.value = wc
        attendus.append(attendu)


@cocotb.test()
async def test_tous_les_wc(dut):
    """RAW6, RAW8, RAW10, RAW12, RAW14 et RAW7 non dépaqueté, WC de 0 à 65 535, fin 2 cycles après l'en-tête."""
    await demarre(dut)
    for dt, code in TYPES.items():
        dut.i_hdr_dt.value = dt
        refus = 0

        def cycles():
            nonlocal refus
            precedente = None               # (WC, état) de la ligne ouverte
            for wc in range(65537):
                etat = random.choice((0, 0, 0, 1, 2, 3))
                fin = precedente is not None
                statut = 0
                if fin:
                    statut = precedente[1] or (4 if taille_refusee(dt, precedente[0]) else 0)
                    refus += statut == 4
                if wc < 65536:
                    yield (1, wc, int(fin), precedente[1] if fin else 0, (1, int(fin), statut, code, f"WC {wc}"))
                    yield (0, 0, 0, 0, (0, 0, 0, code, f"WC {wc}"))
                    precedente = (wc, etat)
                else:
                    yield (0, 0, 1, precedente[1], (0, 1, statut, code, "WC 65535"))
        await joue(dut, cycles())
        dut._log.info("0x%02X : 65 536 WC, %d états 4", dt, refus)


@cocotb.test()
async def test_petits_wc(dut):
    """Fins au plus tôt que llp_rx publie : au cycle de l'en-tête (WC 0 et 1), au suivant (WC 0 à 5), état tiré."""
    await demarre(dut)
    for dt, code in TYPES.items():
        dut.i_hdr_dt.value = dt
        cycles = []
        for _ in range(8):
            for wc in range(6):
                for d in ((0, 1) if wc <= 1 else (1,)):
                    etat = random.choice((0, 0, 1, 2, 3))
                    statut = etat or (4 if taille_refusee(dt, wc) else 0)
                    if d == 0:
                        cycles.append((1, wc, 1, etat, (1, 1, statut, code, f"WC {wc}, d 0")))
                    else:
                        cycles.append((1, wc, 0, 0, (1, 0, 0, code, f"WC {wc}, d 1")))
                        cycles.append((0, 0, 1, etat, (0, 1, statut, code, f"WC {wc}, d 1")))
                    cycles.append((0, 0, 0, 0, (0, 0, 0, code, f"WC {wc}")))
        await joue(dut, cycles)
