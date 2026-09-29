# Alimentation des macros du kit CML (sr16_rx4, sr16_tx, cml_to_cmos, cmos_to_cml, cml_gate2), vues enveloppees de
# nebula:~/depots/pcml_alim/vues : chaque rail Metal1 porte des piles Via1..TopVia1 posees dans les
# fenetres libres du GDS, reliees a des bandes TopMetal1 declarees broches VDD / VSS dans le LEF. La
# grille de la puce n'a plus qu'a descendre de TopMetal2 sur ces bandes, comme pour csi2_top.
# Halo de grille nul : l'OBS TopMetal1 des vues, gonflee du halo de 10 um, fermait les canaux de rangees entre
# macros aux bandes TopMetal1 de la puce (PDN-0179, pcml_preuve1).
# Une grille de macro -default ne doit pas exister (ou doit lister ses instances) : elle attraperait les c2c
# relies seulement par ponts et laisserait une grille vide (PDN-0232 puis PDN-0233).
# Preuve : MSPHY5973 (copie de p063_mipileo), pcml_preuve6 du 29/09/2026 : GeneratePDN rc 0, PSM-0040 VDD et VSS,
# aucun via de pdngen sous TopMetal1 dans les macros CML, DRC KLayout des zones CML 0 violation.
# A sourcer dans pdn_cfg.tcl apres la grille stdcell_grid, a la place de toute grille qui connecte
# « TopMetal1 Metal1 » sur ces macros (pdngen ignore l'OBS d'une macro pour les vias de sa propre grille).
# LibreLane source ce fichier depuis une procedure : les variables lues par les procedures pcml_* sont globales.
global pcml_block pcml_tm1 pcml_y0 pcml_off pcml_pas pcml_l pcml_dvss pcml_recouv
set pcml_maitres {sr16_rx4 sr16_tx cml_to_cmos cmos_to_cml cml_gate2}
set pcml_block [ord::get_db_block]
set pcml_tm1 [[[ord::get_db] getTech] findLayer TopMetal1]
set pcml_dbu [$pcml_block getDbUnitsPerMicron]
set pcml_pont_max [expr {int(20.0 * $pcml_dbu)}]

set pcml_instances {}
set pcml_boites {}
array unset pcml_colonnes
foreach pcml_inst [$pcml_block getInsts] {
    set pcml_maitre [[$pcml_inst getMaster] getName]
    if {[lsearch -exact $pcml_maitres $pcml_maitre] < 0} {
        continue
    }
    lappend pcml_instances [$pcml_inst getName]
    if {[$pcml_inst getOrient] ne "R0"} {
        utl::error PDN 9001 "pcml : orientation [$pcml_inst getOrient] de [$pcml_inst getName] non prise en charge (R0 seulement)"
    }
    lassign [$pcml_inst getOrigin] pcml_ox pcml_oy
    foreach pcml_iterm [$pcml_inst getITerms] {
        set pcml_net [$pcml_iterm getNet]
        if {$pcml_net == "NULL"} {
            continue
        }
        if {[lsearch -exact {POWER GROUND} [[$pcml_iterm getMTerm] getSigType]] < 0} {
            continue
        }
        foreach pcml_mpin [[$pcml_iterm getMTerm] getMPins] {
            foreach pcml_box [$pcml_mpin getGeometry] {
                if {[[$pcml_box getTechLayer] getName] ne "TopMetal1"} {
                    continue
                }
                set pcml_cle "[$pcml_net getName],[expr {$pcml_ox + [$pcml_box xMin]}],[expr {$pcml_ox + [$pcml_box xMax]}]"
                lappend pcml_colonnes($pcml_cle) [list [expr {$pcml_oy + [$pcml_box yMin]}] [expr {$pcml_oy + [$pcml_box yMax]}] [$pcml_inst getName]]
            }
        }
    }
}

