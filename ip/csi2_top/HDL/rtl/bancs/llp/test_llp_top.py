"""Banc de llp_top (top tb_llp_top, INIT_CYCLES réduit) : RX et TX à travers le sommet, compteurs, reset.

RX : flux, modèle et comparaison de test_llp_rx (joue), avec ATTENTE_RX cycles de plus après le reset
(lm_sync_reset relâche deux fronts après rst_n) et RETARD_RX cycles ajoutés aux latences (bascules d'entrée de
llp_top). À chaque cycle, chaque compteur est comparé au décompte des événements déjà comparés au modèle, saturé à
CNT_WIDTH bits. Un compteur avance au front qui suit son impulsion : le banc l'attend au cycle suivant.
- ok : paquets courts du modèle (sans fin) et paquets longs finis en état 0 ;
- crc, trunc : paquets longs finis en état 1, 2 ; trunc compte aussi les événements « court » ;
- ecc_double, dt, burst : événements « ecc », « dt », « burst » ;
- ecc_corrected : o_hdr_valid avec o_hdr_ecc_corrected, paquets jetés par rx_out_err compris, que le modèle ne rend
  pas. En fin de flux, ce total égale les paquets corrigés du modèle plus les jetés dont l'en-tête était corrigé ;
- sot_err : battements valides portant rx_out_sot_err, tels que le banc les pose.
TX : Llp.joue de test_llp_tx sur le même top : trace passée à check_tx_link, octets égaux à build_*.
Reset : relâchement à deux fronts, sorties sous reset, reset asynchrone au milieu du trafic puis reprise.
"""
import random
from collections import deque

import cocotb
from cocotb.triggers import ClockCycles, FallingEdge, Timer

import test_llp_rx as rx
import test_llp_tx as tx

COMPTEURS = ("ok", "ecc_corrected", "ecc_double", "crc", "trunc", "burst", "dt", "sot_err")
GENRE_COMPTEUR = {"ecc": "ecc_double", "dt": "dt", "court": "trunc", "burst": "burst"}
# joue relâche rst_n au front descendant F0 ; w_rst_n monte au 2e front montant qui suit ; le premier battement,
# posé à F2 après une attente d'un cycle, est pris au 3e, le premier où les bascules d'entrée sont hors reset
ATTENTE_RX = 1
# Llp.joue relâche rst_n au (CYCLES_RESET + 2)e front descendant après son départ : le premier battement pris hors
# reset est posé au (CYCLES_RESET + 4)e, soit après CYCLES_RESET + 3 cycles d'attente
ATTENTE_TX = tx.CYCLES_RESET + 3
RETARD_RX = 1                   # rangée de bascules entre rx_out_* et llp_rx
BATTEMENT_VIDE_SOT_ERR = rx.LmBeat(b"", True, True, True)   # battement vide, porteur de rx_out_sot_err
SORTIES = ("o_mon", "o_cnt", "o_tx_valid", "o_tx_data", "o_tx_nb", "o_tx_last", "o_tx_total", "o_tx_init",
           "o_req_ready", "o_pay_ready", "o_init_done")


def lit_compteurs(dut):
    largeur = int(dut.CNT_WIDTH.value)
    mot = int(dut.o_cnt.value)
    return {nom: rx.champ(mot, rang * largeur, largeur) for rang, nom in enumerate(COMPTEURS)}


