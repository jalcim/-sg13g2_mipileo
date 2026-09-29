#!/usr/bin/env python3
"""Bancs de bout en bout du renvoi RX -> TX (prompt 056), contre le golden mipi_csi2 (jalcim/mipi-csi).

Chaîne : paquets du golden (build_frame, build_long_packet, build_short_packet), erreurs injectées -> modèle PHY RX
indépendant (sources/modeles/modele_phy_dphy.py, bit par bit, un paquet par burst) -> csi2_top --renvoi -> FIFO TX de
32 mots et PHY TX modélisés (tb_renvoi.v : départ non_vide, SoT et EoT aux minimums de D-PHY v1.1 Table 14, un mot
par période de W_TX sans pause) -> octets relus par lane (fifo_tx_wlanes), paquet par paquet -> parse_packet du golden.
Horloges indépendantes : W du RX (débit par lane nominal), Clk Système 7,992 ns, W_TX décalée de l'écart en ppm.

Jugé, paquet par paquet (alignement des paquets émis sur les paquets relus, par contenu) :
- juste : relu identique au paquet d'origine ; ECC corrigée : en-tête corrigé (1 bit), contenu identique ;
- erroné marqué : paquet reçu en erreur, relu avec une erreur (CRC faux, en-tête non corrigeable, tronqué) ;
- perdu : absent au TX ; signalé si les compteurs (llp_top : ECC non corrigeable, types réservés ; renvoi : perdus,
  supprimés) en rendent compte, silencieux sinon ;
- faux silencieux : relu juste mais différent de l'origine, ou paquet en erreur relu juste (réparé), ou intrus juste ;
- abîmé : paquet reçu juste, relu en erreur ;
- FIFO TX : sous-remplissages (burst TX perdu), débordements (écriture au plein), remplissage maximal ; tampon du
  renvoi : remplissage maximal.
STATUT : un paquet générique par FE publié, VC réservé, fe_ok contre le golden (receive_frames), DT 0x08 + k.

    python3 3_digital/rtl/csi2_top/construit.py --renvoi
    MIPI_CSI_SRC=<mipi-csi master 0b97cb1 ou plus>/src python3 3_digital/rtl/csi2_top/renvoi/tests/bancs.py
        [--variantes N1,N2_CRC,...] [--lanes 1,2,4] [--debits 500,728,912,1000] [--ppm -200,0,200]
        [--scenarios imx219_raw10,...] [--paralleles 24] [--prerempli 0] [--prof 16] [--sot-extra 0]
        [--sans-campagne] [--suffixe renvoi_bancs]
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import json
import os
import random
import subprocess
import sys
from collections import Counter
from pathlib import Path

ICI = Path(__file__).resolve().parent
RENVOI = ICI.parent
TOPD = RENVOI.parent
SOURCES = TOPD / "sources"
BUILD = TOPD / "build" / "renvoi_bancs"
DIGITAL = TOPD.parents[1]
sys.path.insert(0, str(SOURCES / "modeles"))
sys.path.insert(0, str(DIGITAL / "mesures"))
if "MIPI_CSI_SRC" not in os.environ:
    sys.exit("MIPI_CSI_SRC : dossier src/ de mipi-csi (master 0b97cb1 ou plus récent)")
sys.path.insert(0, os.environ["MIPI_CSI_SRC"])
import modele_phy_dphy as P  # noqa: E402
from mipi_csi2.frame import FrameSpec, build_frame  # noqa: E402
from mipi_csi2.packet import build_long_packet, build_short_packet  # noqa: E402
from mipi_csi2.rx import parse_packet, receive_frames  # noqa: E402

DEFINES = ["-DLM_FIFO_ASYNC_P_REMPLACE", "-DLM_FIFO_SYNC_P_REMPLACE"]
TS_PS = 7992
STATUT_VC = 3
LLP_INIT = 200                     # cycles d'initialisation TX de llp_tx dans les bancs (20 000 sur la puce)

# variante : (renvoi_mode, paramètres du top)
VARIANTES = {
    "N1": (1, {"RENVOI_STATUT": 0}),
    "N1_SEUL": (1, {"RENVOI_NIVEAUX": 1, "RENVOI_STATUT": 0}),     # N2 et N3 retirés (NIVEAUX = 1)
    "N2_CRC": (2, {"RENVOI_ERREUR": 0, "RENVOI_STATUT": 0}),
    "N2_SUP": (2, {"RENVOI_ERREUR": 1, "RENVOI_STATUT": 0}),
    "N3": (3, {"RENVOI_STATUT": 0}),
    "N1_STATUT": (1, {"RENVOI_STATUT": 1}),
    "N2_STATUT": (2, {"RENVOI_ERREUR": 0, "RENVOI_STATUT": 1}),
    "N3_STATUT": (3, {"RENVOI_STATUT": 1}),
}


# ------------------------------------------------------------------------------------------------ modèle RX
class ModeleRx(P.Modele):
    """modele_phy_dphy.Modele, avec des bits inversés dans le sync d'un burst donné (sot_err d'un seul burst)."""

    def __init__(self, sync_err=None, **kw):
        super().__init__(**kw)
        self.sync_err = sync_err or {}          # burst -> [(lane, position dans le sync, UI)]

    def bit(self, l, n):
        v = super().bit(l, n)
        for b, err in self.sync_err.items():
            ev = self.bursts[b]["lanes"].get(l)
            if ev is not None and any(le == l and n == ev["sync"] + pos for le, pos in err):
                v ^= 1
        return v


# ------------------------------------------------------------------------------------------------ scénarios
def pixels(rng, bits, w, h):
    return [[rng.randrange(1 << bits) for _ in range(w)] for _ in range(h)]


def flip(p: bytes, bits) -> bytes:
    b = bytearray(p)
    for k in bits:
        b[k // 8] ^= 1 << (k % 8)
    return bytes(b)


def ecc2(rng, p):
    while True:
        a, b = rng.sample(range(24), 2)
        q = flip(p, [a, b])
        if not parse_packet(q).header_ok:
            return q


def scenario(nom, rng):
    """[(paquet d'origine, paquet émis, genre d'erreur ou None)], {burst: erreurs de sync}."""
    items, sync = [], {}
    if nom == "imx219_raw10":
        for p in build_frame(FrameSpec(width=3280, height=3, pixel_format="RAW10", frame_number=1),
                             pixels(rng, 10, 3280, 3)):
            items.append((p, p, None))
    elif nom == "imx219_raw8":
        for p in build_frame(FrameSpec(width=3280, height=2, pixel_format="RAW8", frame_number=2, virtual_channel=1,
                                       line_sync=True), pixels(rng, 8, 3280, 2)):
            items.append((p, p, None))
    elif nom == "tailles":
        items.append((build_short_packet(0, 0x00, 5),) * 2 + (None,))              # FS
        for wc in (0, 1, 2, 3, 5, 64, 1023):
            p = build_long_packet(2, 0x12, bytes(rng.randrange(256) for _ in range(wc)))
            items.append((p, p, None))
        for dt in range(0x08, 0x10):
            p = build_short_packet(0, dt, rng.randrange(1 << 16))
            items.append((p, p, None))
        p = build_long_packet(2, 0x12, bytes(rng.randrange(256) for _ in range(65535)))
        items.append((p, p, None))
        items.append((build_short_packet(0, 0x01, 5),) * 2 + (None,))              # FE
    elif nom == "erreurs":
        f = build_frame(FrameSpec(width=320, height=8, pixel_format="RAW10", frame_number=3), pixels(rng, 10, 320, 8))
        lignes = [i for i, p in enumerate(f) if (p[0] & 0x3F) >= 0x10]
        emis = list(f)
        genres = [None] * len(f)
        i = lignes[0]; emis[i] = flip(f[i], [rng.randrange(24)]); genres[i] = "ecc1"
        i = lignes[1]; b = bytearray(f[i]); b[10] ^= 0x21; emis[i] = bytes(b); genres[i] = "crc"
        i = lignes[2]; emis[i] = ecc2(rng, f[i]); genres[i] = "ecc2"
        i = lignes[3]; emis[i] = f[i][:4 + 17]; genres[i] = "tronque"
        i = lignes[5]; genres[i] = "sot_err"; sync[i] = [(0, 5)]
        for o, e, g in zip(f, emis, genres):
            items.append((o, e, g))
        for p in build_frame(FrameSpec(width=64, height=2, pixel_format="RAW8", frame_number=4),
                             pixels(rng, 8, 64, 2)):
            items.append((p, p, None))
        p = build_short_packet(1, 0x00, 9)                                           # FS à ECC corrigée
        items.append((p, flip(p, [rng.randrange(24)]), "ecc1"))
        p = build_short_packet(1, 0x01, 9)                                           # FE à ECC non corrigeable
        items.append((p, ecc2(rng, p), "ecc2"))
        for p in build_frame(FrameSpec(width=64, height=1, pixel_format="RAW8", frame_number=5),
                             pixels(rng, 8, 64, 1)):                                 # le flux continue
            items.append((p, p, None))
    else:
        raise KeyError(nom)
    return items, sync


SCENARIOS = ["imx219_raw10", "imx219_raw8", "tailles", "erreurs"]


# ------------------------------------------------------------------------------------------------ compilation
def compile_tb(variante: str, prerempli: int, prof: int) -> Path:
    mode, params = VARIANTES[variante]
    d = BUILD / f"{variante}_p{prerempli}_t{prof}"
    d.mkdir(parents=True, exist_ok=True)
    vvp = d / "tb.vvp"
    fichiers = (SOURCES / "fichiers.f").read_text().split()
    assert fichiers[0].endswith("csi2_top_renvoi.v"), "construit.py --renvoi d'abord"
    p = {**params, "RENVOI_PREREMPLI": prerempli, "RENVOI_PROF": prof, "LLP_INIT_CYCLES": LLP_INIT}
    r = subprocess.run(["iverilog", "-g2012", *DEFINES, f"-I{SOURCES / 'llp'}", "-s", "tb_renvoi", "-o", str(vvp),
                        *[f"-Ptb_renvoi.{k}={v}" for k, v in p.items()],
                        str(ICI / "tb_renvoi.v"), *fichiers], capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"iverilog {variante} :\n{r.stdout}\n{r.stderr}")
    return vvp


# ------------------------------------------------------------------------------------------------ un cas
def bornes_tx(debit_tx):
    ui = 1000.0 / debit_tx
    sot = 50.0 + 145.0 + 10 * ui + 8 * ui                  # T_LPX + T_HS-PREPARE + T_HS-ZERO (min) + sync
    eot = max(8 * ui, 60.0 + 4 * ui) + 100.0               # T_HS-TRAIL + T_HS-EXIT (min)
    return sot, eot


def relit(sortie: Path, lanes):
    """Paquets relus au TX : [(octets, sous_rempli, en-têtes)], lignes K, débordements."""
    paquets, courant, entetes, u, k, debord = [], [], [], False, None, 0
    for ligne in sortie.read_text().splitlines():
        c = ligne.split()
        if c[0] == "H":
            entetes.append(int(c[2], 16))
        elif c[0] in ("D", "B"):
            w, wl, fin = int(c[2], 16), int(c[3], 16), int(c[4])
            courant += [(w >> (8 * l)) & 0xFF for l in range(4) if wl >> l & 1]
            if fin:
                paquets.append((bytes(courant), u, entetes))
                courant, entetes, u = [], [], False
        elif c[0] == "U":
            u = True
        elif c[0] == "O":
            debord += 1
        elif c[0] == "K":
            k = [int(x) for x in c[1:]]
    return paquets, k, debord


def contenu(p: bytes):
    q = parse_packet(p) if len(p) >= 4 else None
    if q is None or not q.header_ok:
        return None, "mauvais"
    etat = "juste"
    if not q.is_short and (q.truncated or not q.crc_ok):
        etat = "mauvais"
    elif q.ecc.status.name == "CORRECTED":
        etat = "corrige"
    cle = (q.virtual_channel, q.data_type, q.data_field) if q.is_short else \
          (q.virtual_channel, q.data_type, q.word_count, bytes(q.payload))
    return cle, etat


def aligne(origines, relus):
    """Alignement par programmation dynamique : 3 si contenu identique, 1 si même longueur ou relu en erreur face à
    un paquet reçu en erreur ; renvoie {i_origine: j_relu}."""
    n, m = len(origines), len(relus)

    def score(i, j):
        o, r = origines[i], relus[j]
        if r["cle"] is not None and r["cle"] == o["cle"]:
            return 3
        if len(r["octets"]) == len(o["octets"]) or (r["etat"] == "mauvais" and o["genre"]):
            return 1
        return 0
    best = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n - 1, -1, -1):
        for j in range(m - 1, -1, -1):
            s = score(i, j)
            best[i][j] = max(best[i + 1][j], best[i][j + 1], (s + best[i + 1][j + 1]) if s else 0)
    res, i, j = {}, 0, 0
    while i < n and j < m:
        s = score(i, j)
        if s and best[i][j] == s + best[i + 1][j + 1]:
            res[i] = j
            i, j = i + 1, j + 1
        elif best[i][j] == best[i + 1][j]:
            i += 1
        else:
            j += 1
    return res


def cas(tache):
    (variante, vvp, nom, lanes, debit, ppm, graine, prerempli, prof, sot_extra) = tache
    mode, params = VARIANTES[variante]
    rng = random.Random(graine)
    items, sync = scenario(nom, rng)
    tag = f"{variante}_p{prerempli}_t{prof}_{nom}_{len(lanes)}l_{int(debit)}_{ppm:+d}"
    d = vvp.parent / "cas"
    d.mkdir(exist_ok=True)
    stim, sortie = d / f"{tag}.stim", d / f"{tag}.sortie"
    mod = ModeleRx(sync_err=sync, charges=[list(e) for _, e, _ in items], lanes=lanes, debit=debit, continue_=True,
                   graine=graine)
    mod.construit()
    ev = mod.evenements()
    with open(stim, "w") as f:
        for (t, ty, v) in ev:
            f.write(f"{t} {ty} {v:x}\n")
        f.write(f"{ev[-1][0] + 1000} 9 0\n")
    debit_tx = debit * (1 + ppm * 1e-6)
    sot, eot = bornes_tx(debit_tx)
    sot += sot_extra
    ttx = 8e6 / debit_tx
    # vidange : 30 µs, ou un paquet de 65 541 octets bourré à 1 lane dans le scénario d'erreurs (N1 : WC faux)
    fin_ps = 30e6 if nom != "erreurs" else 30e6 + 70000 * ttx
    masque = sum(1 << l for l in lanes)
    r = subprocess.run(["vvp", "-n", str(vvp), f"+TS={TS_PS}", f"+PHASE={rng.randrange(TS_PS)}", f"+MASQUE={masque:x}",
                        f"+MODE={mode}", f"+STIM={stim}", f"+SORTIE={sortie}", f"+TTX={ttx:.6f}",
                        f"+PHASE_TX={rng.uniform(0, ttx):.3f}", f"+SOT={sot * 1000:.3f}", f"+EOT={eot * 1000:.3f}",
                        "+PROF_FIFO=32", f"+FIN={fin_ps:.0f}"], capture_output=True, text=True)
    stim.unlink()
    if r.returncode:
        return dict(cas=tag, verdict="ÉCHEC", detail=f"vvp : {r.stdout[-300:]} {r.stderr[-300:]}")
    paquets, k, debord = relit(sortie, lanes)
    if k is None:
        return dict(cas=tag, verdict="ÉCHEC", detail="sortie sans ligne K")
    (k_ok, k_corr, k_dbl, k_crc, k_trunc, k_burst, k_dt, k_se, t_cok, t_cerr, t_cligne,
     rv_perdus, rv_marques, rv_supp, rv_bourres, rv_tmax, occ_max, n_u, n_bursts, reste_fifo, etat_tx,
     err_fifo) = k
    origines = []
    for o, e, g in items:
        cle, _ = contenu(o)
        origines.append(dict(octets=o, cle=cle, genre=g))
    relus, statuts = [], []
    for octets, u, _ in paquets:
        cle, etat = contenu(octets)
        if u:
            etat = "mauvais"
        if cle is not None and cle[0] == STATUT_VC and len(cle) == 3 and 0x08 <= cle[1] <= 0x0F \
                and params.get("RENVOI_STATUT", 0):
            statuts.append(dict(cle=cle, rang=len(relus)))
            continue
        relus.append(dict(octets=octets, cle=cle, etat=etat, u=u))
    a = aligne(origines, relus)
    n = Counter()
    faux, abimes = [], []
    for i, o in enumerate(origines):
        if i not in a:
            n["perdu"] += 1
            continue
        r_ = relus[a[i]]
        g = o["genre"]
        if r_["cle"] == o["cle"] and r_["etat"] != "mauvais":
            n["corrige" if (g == "ecc1" or r_["etat"] == "corrige") else "juste"] += 1
            if g in ("crc", "tronque", "ecc2"):
                n["repare"] += 1
                faux.append(f"{i}:{g} réparé")
        elif r_["etat"] == "mauvais":
            if g:
                n["marque"] += 1
            else:
                n["abime"] += 1
                abimes.append(i)
        else:
            n["faux"] += 1
            faux.append(f"{i}:{g} relu juste mais différent")
    intrus = [j for j in range(len(relus)) if j not in a.values()]
    # sous-remplissages : dans le scénario d'erreurs, ils suivent une erreur du RX (burst tronqué : la troncature n'est
    # connue qu'au sot suivant ; en N1, en-tête faux) ; ailleurs, ils viennent du débit (écart des horloges)
    n_u_err = n_u if nom == "erreurs" else 0
    n_u_debit = n_u - n_u_err
    if os.environ.get("RENVOI_DETAIL"):
        print(f"== {tag}")
        for i, o in enumerate(origines):
            r_ = relus[a[i]] if i in a else None
            print(f"  origine {i:2d} {o['genre'] or '-':8} {len(o['octets']):6d} o. dt={o['octets'][0] & 0x3F:#04x} -> "
                  + (f"relu {a[i]:2d} {r_['etat']:8} {len(r_['octets']):6d} o. {'même contenu' if r_['cle'] == o['cle'] else 'contenu différent'}"
                     f"{' U' if r_['u'] else ''}" if r_ else "perdu"))
        for j in intrus:
            print(f"  intrus {j:2d} {relus[j]['etat']:8} {len(relus[j]['octets'])} o. {relus[j]['octets'][:6].hex()}")
        print(f"  K {k}")
    for j in intrus:
        if relus[j]["etat"] == "mauvais":
            n["intrus_marque"] += 1
        else:
            n["faux"] += 1
            faux.append(f"intrus {j}")
    signale = rv_perdus + rv_supp + (0 if mode == 1 else k_dbl + k_dt)
    n["perdu_signale"] = min(n["perdu"], signale)
    n["perdu_silencieux"] = n["perdu"] - n["perdu_signale"]
    # statut : un par FE publié, dans l'ordre, fe_ok contre le golden
    st_att, st_ok = 0, 0
    if params.get("RENVOI_STATUT", 0):
        trames = [f for f in receive_frames([e for _, e, _ in items]) if not f.is_stream_level]
        fe_pub = [i for i, (o, e, g) in enumerate(items) if (o[0] & 0x3F) == 0x01 and g != "ecc2"]
        st_att = len(fe_pub)
        oks = [f.ok for f in trames]
        for q, st in enumerate(statuts):
            vc, dt, data = st["cle"]
            bon = (dt & 7) == q % 8 and q < len(oks) and bool(data >> 15) == oks[q]
            st_ok += bon
    ecarts = []
    if n["perdu_silencieux"]:
        ecarts.append(f"{n['perdu_silencieux']} perdus silencieux")
    if n["faux"] or n["repare"]:
        ecarts.append(f"faux silencieux : {faux[:4]}")
    if n_u_debit:
        ecarts.append(f"{n_u_debit} sous-remplissages de la FIFO TX")
    if debord:
        ecarts.append(f"{debord} écritures au plein")
    if nom != "erreurs" and (n["perdu"] or n["abime"] or n["marque"] or n["intrus_marque"]):
        ecarts.append(f"sans erreur injectée : {n['perdu']} perdus, {n['abime']} abîmés, {n['marque']} marqués")
    if n["abime"] and nom == "erreurs":
        ecarts.append(f"abîmés {abimes[:4]}")
    if st_att and (st_ok != st_att or len(statuts) != st_att):
        ecarts.append(f"statut : {st_ok} justes, {len(statuts)} relus, {st_att} attendus")
    if reste_fifo or etat_tx != 0:
        ecarts.append(f"TX pas vidé (FIFO {reste_fifo}, état {etat_tx})")
    return dict(cas=tag, variante=variante, scenario=nom, lanes=len(lanes), debit_mbps_par_lane=debit, ppm=ppm,
                prerempli_octets=prerempli, tampon_battements=prof, sot_extra_ns=sot_extra,
                paquets=len(origines), justes=n["juste"], ecc_corrigees=n["corrige"], marques=n["marque"],
                perdus_signales=n["perdu_signale"], perdus_silencieux=n["perdu_silencieux"],
                faux_silencieux=n["faux"] + n["repare"], abimes=n["abime"], intrus_marques=n["intrus_marque"],
                sous_remplissages=n_u_debit, sous_remplissages_erreur_rx=n_u_err, debordements=debord, fifo_tx_max_mots=occ_max, tampon_max=rv_tmax,
                bursts_tx=n_bursts, statuts=f"{st_ok}/{st_att}" if st_att else "",
                cnt_llp=f"ok={k_ok} corr={k_corr} dbl={k_dbl} crc={k_crc} trunc={k_trunc} burst={k_burst} dt={k_dt} "
                        f"sot_err={k_se}",
                cnt_renvoi=f"perdus={rv_perdus} marques={rv_marques} supprimes={rv_supp} bourres={rv_bourres}",
                verdict="ok" if not ecarts else "ÉCHEC", detail=" ; ".join(ecarts)[:500])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--variantes", default="N1,N2_CRC,N2_SUP,N3,N2_STATUT")
    ap.add_argument("--lanes", default="1,2,4")
    ap.add_argument("--debits", default="500,728,912,1000")
    ap.add_argument("--ppm", default="-200,0,200")
    ap.add_argument("--scenarios", default=",".join(SCENARIOS))
    ap.add_argument("--paralleles", type=int, default=24)
    ap.add_argument("--prerempli", type=int, default=0)
    ap.add_argument("--prof", type=int, default=16)
    ap.add_argument("--sot-extra", type=float, default=0.0, help="ns ajoutés au SoT minimal du PHY TX")
    ap.add_argument("--sans-campagne", action="store_true")
    ap.add_argument("--suffixe", default="renvoi_bancs")
    a = ap.parse_args()
    vvps = {v: compile_tb(v, a.prerempli, a.prof) for v in a.variantes.split(",")}
    lanes_de = {1: (0,), 2: (0, 1), 4: (0, 1, 2, 3)}
    taches = []
    g = 0
    for v in a.variantes.split(","):
        for nom in a.scenarios.split(","):
            for nl in map(int, a.lanes.split(",")):
                for debit in map(float, a.debits.split(",")):
                    for ppm in map(int, a.ppm.split(",")):
                        g += 1
                        taches.append((v, vvps[v], nom, lanes_de[nl], debit, ppm, 1000 + g, a.prerempli, a.prof,
                                       a.sot_extra))
    lignes = []
    with cf.ProcessPoolExecutor(a.paralleles) as ex:
        for l in ex.map(cas, taches):
            lignes.append(l)
            print({x: l.get(x) for x in ("cas", "justes", "ecc_corrigees", "marques", "perdus_signales",
                                         "perdus_silencieux", "faux_silencieux", "sous_remplissages",
                                         "sous_remplissages_erreur_rx",
                                         "fifo_tx_max_mots", "tampon_max", "statuts", "verdict", "detail")},
                  flush=True)
    ok = sum(l["verdict"] == "ok" for l in lignes)
    print(f"renvoi : {ok}/{len(lignes)} cas justes")
    if not a.sans_campagne:
        from campagne import Campagne
        m = json.loads((SOURCES / "manifeste.json").read_text())
        mc = subprocess.run(["git", "-C", os.environ["MIPI_CSI_SRC"], "rev-parse", "--short", "HEAD"],
                            capture_output=True, text=True).stdout.strip() or "hors git"
        c = Campagne("iverilog", "renvoi RX -> TX du csi2_top de bout en bout contre le golden mipi_csi2 : "
                     "N1 à N3, E_CRC et E_SUP, STATUT ; 1, 2, 4 lanes ; 500 à 1 000 Mb/s par lane ; ±200 ppm",
                     outils=["iverilog"], suffixe=a.suffixe,
                     versions={"LM": m["lcr"], "LLP": m["llp"], "mipi_csi": mc, "renvoi": json.dumps(m["renvoi"])})
        for l in lignes:
            c.ligne(**l)
        c.garde(SOURCES / "manifeste.json")
        c.garde(Path(__file__))
        c.garde(ICI / "tb_renvoi.v")
        print("campagne :", c.ferme(f"{ok} cas sur {len(lignes)} justes"))
    sys.exit(0 if ok == len(lignes) else 1)


if __name__ == "__main__":
    main()