# Bandes TopMetal2 de la puce (stdcell_grid, starts_with POWER) : centre VDD = coeur.y + PDN_HOFFSET + k * PDN_HPITCH,
# VSS a + PDN_HWIDTH + PDN_HSPACING (releve du DEF de p063_coupe5).
set pcml_y0 [[$pcml_block getCoreArea] yMin]
set pcml_off [expr {int(round($::env(PDN_HOFFSET) * $pcml_dbu))}]
set pcml_pas [expr {int(round($::env(PDN_HPITCH) * $pcml_dbu))}]
set pcml_l [expr {int(round($::env(PDN_HWIDTH) * $pcml_dbu))}]
set pcml_dvss [expr {int(round(($::env(PDN_HWIDTH) + $::env(PDN_HSPACING)) * $pcml_dbu))}]
set pcml_recouv [expr {int(2.0 * $pcml_dbu)}]
proc pcml_bande {net k} {
    upvar #0 pcml_y0 y0 pcml_off off pcml_pas pas pcml_dvss dvss
    set c [expr {$y0 + $off + $k * $pas}]
    if {$net eq "VSS"} {
        set c [expr {$c + $dvss}]
    }
    return $c
}
proc pcml_croise {net bas haut} {
    upvar #0 pcml_pas pas pcml_l l pcml_recouv recouv pcml_y0 y0
    set k0 [expr {int(floor(double($bas - $y0) / $pas)) - 1}]
    for {set k $k0} {$k <= $k0 + int(ceil(double($haut - $bas) / $pas)) + 2} {incr k} {
        set c [pcml_bande $net $k]
        set lo [expr {max($c - $l / 2, $bas)}]
        set hi [expr {min($c + $l / 2, $haut)}]
        if {$hi - $lo >= $recouv} {
            return 1
        }
    }
    return 0
}
proc pcml_rect {net x1 y1 x2 y2} {
    upvar #0 pcml_block block pcml_tm1 tm1
    set sw [odb::dbSWire_create [$block findNet $net] ROUTED]
    odb::dbSBox_create $sw $tm1 $x1 $y1 $x2 $y2 STRIPE
}
proc pcml_libre {x1 y1 x2 y2} {
    upvar #0 pcml_block block
    foreach inst [$block getInsts] {
        set b [$inst getBBox]
        if {[$b xMin] < $x2 && [$b xMax] > $x1 && [$b yMin] < $y2 && [$b yMax] > $y1} {
            return [$inst getName]
        }
    }
    return ""
}