class Compteurs:
    """Décompte attendu des compteurs de llp_top, comparé au RTL à chaque cycle de joue (argument suivi)."""

    def __init__(self, dut, nom):
        self.dut = dut
        self.nom = nom
        self.plafond = (1 << int(dut.CNT_WIDTH.value)) - 1
        self.compte = dict.fromkeys(COMPTEURS, 0)
        self.entete_corrigee = False
        self.corriges_modele = 0
        self.corriges_jetes = 0
        self.sot_err_en_route = deque([0] * RETARD_RX)

    def __call__(self, cycle, mot, obtenus, beat):
        attendus = {nom: min(n, self.plafond) for nom, n in self.compte.items()}
        lus = lit_compteurs(self.dut)
        assert lus == attendus, f"{self.nom}, cycle {cycle} : compteurs {lus}, attendus {attendus}"
        for _, (genre, *reste) in obtenus:
            if genre == "paquet":
                self.compte["ok" if reste[-1] is None else ("ok", "crc", "trunc")[reste[-1]]] += 1
                self.corriges_modele += reste[4]
            else:
                self.compte[GENRE_COMPTEUR[genre]] += 1
        # une fin 3 ferme toujours le paquet long précédent : elle passe avant un en-tête du même cycle
        if rx.champ(mot, 64, 1) and rx.champ(mot, 65, 2) == 3:
            self.corriges_jetes += self.entete_corrigee
        if rx.champ(mot, 0, 1):
            self.entete_corrigee = bool(rx.champ(mot, 26, 1))
            self.compte["ecc_corrected"] += self.entete_corrigee
        self.sot_err_en_route.append(int(beat != rx.CYCLE_VIDE and beat.sot_error))
        self.compte["sot_err"] += self.sot_err_en_route.popleft()

    def bilan(self):
        corriges = self.compte["ecc_corrected"]
        assert corriges == self.corriges_modele + self.corriges_jetes, \
            f"{self.nom} : {corriges} en-têtes corrigés publiés, {self.corriges_modele} paquets corrigés du modèle " \
            f"et {self.corriges_jetes} jetés corrigés"
        return dict(self.compte)


def flux_rx(lanes, construit):
    flux = rx.Flux(random.Random(random.getrandbits(64)), lanes)
    flux.parasites()
    construit(flux)
    return flux


async def joue_rx(dut, flux, nom, attente=ATTENTE_RX, pilote_reset=True):
    """rx.joue à travers llp_top, compteurs vérifiés à chaque cycle ; rend le décompte brut (non saturé)."""
    compteurs = Compteurs(dut, nom)
    await rx.joue(dut, flux, nom, attente, pilote_reset, compteurs, RETARD_RX)
    total = compteurs.bilan()
    dut._log.info("%s : compteurs %s", nom, total)
    return total


def verifie_reset(dut, quand):
    """Toutes les sorties à 0 sous reset, sauf tx_init à 1 ; reset interne bas."""
    lus = {nom: int(getattr(dut, nom).value) for nom in SORTIES}
    attendus = {nom: int(nom == "o_tx_init") for nom in SORTIES}
    assert lus == attendus, f"{quand} : sorties {lus}, attendues {attendus}"
    assert int(dut.u_top.w_rst_n.value) == 0, f"{quand} : reset synchronisé relâché"


# --- RX ----------------------------------------------------------------------------------------------------------


def erreurs_et_coupes(flux, nb_trames=20):
    rng = flux.rng
    for numero in range(nb_trames):
        flux.p_trou = rx.tire_p_trou(rng)
        flux.ecart_max = rng.choice((0, 3, rx.ECART_MAX))
        for paquet in rx.trame_imx219(rng, numero):
            if rng.random() < 0.1:
                flux.vide()
                flux.ecart()
            flux.burst(paquet, rng.choice(("propre",) + rx.GENRES_ERREUR + rx.GENRES_COUPE))


def trames_sot_err(flux, nb_trames=15):
    def genre(rng, paquet):
        return rng.choice(("propre", "ecc1_donnees", "ecc2", "type_reserve", "crc", "err_sot", "err_milieu",
                           "coupe_paquet"))
    rx.trames(flux, nb_trames, genre, p_sot_err=0.5)


@cocotb.test()
async def test_rx_melange(dut):
    """Tous les genres de test_llp_rx au hasard (en-têtes, CRC, erreurs, coupes, réservés), N = 1 à 4 et nb variable."""
    tx.Llp(dut)
    for lanes in (1, 2, 3, 4, None):
        await joue_rx(dut, flux_rx(lanes, lambda flux: rx.melange(flux, 250)),
                      f"RX mélange, N = {lanes or 'aléatoire'}")


