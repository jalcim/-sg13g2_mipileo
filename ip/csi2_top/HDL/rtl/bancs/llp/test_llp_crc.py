"""Banc de llp_crc_step contre mipi_csi2.crc.crc16.

La référence d'un pas est crc16 lancé depuis la valeur du registre avant ce pas, par la couture INIT du modèle
(celle que tests/test_vectors.py du modèle exerce). La valeur finale est comparée à crc16 sans couture.
"""
import random

import cocotb
from cocotb.triggers import Timer

import modele_llp  # noqa: F401  (met mipi_csi2 dans sys.path)
from mipi_csi2 import crc

NB_CHAINES = 60
LONGUEUR_MAX = 5000
NB_HORS_PLAGE = 2000

# §9.6, exemples de calcul du CRC : checksum donné poids faible puis poids fort
VECTEURS_NORME = [
    (bytes.fromhex("FF000002B9DCF372BBD4B85AC875C27C81F805DFFF000001"), 0x00F0),
    (bytes.fromhex("FF0000001EF01EC74F8278C582E08C70D23C78E9FF000001"), 0xE569),
    (b"123456789", 0x6F91),
    (b"", 0xFFFF),
]


def crc_depuis(init, octets):
    ancien = crc.INIT
    crc.INIT = init
    try:
        return crc.crc16(octets)
    finally:
        crc.INIT = ancien


async def pas(dut, valeur, morceau, nb=None):
    dut.i_crc.value = valeur
    # Octets au-delà du morceau aléatoires : o_crc ne doit pas les lire
    dut.i_data.value = int.from_bytes(morceau + random.randbytes(4 - len(morceau)), "little")
    dut.i_nb.value = len(morceau) if nb is None else nb
    await Timer(1, unit="ns")
    return int(dut.o_crc.value)


async def calcule(dut, octets, decoupe):
    """Fait passer octets par pas de decoupe() octets, chaque pas comparé au modèle ; rend le registre final."""
    valeur, debut, nb_pas = crc.INIT, 0, 0
    while debut < len(octets) or nb_pas == 0:
        morceau = octets[debut:debut + decoupe()]
        obtenu = await pas(dut, valeur, morceau)
        attendu = crc_depuis(valeur, morceau)
        assert obtenu == attendu, (
            f"pas {nb_pas} : C 0x{valeur:04X}, octets {morceau.hex()}, 0x{obtenu:04X}, attendu 0x{attendu:04X}"
        )
        valeur, debut, nb_pas = obtenu, debut + len(morceau), nb_pas + 1
    return valeur, nb_pas


@cocotb.test()
async def test_couture_init(dut):
    """La référence d'un pas dépend de la couture INIT du modèle : on vérifie qu'elle mord toujours."""
    assert crc_depuis(0x1234, b"") == 0x1234
    assert crc.crc16(b"") == 0xFFFF


@cocotb.test()
async def test_vecteurs_norme(dut):
    """Exemples du §9.6, valeur de contrôle CRC-16/MCRF4XX et charge vide, par pas de 4 puis de 1 à 4 au hasard."""
    for octets, attendu in VECTEURS_NORME:
        assert crc.crc16(octets) == attendu
        for decoupe in (lambda: 4, lambda: random.randint(1, 4)):
            final, _ = await calcule(dut, octets, decoupe)
            assert final == attendu, f"{octets.hex()} : 0x{final:04X}, attendu 0x{attendu:04X}"


@cocotb.test()
async def test_chaines_aleatoires(dut):
    """Chaînes de 0 à 5 000 octets, découpées en pas de 0 à 4 octets tirés au hasard."""
    longueurs = [0, 1, LONGUEUR_MAX] + [random.randint(0, LONGUEUR_MAX) for _ in range(NB_CHAINES - 3)]
    total_octets, total_pas = 0, 0
    for longueur in longueurs:
        octets = random.randbytes(longueur)
        final, nb_pas = await calcule(dut, octets, lambda: random.randint(0, 4))
        assert final == crc.crc16(octets), f"chaîne de {longueur} octets : 0x{final:04X}"
        total_octets += longueur
        total_pas += nb_pas
    dut._log.info("%d chaînes, %d octets, %d pas", len(longueurs), total_octets, total_pas)


@cocotb.test()
async def test_nb_hors_plage(dut):
    """i_nb de 5 à 7 ne se produit pas ; il est traité comme 4."""
    for _ in range(NB_HORS_PLAGE):
        valeur = random.getrandbits(16)
        morceau = random.randbytes(4)
        attendu = crc_depuis(valeur, morceau)
        for nb in (5, 6, 7):
            obtenu = await pas(dut, valeur, morceau, nb)
            assert obtenu == attendu, f"i_nb {nb} : C 0x{valeur:04X}, 0x{obtenu:04X}, attendu 0x{attendu:04X}"
    dut._log.info("%d cas hors plage", 3 * NB_HORS_PLAGE)
