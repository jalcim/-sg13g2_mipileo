"""Accès au modèle mipi_csi2 pour les bancs du LLP : dossier src d'un checkout de mipi-csi, donné par MIPI_CSI_SRC.

Modèle attendu : mipi-csi master e2a0781 ou plus récent (fusion de feat/llp-sot, 5ce2eef). Les règles R2, R5 et R12
de la spec d'interface, check_tx_link et formats (pack, unpack, payload_size, raw_format_by_data_type) y sont. Un
modèle antérieur à 8132e12 est refusé ici, avant toute simulation ; un modèle sans formats aussi, avec un message
qui nomme les bancs de llp_pix_rx et llp_pix_tx.
"""
import os
import sys

MODELE_MIN = "8132e12"

SRC = os.path.abspath(os.environ.get("MIPI_CSI_SRC", ""))
if not os.environ.get("MIPI_CSI_SRC") or not os.path.isdir(os.path.join(SRC, "mipi_csi2")):
    raise RuntimeError(
        f"MIPI_CSI_SRC vaut {os.environ.get('MIPI_CSI_SRC')!r} : il faut le dossier src d'un checkout de mipi-csi "
        f"(branche feat/llp-sot, {MODELE_MIN} ou plus récent), celui qui contient mipi_csi2/"
    )
os.environ["MIPI_CSI_SRC"] = SRC  # chemin absolu : les simulations tournent dans sim_build/<top>
if SRC not in sys.path:
    sys.path.insert(0, SRC)

from mipi_csi2.llp import LlpHead  # noqa: E402

try:
    from mipi_csi2.formats import pack, payload_size, raw_format_by_data_type, unpack  # noqa: E402, F401
except ImportError as absent:
    raise RuntimeError(
        "modèle mipi_csi2 sans formats.pack, unpack, payload_size ou raw_format_by_data_type : les bancs de "
        f"llp_pix_rx et llp_pix_tx demandent mipi-csi master e2a0781 ou plus récent ({absent})"
    ) from absent

try:
    from mipi_csi2.tx_link import check_tx_link  # noqa: E402, F401
except ImportError as absent:
    raise RuntimeError(f"modèle mipi_csi2 antérieur à {MODELE_MIN} : check_tx_link absent") from absent
if LlpHead(framing="sot").feed(b"\x00", error=True):
    raise RuntimeError(f"modèle mipi_csi2 antérieur à {MODELE_MIN} : R2 non appliquée (erreur avant le premier sot)")