@cocotb.test()
async def test_rx_erreurs_et_coupes(dut):
    """rx_out_err dès le sot, au milieu, dans la traîne, battements vides, coupes d'en-tête et de paquet."""
    tx.Llp(dut)
    for lanes in (1, 2, 3, 4):
        await joue_rx(dut, flux_rx(lanes, erreurs_et_coupes), f"RX erreurs et coupes, N = {lanes}")


@cocotb.test()
async def test_rx_sot_err(dut):
    """rx_out_sot_err sur la moitié des bursts, seul ou avec un en-tête abîmé, un CRC faux, une erreur, une coupe."""
    tx.Llp(dut)
    for lanes in (1, 2, 3, 4):
        total = await joue_rx(dut, flux_rx(lanes, trames_sot_err), f"RX sot_err, N = {lanes}")
        assert total["sot_err"] > 0


# --- TX ----------------------------------------------------------------------------------------------------------


@cocotb.test()
async def test_tx_courts_et_trames(dut):
    """Les 16 types courts sous les 4 VC, des trames FS, LS, ligne, LE, FE et un paquet de WC 65 535 : LM aléatoire."""
    llp = tx.Llp(dut)
    paquets = [tx.court(dt, vc) for vc in range(4) for dt in range(16)]
    for vc in range(4):
        paquets += tx.trame(vc, 3, random.randint(1, 120), random.choice(tx.TYPES_LONGS))
    paquets += [tx.court(0x02), tx.long(65535), tx.court(0x03)]
    tx.bilan(dut, "TX courts et trames", paquets, await llp.joue(paquets, tx.LmAleatoire()))


@cocotb.test()
async def test_tx_lm_realiste(dut):
    """LM à N = 1 à 4 lanes, tous les restes de WC modulo 4, sans trou."""
    llp = tx.Llp(dut)
    for lanes in (1, 2, 3, 4):
        paquets = tx.melange(150)
        tx.bilan(dut, f"TX LM réaliste N = {lanes}", paquets, await llp.joue(paquets, tx.LmRealiste(lanes)))


@cocotb.test()
async def test_tx_trous(dut):
    """Trous de l'application : pauses égales aux trous (LM toujours prêt), puis LM aléatoire et sorties sans chemin
    combinatoire depuis les entrées."""
    llp = tx.Llp(dut)
    paquets = tx.melange(150)
    res = await llp.joue(paquets, tx.LmAleatoire(0.0, 0.0), trous=0.2, attendre=True)
    assert sum(res.trous) > 0
    tx.bilan(dut, "TX trous, LM toujours prêt", paquets, res)
    paquets = tx.melange(150)
    tx.bilan(dut, "TX trous, LM aléatoire, sans chemin combinatoire", paquets,
             await llp.joue(paquets, tx.LmAleatoire(), trous=0.2, comb=True))


# --- RX et TX ensemble, reset ------------------------------------------------------------------------------------


@cocotb.test()
async def test_rx_tx_ensemble(dut):
    """Les deux voies en même temps, indépendantes : Llp.joue tient le reset, joue suit sans le piloter."""
    llp = tx.Llp(dut)
    for lanes in (1, 2, 3, 4):
        paquets = tx.melange(150)
        tache_tx = cocotb.start_soon(llp.joue(paquets, tx.LmRealiste(lanes), trous=0.1))
        await joue_rx(dut, flux_rx(lanes, lambda flux: rx.melange(flux, 150)), f"RX avec TX, N = {lanes}",
                      ATTENTE_TX, pilote_reset=False)
        tx.bilan(dut, f"TX avec RX, N = {lanes}", paquets, await tache_tx)


