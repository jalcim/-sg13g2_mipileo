// SPDX-License-Identifier: Apache-2.0
// Design nestis_cpp du chip_top — TOP PLAT (feuilles blackbox), zéro-yosys.
//
// Remplace src/chip_top.v + src/chip_core.v : au lieu de laisser un outil de
// synthèse élaborer du RTL, on émet directement la netlist structurelle plate.
// Les feuilles (pads IO) sont instanciées en blackbox → OpenROAD les résout
// via LEF (read_verilog + link_design), sans aucune passe de synthèse.
//
// Noms d'instances PLATS (pas de hiérarchie generate) — le padring
// (librelane/config.nebula.yaml) référence ces noms.
//
// Padring 3/3/3/3 (12 pads) : quatre structures de mesure et UNE alimentation
// de chaque (08/09/2026). Disposition dans librelane/config.nebula.yaml.
//
// Les deux pads de signal sont des sg13g2_IOPadAnalog, cables sur « pad » et
// jamais sur « padres » : cette seconde broche est derriere les 586,9 ohms de
// la protection ESD secondaire, qui effondreraient le gain. Laissee libre, elle
// n'est pas flottante pour autant : elle suit « pad » a travers la resistance,
// aucun courant ne la traverse, et elle n'a aucune grille cote coeur donc
// aucune antenne.
//
// 2026-09-04 : les 20 pads de reserve sont retires. C'etaient des IOPadIn dont
// le plot flottait - jusqu'a 152 uA par pad au pire cas (simule) - et ils ne
// mesuraient rien. Le die ne perd rien a leur depart : la couronne de 365,28 um
// domine la largeur exigee par les pads jusqu'a CINQ pads par cote, si bien que
// 3 ou 4 pads donnent le meme die. Voir librelane/10_floorplan.yaml.

#include <cstdlib>
#include <fstream>
#include <string>

#include <nestis/instance.hpp>
#include <nestis/module.hpp>
#include <nestis/signal.hpp>

using nestis::Dir;
using nestis::Instance;
using nestis::Module;

namespace
{
// Déclare les 4 broches d'alim d'un pad IO (ordre = interface PDK).
// Les alims ENTRENT dans la puce : input, jamais inout.
void add_pad_power(Module &pad)
{
  pad.add_signal(1, "iovdd", Dir::input);
  pad.add_signal(1, "iovss", Dir::input);
  pad.add_signal(1, "vdd", Dir::input);
  pad.add_signal(1, "vss", Dir::input);
}
} // namespace

