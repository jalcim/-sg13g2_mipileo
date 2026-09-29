"""Banc de llp_ecc_gen et llp_ecc_check (top tb_llp_ecc) contre mipi_csi2.ecc : ecc8 et correct_header.

Le mot de code fait 30 bits : 24 bits de données et ECC[5:0]. ECC[7:6] sont hors du code et ne changent pas le verdict.
"""
import itertools
import random

import cocotb
from cocotb.triggers import Timer

import modele_llp  # noqa: F401  (met mipi_csi2 dans sys.path)
from mipi_csi2.ecc import EccStatus, correct_header, ecc8

NB_ALEATOIRES = 200_000
NB_ECHANTILLONS = 64
BITS_CODE = 30


async def applique(dut, data=0, header=0):
    dut.i_data.value = data
    dut.i_header.value = header
    await Timer(1, unit="ns")


def ecc_modele(data):
    return ecc8(data.to_bytes(3, "little"))


def verifie_gen(dut, data):
    attendu = ecc_modele(data)
    obtenu = int(dut.o_ecc.value)
    assert obtenu == attendu, f"llp_ecc_gen : données 0x{data:06X}, ECC 0x{obtenu:02X}, attendu 0x{attendu:02X}"


def verifie_check(dut, header):
    res = correct_header(header.to_bytes(4, "little"))
    attendu = (int.from_bytes(res.header[:3], "little"),
               int(res.status is EccStatus.CORRECTED),
               int(res.status is EccStatus.UNCORRECTABLE))
    obtenu = (int(dut.o_data.value), int(dut.o_corrected.value), int(dut.o_uncorrectable.value))
    assert obtenu == attendu, (
        f"llp_ecc_check : en-tête 0x{header:08X}, (data, corrigé, non corrigeable) = "
        f"(0x{obtenu[0]:06X}, {obtenu[1]}, {obtenu[2]}), attendu (0x{attendu[0]:06X}, {attendu[1]}, {attendu[2]})"
    )
    return res.status


@cocotb.test()
async def test_vecteur_norme(dut):
    """§9.5, figure 46 : DI 0x37, WC 0x01F0 -> ECC 0x3F ; l'en-tête complet passe sans erreur."""
    data = 0x37 | 0x01F0 << 8
    await applique(dut, data, 0x3F << 24 | data)
    assert int(dut.o_ecc.value) == 0x3F
    assert verifie_check(dut, 0x3F << 24 | data) is EccStatus.NO_ERROR


@cocotb.test()
async def test_un_bit(dut):
    """Les 24 données à un seul bit : ECC comparé à ecc8, en-tête bien formé sans erreur."""
    for rang in range(24):
        data = 1 << rang
        header = ecc_modele(data) << 24 | data
        await applique(dut, data, header)
        verifie_gen(dut, data)
        assert verifie_check(dut, header) is EccStatus.NO_ERROR
    dut._log.info("24 vecteurs à un bit")


@cocotb.test()
async def test_aleatoire(dut):
    """En-têtes de 32 bits tirés au hasard : le syndrome couvre les trois verdicts."""
    verdicts = dict.fromkeys(EccStatus, 0)
    for _ in range(NB_ALEATOIRES):
        header = random.getrandbits(32)
        await applique(dut, header & 0xFFFFFF, header)
        verifie_gen(dut, header & 0xFFFFFF)
        verdicts[verifie_check(dut, header)] += 1
    assert all(verdicts.values()), verdicts
    dut._log.info("%d en-têtes aléatoires : %s", NB_ALEATOIRES, {s.value: n for s, n in verdicts.items()})


@cocotb.test()
async def test_erreurs_simples_et_doubles(dut):
    """Échantillon de données, chacune sans erreur, avec les 30 erreurs simples et les 435 doubles, sous les 4 ECC[7:6]."""
    echantillon = [0x000000, 0xFFFFFF, 0x01F037] + [random.getrandbits(24) for _ in range(NB_ECHANTILLONS - 3)]
    motifs = [()] + [(rang,) for rang in range(BITS_CODE)] + list(itertools.combinations(range(BITS_CODE), 2))
    assert len(motifs) == 1 + 30 + 435
    nb = 0
    for data in echantillon:
        propre = ecc_modele(data) << 24 | data
        for reserve in range(4):
            for motif in motifs:
                erreur = sum(1 << rang for rang in motif)
                header = (propre ^ erreur) | reserve << 30
                await applique(dut, data, header)
                statut = verifie_check(dut, header)
                attendu = (EccStatus.NO_ERROR, EccStatus.CORRECTED, EccStatus.UNCORRECTABLE)[len(motif)]
                assert statut is attendu, f"modèle : en-tête 0x{header:08X}, {statut}, attendu {attendu}"
                if len(motif) < 2:
                    assert int(dut.o_data.value) == data, f"en-tête 0x{header:08X} : données non restaurées"
                nb += 1
    dut._log.info("%d en-têtes (%d données x 4 ECC[7:6] x %d motifs)", nb, len(echantillon), len(motifs))
