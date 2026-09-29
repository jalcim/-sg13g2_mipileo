"""Banc de llp_top à paramètres changés (top tb_llp_top, CNT_WIDTH = 3, INIT_CYCLES = 20 000, par run_llp.py) :
les huit compteurs saturent à 7 et y restent, vérifiés à chaque cycle comme dans test_llp_top ; l'attente de tx_init
réelle traverse le sommet, vérifiée par check_tx_link avec son init_cycles par défaut."""
import cocotb

import test_llp_rx as rx
import test_llp_tx as tx
from mipi_csi2.tx_link import INIT_CYCLES
from test_llp_top import COMPTEURS, flux_rx, joue_rx


# Un burst de chaque genre, sot_err compris, fait avancer chacun des huit compteurs au moins une fois
GENRES_SATURANTS = ("propre", "crc", "ecc1_donnees", "ecc2", "type_reserve", "coupe_paquet", "err_sot")


def sature(flux, plafond):
    """Mélange, puis plafond + 1 paquets longs de chaque genre saturant, pour que chaque compteur dépasse le plafond
    quel que soit le tirage."""
    rng = flux.rng
    rx.melange(flux, 150)
    for _ in range(plafond + 1):
        for genre in GENRES_SATURANTS:
            flux.burst(rx.build_long_packet(rng.randrange(4), 0x2B, rng.randbytes(rng.randint(8, 100))), genre, True)


@cocotb.test()
async def test_saturation(dut):
    """Mélange RX à N = 4 et 2 : chaque compteur dépasse 7 événements, le RTL reste à 7."""
    tx.Llp(dut)
    plafond = (1 << int(dut.CNT_WIDTH.value)) - 1
    assert plafond == 7
    for lanes in (4, 2):
        total = await joue_rx(dut, flux_rx(lanes, lambda flux: sature(flux, plafond)), f"saturation, N = {lanes}")
        sous = [nom for nom in COMPTEURS if total[nom] <= plafond]
        assert not sous, f"compteurs jamais saturés : {sous}, décompte {total}"


@cocotb.test()
async def test_init_reel(dut):
    """tx_init tombe une fois, o_req_ready reste à 0 pendant 20 000 cycles, puis 100 paquets partent."""
    llp = tx.Llp(dut)
    assert llp.init_cycles == INIT_CYCLES, f"INIT_CYCLES du top {llp.init_cycles}, du modèle {INIT_CYCLES}"
    paquets = tx.melange(100)
    tx.bilan(dut, "INIT_CYCLES réel", paquets, await llp.joue(paquets, tx.LmAleatoire()))