int main()
{
  // ---- Feuilles blackbox (instanciées, jamais définies → netlist plate) ----
  // LE PAD ANALOGIQUE EST LA SEULE EXCEPTION A LA REGLE « AUCUN INOUT ».
  //
  // Cette regle vaut pour tout ce que nous ecrivons, ports du top compris, et
  // elle tient parfaitement pour les pads numeriques : l'IOPadIn recoit son plot
  // en entree, l'IOPadOut le pilote en sortie, aucune ambiguite. Mais la broche
  // « pad » de l'IOPadAnalog n'est pas un tampon, c'est un FIL : le PDK la
  // declare inout dans son propre modele Verilog, et le meme module sert ici a
  // l'entree et a la sortie du signal.
  //
  // Deux modules de noms differents seraient la seule facon de porter deux
  // directions, et c'est impossible : le nom doit etre celui de la cellule du
  // PDK, et nestis refuse deux definitions homonymes (« nom deja enregistre »).
  // Declarer arbitrairement une direction reviendrait a mentir sur un des deux
  // pads.
  //
  // La broche `padbare` (LEF genere, scripts/lef_padbare.py) designe une bande
  // de Metal3 du GDS du PDK qui est EXACTEMENT le premier port de `pad`. Deux
  // noms, un seul noeud - et Magic ne garde qu'un port par noeud. Connecter les
  // deux declare deux nets la ou le silicium n'en a qu'un, et le LVS le signale
  // a raison : UN ecart, connu, mesure le 06/09/2026.
  //
  // ON LES CONNECTE QUAND MEME, et voici pourquoi (mesure du 07/09/2026,
  // RUN_2026-09-07_21-12-30). Sans `pad`, le top n'a plus aucun port de signal ;
  // OpenRCX ecrit alors un SPEF dont la section *PORTS est VIDE, ce que la norme
  // SPEF (IEEE 1481 : *PORTS exige au moins une entree) interdit, et OpenSTA
  // meurt sur « line 2161, syntax error » aux trois corners. Le LVS a 0 coutait
  // la STA post-PnR. Voie propre, apres le tape-in : un SPEF sans section *PORTS
  // quand elle est vide (correctif OpenRCX), ou la reference LVS corrigee cote
  // netgen plutot que cote netlist. Suivi dans TODO/livraison_2026-09-29.md.
  //
  // `pad` porte le port du haut niveau, que le padring range en SPECIALNETS ;
  // `padbare` porte le net INTERNE que le routeur trace vers le macro.
  Module iopad_ana("sg13g2_IOPadAnalog");
  add_pad_power(iopad_ana);
  iopad_ana.add_signal(1, "pad", Dir::inout);
  iopad_ana.add_signal(1, "padres", Dir::output);
  iopad_ana.add_signal(1, "padbare", Dir::inout);

  // Le macro suiveur (ip/suiveur_npn) : ports = labels du GDS.
  // VCC est le collecteur du HBT, VSS le pied de Rb et de Re.
  Module suiveur("suiveur_npn");
  suiveur.add_signal(1, "VCC", Dir::input);
  suiveur.add_signal(1, "VSS", Dir::input);
  suiveur.add_signal(1, "IN", Dir::input);
  suiveur.add_signal(1, "OUT", Dir::output);

  // Du GatPoly:filler dense, sans broche ni dispositif (ip/remplissage_gatpoly) : il rend a
  // GFil.g la marge que coute une structure de mesure posee a la place d'un plot d'alimentation.
  Module remplissage("remplissage_gatpoly");

  Module iopad_iovdd("sg13g2_IOPadIOVdd");
  add_pad_power(iopad_iovdd);
  Module iopad_iovss("sg13g2_IOPadIOVss");
  add_pad_power(iopad_iovss);
  Module iopad_vdd("sg13g2_IOPadVdd");
  add_pad_power(iopad_vdd);
  Module iopad_vss("sg13g2_IOPadVss");
  add_pad_power(iopad_vss);

  // ---- Top ----
  // Aucun inout. Les ports de signal du top existent parce que sans eux le
  // SPEF n'a plus de section *PORTS et la STA post-PnR meurt (07/09/2026) ;
  // chacun est cable sur la broche `pad` de son IOPadAnalog, que le padring
  // range en SPECIALNETS. `padbare`, meme noeud, porte le net INTERNE que le
  // routeur trace. Un ecart LVS connu en decoule (deux noms pour un noeud).
  Module top("chip_top");
  top.add_signal(1, "IOVDD", Dir::input);
  top.add_signal(1, "IOVSS", Dir::input);
  top.add_signal(1, "VDD", Dir::input);
  top.add_signal(1, "VSS", Dir::input);

  // TROIS STRUCTURES, et c'est le but du chip (revue du 07/09/2026) :
  //   B  sig_*   le suiveur, macro colle aux pads, sur le NET DU PLOT,   - le circuit
  //              relie par deux rubans Metal3 sans via (21/09/2026)
  //   A  flow_*  le meme suiveur au centre, route par le flow tel quel - le temoin
  //   C  thru    deux pads relies par un fil route comme A, sans macro - la liaison
  // B - A chiffre ce que le flow numerique fait a un net analogique.
  //
  // CE QUE C NE FAIT PAS (relecture du 20/09/2026) : « A - C et B - C rendent le
  // suiveur debarrasse de sa liaison » etait FAUX. Un THRU ne de-embedde que si
  // ses acces sont ceux de la structure mesuree ; or, au SPEF du 08/09, le THRU
  // fait 174 ohms pour UN fil, quand les acces de A en font 380 (177 + 204) et
  // ceux de B 221. Trois liaisons differentes : aucune soustraction ne tient.
  // Ce que C mesure vraiment : la resistance d'un fil route par le flow, donc,
  // connaissant sa geometrie, la resistance REELLE d'un via - le tech LEF en
  // declare 20 ohms partout, qui est le MAXIMUM de la spec (5 / 9 / 20, ch. 2.14).
  // Et B - A, depuis que B est en rubans sans via, est un second capteur de la
  // meme grandeur : A est domine par ses vias et son fil de 0,2 um, B par rien.
  // D, LA STRUCTURE OPEN (21/09/2026) : un plot analogique et son bondpad, relies a RIEN
  // d'autre qu'un port du top. C'est la capacite du plot seul (66 fF) et de son bondpad
  // (125 fF), que le THRU ne peut pas donner : sans elle, rien ne se de-embedde.
  // Essayee a deux plots le 08/09/2026 et retiree : le GatPoly du chip passait sous les 15 %
  // de GFil.g (14,78 %), qui est une regle de REJET. Le poly est dans les clamps des IOPadVdd
  // et IOPadIOVdd (2552 um2 chacun, contre 239 pour un IOPadAnalog et 0 pour un plot de
  // masse). Elle revient a UN plot, a la place d'iovdd_pad_1 (le rail d'E/S ne porte aucun
  // courant ici), et quatre macros de GatPoly dense rendent la marge : 15,65 % predits.
  // vdd_pad_1 RESTE : mesure (sim/16, retour_de_masse.py et grand_signal.py), un second fil
  // de VSS ne change le gain que de 0,03 dB, alors que le second fil de VDD repousse la
  // resonance de l'alimentation de 633 a 895 MHz et met Vce hors d'atteinte de BVCEO.
  for (const char *n : {"flow_in_c", "flow_out_c", "thru_c"})
    top.add_net(1, n);

  auto wire_power = [&](Instance &pad)
  {
    top.connect(pad["iovdd"], top["IOVDD"]);
    top.connect(pad["iovss"], top["IOVSS"]);
    top.connect(pad["vdd"], top["VDD"]);
    top.connect(pad["vss"], top["VSS"]);
  };
  // Un pad analogique : `padbare` sur son net interne, `padres` libre (cf.
  // en-tete), et `pad` cable sur un port du top SEULEMENT pour les deux pads
  // du suiveur. Ces deux ports existent parce que sans aucun port de signal le
  // SPEF n'a plus de section *PORTS et la STA post-PnR meurt (07/09/2026).
  // Le LVS n'est propre dans AUCUNE des deux formes (mesure du 08/09/2026,
  // RUN_2026-09-08_13-31-43) : un port du top coute « deux noms pour un noeud »,
  // et un pad SANS port laisse son bondpad rejoindre `pad` dans le silicium
  // alors que la netlist ne cable que `padbare` (netgen fabrique un `proxypad`).
  // Six pads sans port -> 19 ecarts. Dette instruite dans
  // TODO/livraison_2026-09-29.md, hors perimetre par decision du 07/09/2026.
  //
  // `net` VIDE = structure B (21/09/2026) : UN SEUL NOM POUR UN SEUL NOEUD. `pad`
  // et `padbare` sont le meme metal ; les deux broches rejoignent donc le meme
  // net, celui du port du top, et le macro aussi. Ce net, le padring le marque
  // SPECIAL (ICeWall::placeBondPads -> makeSpecial) : le routeur l'ignore, et
  // c'est Nebula.StitchDomainToPad qui le trace. `pad` doit rester cable, c'est
  // par lui que placeBondPads rattache le bondpad ; `padbare` aussi, c'est lui
  // que la vue abstraite de Magic garde (un port par noeud) et que le LVS lit.
  auto add_ana_pad = [&](const std::string &name, const std::string &net, Dir sens, bool port_top)
  {
    Instance &pad = top.add_instance(name, iopad_ana);
    wire_power(pad);
    if (port_top)
    {
      top.add_signal(1, name + "_PAD", sens);
      top.connect(pad["pad"], top[name + "_PAD"]);
    }
    top.connect(pad["padbare"], top[net.empty() ? name + "_PAD" : net]);
    top.add_net(1, "padres_" + name + "_nc");
    top.connect(pad["padres"], top["padres_" + name + "_nc"]);
    return &pad;
  };

  // Six alimentations : une masse de chaque (les rails d'E/S courent par
  // abutement sur tout l'anneau, les rails de coeur par le core ring), deux
  // VDD et deux IOVDD - pour le bonding, et pour le GatPoly de leurs clamps
  // (cf. ci-dessus). Les deux pads liberes portent les structures de mesure.
  wire_power(top.add_instance("iovdd_pad", iopad_iovdd));
  wire_power(top.add_instance("iovss_pad", iopad_iovss));
  wire_power(top.add_instance("vdd_pad", iopad_vdd));
  wire_power(top.add_instance("vss_pad", iopad_vss));
  wire_power(top.add_instance("vdd_pad_1", iopad_vdd));

  add_ana_pad("sig_in_pad", "", Dir::input, true);
  add_ana_pad("sig_out_pad", "", Dir::output, true);
  add_ana_pad("flow_in_pad", "flow_in_c", Dir::input, false);
  add_ana_pad("flow_out_pad", "flow_out_c", Dir::output, false);
  add_ana_pad("thru_n_pad", "thru_c", Dir::input, false);
  add_ana_pad("thru_s_pad", "thru_c", Dir::input, false);
  // OPEN : `pad` DOIT porter un net, c'est par lui que placeBondPads rattache le bondpad.
  // `padbare` le rejoint, comme pour B : un seul nom pour un seul noeud.
  add_ana_pad("open_pad", "", Dir::input, true);

  for (const char *n : {"remplissage_so", "remplissage_no", "remplissage_se", "remplissage_ne"})
    top.add_instance(n, remplissage);

  // Noms d'instances = cles MACROS.instances (OpenROAD.CheckMacroInstances).
  Instance &sv = top.add_instance("suiveur", suiveur);
  top.connect(sv["VCC"], top["VDD"]);
  top.connect(sv["VSS"], top["VSS"]);
  // B : sur le net du plot. 90 % des pertes du 08/09 etaient sur le net de
  // SORTIE (sortie seule corrigee +10,3 dB, entree seule +1,0 dB).
  top.connect(sv["IN"], top["sig_in_pad_PAD"]);
  top.connect(sv["OUT"], top["sig_out_pad_PAD"]);

  Instance &svf = top.add_instance("suiveur_flow", suiveur);
  top.connect(svf["VCC"], top["VDD"]);
  top.connect(svf["VSS"], top["VSS"]);
  top.connect(svf["IN"], top["flow_in_c"]);
  top.connect(svf["OUT"], top["flow_out_c"]);

  const char *path = std::getenv("NESTIS_OUTPUT");
  std::ofstream out(path ? path : "chip_top.v");
  top.to_verilog(out, "1ns/10ps");
  return 0;
}