# Ponts TopMetal1 entre bandes alignees de cellules empilees (colonnes c2c / m2c), puis prolongement d'une
# colonne qu'aucune bande TopMetal2 de son net ne croise (cellule de 22,36 um, pas de 75,6 um) jusqu'a la plus
# proche, si la place est libre de toute instance.
set pcml_nb_ponts 0
set pcml_nb_prolong 0
set pcml_orphelines {}
array unset pcml_dans_grille
foreach pcml_cle [lsort [array names pcml_colonnes]] {
    lassign [split $pcml_cle ","] pcml_nom pcml_x1 pcml_x2
    set pcml_seg [lsort -integer -index 0 $pcml_colonnes($pcml_cle)]
    # une chaine = liste de morceaux {y1 y2 instance|pont}
    set pcml_chaines {}
    set pcml_ch [list [lindex $pcml_seg 0]]
    set pcml_haut [lindex $pcml_seg 0 1]
    foreach pcml_s [lrange $pcml_seg 1 end] {
        lassign $pcml_s pcml_y1 pcml_y2
        set pcml_ecart [expr {$pcml_y1 - $pcml_haut}]
        if {$pcml_ecart > $pcml_pont_max} {
            lappend pcml_chaines $pcml_ch
            set pcml_ch {}
        } elseif {$pcml_ecart > 0} {
            pcml_rect $pcml_nom $pcml_x1 $pcml_haut $pcml_x2 $pcml_y1
            lappend pcml_ch [list $pcml_haut $pcml_y1 pont]
            incr pcml_nb_ponts
        }
        lappend pcml_ch $pcml_s
        if {$pcml_y2 > $pcml_haut} {
            set pcml_haut $pcml_y2
        }
    }
    lappend pcml_chaines $pcml_ch
    foreach pcml_ch $pcml_chaines {
        set pcml_bas [lindex $pcml_ch 0 0]
        set pcml_haut [lindex $pcml_ch end 1]
        set pcml_txt "colonne $pcml_nom x=[expr {$pcml_x1 / double($pcml_dbu)}]..[expr {$pcml_x2 / double($pcml_dbu)}] y=[expr {$pcml_bas / double($pcml_dbu)}]..[expr {$pcml_haut / double($pcml_dbu)}]"
        # un morceau croise par une bande TopMetal2 de son net recoit un TopVia2 : la broche d'une instance
        # (l'instance entre alors dans la grille pcml) ou un pont (connexion TopMetal1-TopMetal2 de stdcell_grid)
        set pcml_croisee 0
        foreach pcml_m $pcml_ch {
            lassign $pcml_m pcml_y1 pcml_y2 pcml_qui
            if {[pcml_croise $pcml_nom $pcml_y1 $pcml_y2]} {
                set pcml_croisee 1
                if {$pcml_qui ne "pont"} {
                    set pcml_dans_grille($pcml_qui) 1
                }
            }
        }
        if {$pcml_croisee} {
            puts "\[INFO pcml\] $pcml_txt : croisee par TopMetal2"
            continue
        }
        set pcml_k [expr {int(floor(double($pcml_haut - $pcml_y0) / $pcml_pas)) - 1}]
        set pcml_haut_ext ""
        set pcml_bas_ext ""
        for {set k [expr {$pcml_k - 2}]} {$k <= $pcml_k + 3} {incr k} {
            set c [pcml_bande $pcml_nom $k]
            if {$c - $pcml_l / 2 >= $pcml_haut - $pcml_recouv && $pcml_haut_ext eq ""} {
                set pcml_haut_ext [expr {$c + $pcml_l / 2}]
            }
            if {$c + $pcml_l / 2 <= $pcml_bas + $pcml_recouv} {
                set pcml_bas_ext [expr {$c - $pcml_l / 2}]
            }
        }
        set pcml_fait 0
        set pcml_essais {}
        if {$pcml_haut_ext ne ""} {
            lappend pcml_essais [list [expr {$pcml_haut_ext - $pcml_haut}] $pcml_haut $pcml_haut_ext]
        }
        if {$pcml_bas_ext ne ""} {
            lappend pcml_essais [list [expr {$pcml_bas - $pcml_bas_ext}] $pcml_bas_ext $pcml_bas]
        }
        foreach pcml_e [lsort -integer -index 0 $pcml_essais] {
            lassign $pcml_e pcml_long pcml_ya pcml_yb
            set pcml_gene [pcml_libre $pcml_x1 [expr {$pcml_ya + 1}] $pcml_x2 [expr {$pcml_yb - 1}]]
            if {$pcml_gene eq ""} {
                pcml_rect $pcml_nom $pcml_x1 $pcml_ya $pcml_x2 $pcml_yb
                incr pcml_nb_prolong
                puts "\[INFO pcml\] $pcml_txt : prolongee y=[expr {$pcml_ya / double($pcml_dbu)}]..[expr {$pcml_yb / double($pcml_dbu)}]"
                set pcml_fait 1
                break
            }
            puts "\[INFO pcml\] $pcml_txt : prolongement y=[expr {$pcml_ya / double($pcml_dbu)}]..[expr {$pcml_yb / double($pcml_dbu)}] bloque par $pcml_gene"
        }
        if {!$pcml_fait} {
            lappend pcml_orphelines $pcml_txt
        }
    }
}
# Une instance qu'aucune bande TopMetal2 ne croise reste hors grille (pdngen refuse une grille d'instance vide,
# PDN-0232 puis PDN-0233) : elle est alimentee par les ponts TopMetal1 poses sur ses broches.
# define_pdn_grid -instances prend des expressions regulieres non ancrees (get_insts de pdn.tcl) : c2c_mot2
# attraperait c2c_mot27. Chaque nom est donc ancre et echappe.
set pcml_grille {}
foreach pcml_n [lsort [array names pcml_dans_grille]] {
    lappend pcml_grille "^[regsub -all {[][\\.*+?(){}^$|]} $pcml_n {\\&}]\$"
}
set pcml_hors {}
foreach pcml_n $pcml_instances {
    if {![info exists pcml_dans_grille($pcml_n)]} {
        lappend pcml_hors $pcml_n
    }
}
puts "\[INFO pcml\] [llength $pcml_instances] instances du kit CML ([array size pcml_dans_grille] dans la grille pcml, [llength $pcml_hors] reliees par ponts seulement), $pcml_nb_ponts ponts, $pcml_nb_prolong prolongements TopMetal1"
puts "\[INFO pcml\] hors grille : $pcml_hors"
if {[llength $pcml_orphelines] > 0} {
    utl::error PDN 9002 "pcml : colonnes sans bande TopMetal2 de leur net : $pcml_orphelines"
}

define_pdn_grid \
    -macro \
    -instances $pcml_grille \
    -name pcml \
    -starts_with POWER \
    -halo "0 0"

add_pdn_connect \
    -grid pcml \
    -layers "$::env(PDN_VERTICAL_LAYER) $::env(PDN_HORIZONTAL_LAYER)"
