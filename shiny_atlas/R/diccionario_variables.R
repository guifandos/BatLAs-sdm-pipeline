# Diccionario de variables: mapea codigos internos a nombres interpretables
# Para el atlas de distribucion de murcielagos de la Peninsula Iberica

DICCIONARIO_VARS <- c(

 # --- Clima: Temperatura ---
 "Bio1"      = "Temp. media anual",
 "Bio2"      = "Rango diurno medio temp.",
 "Bio3"      = "Isotermalidad",
 "Bio4"      = "Estacionalidad temp.",
 "Bio5"      = "Temp. max. mes mas calido",
 "Bio6"      = "Temp. min. mes mas frio",
 "Bio7"      = "Rango anual temp.",
 "Bio8"      = "Temp. media trimestre humedo",
 "Bio9"      = "Temp. media trimestre seco",
 "Bio10"     = "Temp. media trimestre calido",
 "Bio11"     = "Temp. media trimestre frio",
 "TSum"      = "Temp. media verano",
 "TxJan"     = "Temp. max. enero",
 "TxSpr"     = "Temp. max. primavera",
 "TnWin"     = "Temp. min. invierno",
 "DTN0Sum"   = "Dias Tmin < 0 C verano",
 "DTN20"     = "Dias Tmin > 20 C anual",
 "DTN20Aut"  = "Dias Tmin > 20 C otono",
 "DTX25Win"  = "Dias Tmax > 25 C invierno",

 # --- Clima: Precipitacion ---
 "Bio12"     = "Precipitacion anual",
 "Bio13"     = "Precip. mes mas humedo",
 "Bio14"     = "Precip. mes mas seco",
 "Bio15"     = "Estacionalidad precip.",
 "Bio16"     = "Precip. trimestre humedo",
 "Bio17"     = "Precip. trimestre seco",
 "Bio18"     = "Precip. trimestre calido",
 "Bio19"     = "Precip. trimestre frio",
 "PSum"      = "Precipitacion verano",
 "DP01"      = "Dias precip. > 0.1 mm anual",
 "DP10Spr"   = "Dias precip. > 10 mm primavera",
 "DP10Sum"   = "Dias precip. > 10 mm verano",
 "DP1Spr"    = "Dias precip. > 1 mm primavera",
 "DP1Win"    = "Dias precip. > 1 mm invierno",
 "DP30Spr"   = "Dias precip. > 30 mm primavera",
 "DP30Sum"   = "Dias precip. > 30 mm verano",
 "DP30Win"   = "Dias precip. > 30 mm invierno",

 # --- Clima: Radiacion y otros ---
 "SIDSum"    = "Dias irradiancia solar verano",
 "Rad"       = "Radiacion solar",

 # --- Termino espacial ---
 "Lo2"       = "Longitud al cuadrado (espacial)",

 # --- Topografia ---
 "Alt"       = "Altitud",
 "Slope"     = "Pendiente",
 "CTI"       = "Indice topografico humedad (CTI)",
 "ETR_rec"   = "Exposicion topografica (ETR)",
 "WE_rec"    = "Exposicion oeste (WE)",
 "SE_rec"    = "Exposicion sur (SE)",
 "DAut_rec"  = "Exposicion otono (DAut)",

 # --- Urbanizacion y poblacion ---
 "Dens_pob_rec"  = "Densidad de poblacion",
 "U500_rec"      = "Urbanizacion buffer 500 m",
 "U100_rec"      = "Urbanizacion buffer 100 m",
 "Ciudad"        = "Superficie de ciudades",
 "Pueblo"        = "Superficie de pueblos",
 "Urbanizacion"  = "Superficie urbanizaciones",
 "Otros_urba"    = "Otros usos urbanos",
 "Carreteras"    = "Densidad de carreteras",
 "Area_degradadas" = "Areas degradadas",

 # --- Bosque (IFN): Abundancia (area basal) ---
 "Ene_sab"        = "Enebros y sabinas",
 "Pina_abe_ab"    = "Pinaceas/abietaceas (area basal)",
 "Haya_ab"        = "Hayedo (area basal)",
 "Cast_ab"        = "Castanar (area basal)",
 "Chopo_ab"       = "Chopera (area basal)",
 "Roble_ab"       = "Robledal (area basal)",
 "Fres_ab"        = "Fresneda (area basal)",
 "Enc_alq_ab"     = "Encinar/alcornocal (area basal)",
 "Planif_ab"      = "Planifolios (area basal)",
 "Plani_con_ab"   = "Planil. y coniferas (area basal)",

 # --- Bosque (IFN): Densidad ---
 "Pina_abe_dens"  = "Pinaceas/abietaceas (densidad)",
 "Haya_den"       = "Hayedo (densidad)",
 "Cast_den"       = "Castanar (densidad)",
 "Chopo_den"      = "Chopera (densidad)",
 "Fres_den"       = "Fresneda (densidad)",
 "Enc_alq_den"    = "Encinar/alcornocal (densidad)",
 "Planif_den"     = "Planifolios (densidad)",
 "Plani_con_den"  = "Planil. y coniferas (densidad)",

 # --- Bosque (IFN): Otros ---
 "Euca"           = "Eucaliptal",
 "Pal"            = "Palmeral",
 "Lauri_motver"   = "Laurisilva y monteverde",

 # --- Paisaje / CORINE ---
 "Riberas_arb"      = "Riberas arboladas",
 "Deforest"         = "Superficie deforestada",
 "Mat_ab"           = "Matorral (abundancia)",
 "Mat_den"          = "Matorral (densidad)",
 "Herb_ralos"       = "Herbazales ralos",
 "Herb_altos"       = "Herbazales altos",
 "Riberas_desarb"   = "Riberas desarboladas",
 "Masas_agua"       = "Masas de agua",
 "Cul_herb"         = "Cultivos herbaceos",
 "Cul_reg"          = "Cultivos de regadio",
 "Cult_inund"       = "Cultivos inundados (arrozales)",
 "Olivar"           = "Olivar",
 "Vid"              = "Vinedo",
 "Frutales"         = "Frutales",
 "Mosaico_agri"     = "Mosaico agricola",
 "otros_habitat"    = "Otros habitats",
 "Shannon"          = "Diversidad paisaje (Shannon)",

 # --- Variables agregadas ---
 "C_forest_total"   = "Cobertura forestal total",
 "C_forest_ab"      = "Cobertura forestal (area basal)",
 "C_agric_total"    = "Cobertura agricola total",
 "C_agric_arb"      = "Cobertura agricola arborea",
 "C_amb_acuat"      = "Ambientes acuaticos",

 # --- Geologia ---
 "Karst_principal"    = "Karst principal",
 "Karst_secundario"   = "Karst secundario",
 "Karst_total"        = "Karst total",
 "Lito_karsticas"     = "Litologias karsticas",
 "Lito_siliciclasticas" = "Litologias siliciclasticas",
 "Lito_igneas"        = "Litologias igneas",
 "Lito_metamorficas"  = "Litologias metamorficas",
 "Lito_otras"         = "Otras litologias",
 "Lito_dominancia"    = "Dominancia litologica",
 "Lito_n_tipos"       = "N. tipos litologicos",
 "Lito_PC1"           = "Litologia PC1",
 "Lito_PC2"           = "Litologia PC2",
 "Lito_PC3"           = "Litologia PC3",
 "Lito_PC4"           = "Litologia PC4",
 "Lito_PC5"           = "Litologia PC5",
 "Roquedos"           = "Roquedos",
 "Arenales"           = "Arenales"
)
