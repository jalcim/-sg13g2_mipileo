"""Banc de llp_tx (top llp_tx, INIT_CYCLES réel de 20 000) : attente de tx_init vérifiée par check_tx_link avec son
init_cycles par défaut, puis des paquets mêlés. Les autres scénarios sont dans test_llp_tx.py, INIT_CYCLES réduit."""
import cocotb

from mipi_csi2.tx_link import INIT_CYCLES
from test_llp_tx import Llp, LmAleatoire, bilan, melange


@cocotb.test()
async def test_init_reel(dut):
    """tx_init tombe une fois, o_req_ready reste à 0 pendant 20 000 cycles, puis 200 paquets partent."""
    llp = Llp(dut)
    assert llp.init_cycles == INIT_CYCLES, f"INIT_CYCLES du RTL {llp.init_cycles}, du modèle {INIT_CYCLES}"
    paquets = melange(200)
    bilan(dut, "INIT_CYCLES réel", paquets, await llp.joue(paquets, LmAleatoire()))