@cocotb.test()
async def test_reset(dut):
    """Sorties sous reset, relâchement deux fronts après rst_n, puis reset asynchrone au milieu du trafic RX et TX
    (compteurs non nuls) et reprise complète, comparée au modèle."""
    llp = tx.Llp(dut)
    front = FallingEdge(dut.clk)
    dut.i_beat.value = rx.code_battement(random.Random(1), BATTEMENT_VIDE_SOT_ERR)
    for _ in range(3):
        await front
    verifie_reset(dut, "sous reset")
    # Battement vide porteur de sot_err à chaque cycle, pris par les bascules d'entrée dès le 3e front montant après
    # le relâchement : sot_err compte au 4e, burst au 6e (o_evt_burst, latence 2) ; tx_init tombe au 3e
    dut.rst_n.value = 1
    releve = []
    for _ in range(6):
        await front
        compteurs = lit_compteurs(dut)
        releve.append((int(dut.u_top.w_rst_n.value), int(dut.o_tx_init.value), compteurs["sot_err"],
                       compteurs["burst"]))
    attendu = [(0, 1, 0, 0), (1, 1, 0, 0), (1, 0, 0, 0), (1, 0, 1, 0), (1, 0, 2, 0), (1, 0, 3, 1)]
    assert releve == attendu, f"relâchement (w_rst_n, tx_init, sot_err, burst) : {releve}, attendu {attendu}"

    rng = random.Random(random.getrandbits(64))
    paquets = tx.melange(300)
    tache_tx = cocotb.start_soon(llp.joue(paquets, tx.LmAleatoire()))
    tache_rx = cocotb.start_soon(rx.joue(dut, flux_rx(4, lambda flux: rx.melange(flux, 300)), "RX coupé par le reset",
                                         ATTENTE_TX, False, Compteurs(dut, "RX coupé par le reset"), RETARD_RX))
    await ClockCycles(dut.clk, rng.randint(2000, 4000), rising=False)
    assert not tache_tx.done() and not tache_rx.done(), "trafic fini avant le reset"
    tache_tx.cancel()
    tache_rx.cancel()
    avant = lit_compteurs(dut)
    assert avant["ok"] and avant["burst"] and int(dut.o_tx_init.value) == 0, f"trafic sans effet : {avant}"
    await Timer(rng.randint(1, 3), unit="ns")
    dut.rst_n.value = 0
    await Timer(1, unit="ns")
    verifie_reset(dut, f"reset au milieu du trafic, compteurs avant {avant}")

    paquets = tx.melange(200)
    tache_tx = cocotb.start_soon(llp.joue(paquets, tx.LmAleatoire(), trous=0.1))
    await joue_rx(dut, flux_rx(4, lambda flux: rx.melange(flux, 200)), "RX après reset", ATTENTE_TX,
                  pilote_reset=False)
    tx.bilan(dut, "TX après reset", paquets, await tache_tx)


@cocotb.test()
async def test_saturation_16_bits(dut):
    """Battement vide porteur de sot_err à chaque cycle : sot_err et burst montent à 0xFFFF et y restent."""
    tx.Llp(dut)
    assert int(dut.CNT_WIDTH.value) == 16
    dut.i_beat.value = rx.code_battement(random.Random(2), BATTEMENT_VIDE_SOT_ERR)
    for _ in range(3):
        await FallingEdge(dut.clk)
    dut.rst_n.value = 1
    # au k-ième front descendant après le relâchement : sot_err = k - 3, burst = k - 5 (relevé de test_reset)
    await ClockCycles(dut.clk, 65536, rising=False)
    releve = []
    for rang in range(65537, 65543):
        await FallingEdge(dut.clk)
        compteurs = lit_compteurs(dut)
        releve.append((rang, compteurs.pop("sot_err"), compteurs.pop("burst")))
        assert not any(compteurs.values()), f"front {rang} : {compteurs}"
    attendu = [(rang, min(rang - 3, 0xFFFF), min(rang - 5, 0xFFFF)) for rang in range(65537, 65543)]
    assert releve == attendu, f"(front, sot_err, burst) : {releve}, attendu {attendu}"
    await ClockCycles(dut.clk, 1000, rising=False)
    compteurs = lit_compteurs(dut)
    assert (compteurs["sot_err"], compteurs["burst"]) == (0xFFFF, 0xFFFF), compteurs
