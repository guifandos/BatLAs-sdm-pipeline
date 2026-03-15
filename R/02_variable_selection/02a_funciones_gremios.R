# ==============================================================================
# 02a_funciones_gremios.R - Sistema de gremios + prioridades
# ==============================================================================
#
# HIBRIDO: Lee gremios desde CSVs (2 ejes: refugio x alimentacion)
# + sistema de prioridades para seleccion de variables
#
# Prioridades:
#   4 = nucleo de gremio (variables esenciales para el gremio)
#   3 = climatica/base (siempre relevante)
#   2 = complementaria de gremio
#   1 = permitida (no prioritaria pero puede entrar)
#   0 = excluida a priori
#
# Sistema de clasificacion de variables:
#   - Vectores hardcoded con nombres REALES del Excel SEO (Variables_EC.xlsx,
#     Variables_BAL.xlsx) y de los CSVs de geologia (Karst, Litologia).
#   - detect_variable_type() con pattern matching regex como fallback para
#     clasificar variables nuevas o con nombres no previstos.
#   - annotate_variables_by_guild() usa PRIMERO los vectores, y LUEGO fallback
#     al pattern matching para variables no reconocidas.
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

if (!exists("CONFIG")) source("R/00_setup/00_config.R")

suppressPackageStartupMessages(library(tidyverse))

cat("=== CARGANDO SISTEMA DE GREMIOS ===\n\n")

# ==============================================================================
# CATEGORIAS DE VARIABLES (nombres reales del Excel SEO + geologia)
# ==============================================================================
# Estos vectores contienen nombres EXACTOS que existen en los datos:
#   - Variables_EC.xlsx / Variables_BAL.xlsx (152/150 columnas de la SEO)
#   - CSVs de geologia procesados por 01e (Karst_*, Lito_*)
# No se incluyen variables CORINE (CLC_*) porque los datos brutos de la SEO
# usan su propia nomenclatura de coberturas, no codigos CLC.
# Variables que no aparezcan aqui se clasifican por detect_variable_type().
# ==============================================================================

# --- Climaticas (base, siempre prioridad >= 3) ---
# Temperaturas medias y estacionales (T, TAut..TWin, TJan, TJul),
# temperaturas minimas/maximas (Tn*, Tx*),
# precipitaciones (P, PAut..PWin),
# dias con precipitacion umbral (DP01, DP1, DP10, DP30 + estacionales),
# dias con helada/calor (DTN0, DTN20, DTX25 + estacionales),
# radiacion solar (SID = duracion insolacion, SIS = intensidad radiacion).
clima_vars <- c(
  # Temperaturas medias (anual + estacionales)
  "T", "TAut", "TSpr", "TSum", "TWin", "TJan", "TJul",
  # Temperaturas minimas (anual + estacionales)
  "Tn", "TnAut", "TnJan", "TnJul", "TnSpr", "TnSum", "TnWin",
  # Temperaturas maximas (anual + estacionales)
  "Tx", "TxAut", "TxJan", "TxJul", "TxSpr", "TxSum", "TxWin",
  # Precipitaciones (anual + estacionales)
  "P", "PAut", "PSpr", "PSum", "PWin",
  # Dias con precipitacion >= umbral (anual + estacionales)
  "DP01", "DP01Aut", "DP01Spr", "DP01Sum", "DP01Win",
  "DP1", "DP1Aut", "DP1Spr", "DP1Sum", "DP1Win",
  "DP10", "DP10Aut", "DP10Spr", "DP10Sum", "DP10Win",
  "DP30", "DP30Aut", "DP30Spr", "DP30Sum", "DP30Win",
  # Dias con temperatura umbral (heladas, calor) (anual + estacionales)
  "DTN0", "DTN0Aut", "DTN0Spr", "DTN0Sum", "DTN0Win",
  "DTN20", "DTN20Aut",
  "DTX25", "DTX25Aut", "DTX25Spr", "DTX25Sum", "DTX25Win",
  # Radiacion solar: duracion de insolacion (anual + estacionales)
  "SID", "SIDAut", "SIDSpr", "SIDSum", "SIDWin",
  # Radiacion solar: intensidad (anual + estacionales)
  "SIS", "SISAut", "SISSpr", "SISSum", "SISWin",
  # Sequia otonal (duracion)
  "DAut_rec"
)

# --- Topograficas ---
# Variables del Excel SEO con sufijo _rec (reclasificadas) relacionadas con
# relieve, energia y balance hidrico.
topo_vars <- c(
  # Del Excel SEO (recodificadas)
  "Alt_rec",                # Altitud media
  "Slop_rec",               # Pendiente media
  "RA_rec",                 # Radiacion anual
  "ETP_rec",                # Evapotranspiracion potencial
  "ETR_rec",                # Evapotranspiracion real
  "WE_rec",                 # Water excess (excedente hidrico)
  "SE_rec",                 # Solar energy
  "CTI"                     # Compound Topographic Index (humedad topografica)
)

# --- Forestales ---
# Tipos de bosque del Excel SEO: abundancia (_ab) y densidad (_den/_dens)
# por especie arborea, mas indices forestales compuestos (C_forest_*).
forest_vars <- c(
  # Tipos de bosque: pinos
  "Pina_abe_ab", "Pina_abe_dens",
  # Hayas
  "Haya_ab", "Haya_den",
  # Castano
  "Cast_ab", "Cast_den",
  # Chopos
  "Chopo_ab", "Chopo_den",
  # Robles
  "Roble_ab", "Roble_den",
  # Fresnos
  "Fres_ab", "Fres_den",
  # Encinas y alcornoques
  "Enc_alq_ab", "Enc_alq_den",
  # Planifolia (caducifolio)
  "Planif_ab", "Planif_den",
  # Planifolia + coniferas
  "Plani_con_ab", "Plani_con_den",
  # Otros tipos
  "Euca",                   # Eucalipto
  "Pal",                    # Palmeras
  "Lauri_motver",           # Laurisilva y monteverde
  "Ene_sab",                # Enebros y sabinas
  # Indices forestales compuestos
  "C_forest_total",         # Cobertura forestal total
  "C_forest_den",           # Densidad forestal
  "C_forest_ab",            # Abundancia forestal
  "C_forest_conif",         # Cobertura coniferas
  "C_forest_cadu",          # Cobertura caducifolias
  "C_forest_enci",          # Cobertura encinar
  "C_forest_mixta"          # Cobertura bosque mixto
)

# --- Roquedo y geologia ---
# Roquedos del Excel SEO + variables derivadas de geologia (Karst, Litologia)
# procesadas por 01e_procesar_geologia.R
rock_vars <- c(
  # Del Excel SEO
  "Roquedos",               # Proporcion de roquedos
  "Arenales",               # Proporcion de arenales
  # Karst (de utils_geologia.R)
  "Karst_principal", "Karst_secundario", "Karst_total",
  # Litologia agrupada (de utils_geologia.R)
  "Lito_karsticas", "Lito_siliciclasticas", "Lito_igneas",
  "Lito_metamorficas", "Lito_otras",
  # Litologia derivada (de build_geo_features)
  "Lito_dominante", "Lito_dominancia", "Lito_diversidad", "Lito_n_tipos",
  # PCA litologico (de utils_pca_litologia.R)
  "Lito_PC1", "Lito_PC2", "Lito_PC3", "Lito_PC4", "Lito_PC5"
)

# --- Acuaticas ---
# Variables del Excel SEO relacionadas con masas de agua y riberas.
water_vars <- c(
  # Del Excel SEO
  "Masas_agua",             # Superficie de masas de agua
  "Riberas_arb",            # Riberas arboladas
  "Riberas_desarb",         # Riberas desarboladas
  "C_amb_acuat"             # Cobertura de ambientes acuaticos
)

# --- Urbanas/antropicas ---
# Variables del Excel SEO de presion antropica y nucleos urbanos.
urban_vars <- c(
  # Del Excel SEO
  "Ciudad",                 # Superficie de ciudades
  "Pueblo",                 # Superficie de pueblos
  "Urbanizacion",           # Superficie de urbanizaciones
  "Otros_urba",             # Otros usos urbanos
  "Carreteras",             # Densidad de carreteras
  "Area_degradadas",        # Areas degradadas
  "Dens_pob_rec",           # Densidad de poblacion (recodificada)
  "U500_rec",               # Proximidad a nucleos >500 hab
  "U100_rec",               # Proximidad a nucleos >100 hab
  "C_amb_urbani"            # Cobertura de ambientes urbanizados
)

# --- Paisaje/heterogeneidad ---
# Variables del Excel SEO de diversidad de paisaje, cultivos, matorral
# y pastizales. Incluye indices de diversidad (Shannon, Comple_veg).
landscape_vars <- c(
  # Indices de diversidad de paisaje
  "Shannon",                # Indice de Shannon de diversidad de coberturas
  "Comple_veg",             # Complejidad de la vegetacion
  # Matorral y herbaceas
  "Mat_ab", "Mat_den",      # Matorral (abundancia, densidad)
  "Herb_ralos",             # Herbaceas ralas
  "Herb_altos",             # Herbaceas altos
  # Cultivos
  "Cul_herb",               # Cultivos herbaceos
  "Cul_reg",                # Cultivos de regadio
  "Cult_inund",             # Cultivos inundados (arrozales)
  "Olivar",                 # Olivares
  "Vid",                    # Vinedos
  "Frutales",               # Frutales
  "Mosaico_agri",           # Mosaico agricola
  # Indices compuestos de cobertura
  "C_agric_total",          # Cobertura agricola total
  "C_agric_arb",            # Cobertura agricola arborea
  # Perturbacion / cambio
  "Deforest"                # Deforestacion
)

# ==============================================================================
# DETECCION DE TIPO DE VARIABLE POR PATTERN MATCHING
# ==============================================================================
#
# Fallback para clasificar variables que no aparecen en los vectores hardcoded.
# Util cuando:
#   1. Se anaden nuevas variables al Excel SEO entre versiones.
#   2. Los nombres varian ligeramente entre EC y BAL.
#   3. Se incorporan fuentes adicionales con nombres no previstos.
#
# Patrones basados en convenciones de nombrado del Excel SEO:
#   - Temperaturas: T, Tn*, Tx*, TAut, TJan, TJul...
#   - Precipitacion: P, PAut, PSpr..., DP01, DP1, DP10, DP30 + estacionales
#   - Dias umbral: DTN0, DTN20, DTX25 + estacionales
#   - Radiacion: SID*, SIS*
#   - Topografia: Alt_rec, Slop_rec, RA_rec, ETP_rec, ETR_rec, WE_rec, SE_rec, CTI
#   - Bosques: Pina*, Haya*, Cast*, Chopo*, Roble*, Fres*, Enc_alq*, Planif*,
#              Euca, Pal, Lauri*, C_forest_*
#   - Geologia: Karst_*, Lito_*, Roquedos, Arenales
#   - Agua: Masas_agua, Riberas*, C_amb_acuat
#   - Urbano: Ciudad, Pueblo, Urbaniz*, Carreteras, Dens_pob*, U500*, U100*
#   - Paisaje: Shannon, Comple_veg, Mat_*, Herb_*, Cul_*, Olivar, Vid...
# ==============================================================================

#' Detect variable type by pattern matching on the variable name
#'
#' @param varname Character scalar: name of the variable
#' @return Character scalar: one of "climatica", "topografica", "forestal",
#'   "geologica", "acuatica", "urbana", "paisaje", or "otra"
detect_variable_type <- function(varname) {
  # Orden de evaluacion: de mas especifico a mas generico para evitar
  # falsos positivos.

  # --- CLIMATICA ---
  # Temperaturas (T, Tn*, Tx* + estacionales), precipitaciones (P + estacionales),
  # dias con precipitacion/temperatura umbral (DP*, DTN*, DTX*),
  # radiacion solar (SID*, SIS*), sequia (DAut_rec)
  if (str_detect(varname, "^(T$|T[nxA-Z]|P$|PAut|PSpr|PSum|PWin|DP[013]|DTN|DTX|SID|SIS|DAut_rec)")) {
    return("climatica")
  }

  # --- TOPOGRAFICA ---
  # Altitud (Alt_rec), pendiente (Slop_rec), radiacion (RA_rec),
  # evapotranspiracion (ETP_rec, ETR_rec), excedente hidrico (WE_rec),
  # energia solar (SE_rec), indice topografico (CTI)
  if (str_detect(varname, "^(Alt_rec|Slop_rec|RA_rec|ETP_rec|ETR_rec|WE_rec|SE_rec|CTI$)")) {
    return("topografica")
  }

  # --- GEOLOGICA ---
  # Karst (Karst_*), litologia (Lito_*), roquedos y arenales del Excel SEO
  # Se evalua ANTES de forestal/paisaje para evitar falsos positivos
  if (str_detect(varname, "^(Karst|Lito_|Roquedos|Arenales)")) {
    return("geologica")
  }

  # --- FORESTAL ---
  # Tipos de bosque del Excel SEO (Pina*, Haya*, Cast*, Chopo*, Roble*,
  # Fres*, Enc_alq*, Planif*, Plani_con*, Euca, Pal, Lauri*),
  # indices forestales compuestos (C_forest_*), enebros/sabinas (Ene_sab)
  if (str_detect(varname, "^(Pina|Haya|Cast|Chopo|Roble|Fres|Enc_alq|Planif|Plani_con|Euca$|Pal$|Lauri|C_forest|Ene_sab)")) {
    return("forestal")
  }

  # --- ACUATICA ---
  # Masas de agua, riberas (arboladas/desarboladas), ambientes acuaticos
  if (str_detect(varname, "^(Masas_agua|Riberas|C_amb_acuat)")) {
    return("acuatica")
  }

  # --- URBANA ---
  # Nucleos urbanos (Ciudad, Pueblo, Urbanizacion), infraestructuras
  # (Carreteras, Area_degradadas), demografia (Dens_pob, U500, U100),
  # ambientes urbanizados (C_amb_urbani)
  if (str_detect(varname, "^(Ciudad|Pueblo|Urbaniz|Otros_urba|Carreteras|Area_degradadas|Dens_pob|U500|U100|C_amb_urbani)")) {
    return("urbana")
  }

  # --- PAISAJE ---
  # Diversidad (Shannon, Comple_veg), matorral (Mat_*), herbaceas (Herb_*),
  # cultivos (Cul_*, Cult_inund, Olivar, Vid, Frutales, Mosaico_agri),
  # cobertura agricola (C_agric_*), deforestacion, otros habitat
  if (str_detect(varname, "^(Shannon|Comple_veg|Mosaico_agri|Olivar|Vid$|Frutales|Cul_|Cult_inund|Herb_|Mat_|Deforest|C_agric|otros_habitat)")) {
    return("paisaje")
  }

  # --- NO CLASIFICADA ---
  return("otra")
}

# Version vectorizada para aplicar a multiples variables
detect_variable_types <- function(varnames) {
  vapply(varnames, detect_variable_type, character(1), USE.NAMES = FALSE)
}

# ==============================================================================
# FUNCIONES DE CARGA DESDE CSV
# ==============================================================================

cargar_gremios <- function() {
  gremios <- list()

  # Eje 1: Refugio
  # Clasifica cada especie segun el tipo de refugio que utiliza:
  # Cavernicola, Arboricola, Fisuricola, Generalista (v2 2026)
  # Cada categoria tiene una lista de variables_prioritarias en el CSV.
  gremios$refugio <- read_csv(CONFIG$paths$gremios_refugio, show_col_types = FALSE) %>%
    mutate(vars = str_split(variables_prioritarias, ",\\s*"))
  cat(sprintf("  Gremios refugio: %d categorias\n", nrow(gremios$refugio)))

  # Eje 2: Alimentacion
  # Clasifica cada especie segun su estrategia de forrajeo:
  # Forestal, Ripario, Generalista, Mosaico, Pastizal, Aereo, etc.
  # Cada categoria tiene variables_prioritarias que describen el habitat de caza.
  gremios$alimentacion <- read_csv(CONFIG$paths$gremios_alimentacion, show_col_types = FALSE) %>%
    mutate(vars = str_split(variables_prioritarias, ",\\s*"))
  cat(sprintf("  Gremios alimentacion: %d categorias\n", nrow(gremios$alimentacion)))

  # Especies con asignacion de gremios
  gremios$especies <- read_csv(CONFIG$paths$especies_gremios, show_col_types = FALSE)
  cat(sprintf("  Especies clasificadas: %d\n", nrow(gremios$especies)))

  # Complejos taxonomicos (especies cripticas modeladas conjuntamente)
  if (file.exists(CONFIG$paths$complejos_taxonomicos)) {
    gremios$complejos <- read_csv(CONFIG$paths$complejos_taxonomicos, show_col_types = FALSE)
    cat(sprintf("  Complejos taxonomicos: %d\n", nrow(gremios$complejos)))
  } else {
    gremios$complejos <- NULL
  }

  return(gremios)
}

obtener_variables_gremio <- function(especie, gremios) {
  sp_info <- gremios$especies %>% filter(especie == !!especie)
  if (nrow(sp_info) == 0) {
    warning(sprintf("Especie '%s' no encontrada en clasificacion", especie))
    return(character(0))
  }
  refugio <- sp_info$refugio
  alimentacion <- sp_info$alimentacion

  vars_ref <- gremios$refugio %>%
    filter(categoria == refugio) %>%
    pull(vars) %>% unlist()
  vars_alim <- gremios$alimentacion %>%
    filter(categoria == alimentacion) %>%
    pull(vars) %>% unlist()

  unique(c(vars_ref, vars_alim))
}

obtener_especies_modelizables <- function(gremios) {
  gremios$especies %>%
    filter(modelar == TRUE) %>%
    pull(especie)
}

obtener_especies_complejo <- function(nombre_complejo, gremios) {
  if (is.null(gremios$complejos)) return(character(0))
  comp <- gremios$complejos %>% filter(complejo == nombre_complejo)
  if (nrow(comp) == 0) return(character(0))
  str_split(comp$especies_incluidas, ",\\s*")[[1]]
}

# ==============================================================================
# SISTEMA DE PRIORIDADES POR GREMIO
# ==============================================================================
#
# Cada gremio de refugio/alimentacion tiene un conjunto de variables "nucleo"
# (prioridad 4) y "complementarias" (prioridad 2). Las variables climaticas
# siempre tienen prioridad 3 (base) independientemente del gremio.
#
# La logica ecologica detras de cada asignacion:
#
# EJE REFUGIO (donde duermen/hibernan):
#   - Cavernicola: depende de cavidades karsticas -> geologica es nucleo
#   - Arboricola: depende de bosques maduros -> forestal es nucleo
#   - Generalista: plastico en refugio -> paisaje + urbana es nucleo (reemplaza Antropofilo v2)
#   - Fisuricola: depende de fisuras en roca/edificios -> geologica + topografia es nucleo (absorbe Rupicola v2)
#
# EJE ALIMENTACION (donde cazan):
#   - Forestal: caza entre/sobre arboles -> forestal es nucleo
#   - Ripario: caza sobre rios/masas de agua -> acuatica es nucleo
#   - Generalista: caza en multiples habitats -> paisaje es nucleo
#   - Mosaico: caza en mosaicos agricolas -> paisaje es nucleo
#   - Pastizal: caza sobre pastizales -> paisaje es nucleo
#   - Aereo: caza en espacio abierto -> paisaje + acuatica es nucleo
# ==============================================================================

#' Determine if a variable name matches any category pattern
#' Helper to check membership using both hardcoded lists and pattern matching
#' @param varname Character: variable name
#' @param category Character: one of the detect_variable_type categories
#' @return Logical
is_variable_category <- function(varname, category) {
  detect_variable_type(varname) == category
}

#' Asignar prioridades segun gremio (eje refugio)
#'
#' Devuelve listas de variables "nucleo" y "complementaria" para cada
#' categoria de refugio. Se combinan los vectores hardcoded con los
#' patrones para maxima cobertura.
assign_priorities_refugio <- function(cat_refugio) {

  # Categorias validas de refugio (deben coincidir con gremios_refugio.csv)
  categorias_validas <- c("Cavernicola", "Arboricola", "Antropofilo",
                          "Fisuricola", "Rupicola")

  resultado <- switch(cat_refugio,

    # CAVERNICOLA: Rhinolophus spp., Miniopterus, Myotis myotis, M. blythii, etc.
    # Necesitan cavidades (cuevas, minas, tuneles) para colonias de cria e
    # hibernaculos. Las variables geologicas (karst, litologia karstica) son
    # las mas predictivas. Roquedos y la topografia complementan porque
    # las cuevas suelen estar en zonas montanosas con afloramientos.
    "Cavernicola" = list(
      nucleo = c(rock_vars),
      complementaria = c(forest_vars, topo_vars)
    ),

    # ARBORICOLA: Nyctalus spp., Barbastella barbastellus, Plecotus spp.
    # Utilizan huecos de arboles, corteza desprendida, cajas nido.
    # Dependen de bosques maduros con arboles viejos y muertos en pie.
    # C_forest_*, tipos de bosque (Roble, Haya, etc.) son los mejores proxies.
    # La topografia y el paisaje complementan (bosques de ladera, fragmentacion).
    "Arboricola" = list(
      nucleo = c(forest_vars),
      complementaria = c(topo_vars, landscape_vars)
    ),

    # GENERALISTA (refugio): Pipistrellus pipistrellus, P. pygmaeus, P. kuhlii,
    # Eptesicus serotinus, Plecotus austriacus, Myotis daubentonii, M. mystacinus.
    # Especies plasticas sin preferencia clara de refugio: usan fisuras, cuevas,
    # edificios y arboles indistintamente. NO se rescatan variables de refugio
    # especificas. Se priorizan climaticas y paisaje (heterogeneidad).
    # Sustituye a la antigua categoria "Antropofilo" (v2, consenso comite 2026).
    "Generalista" = list(
      nucleo = c(landscape_vars, urban_vars),
      complementaria = c(forest_vars, topo_vars)
    ),

    # FISURICOLA: Tadarida teniotis, Eptesicus isabellinus, Hypsugo savii,
    # Vespertilio murinus. Utilizan fisuras estrechas en paredes rocosas,
    # cantiles, puentes y construcciones. Absorbe la antigua categoria
    # "Rupicola" (v2, consenso comite 2026: Carlos Ibanez, JT Alcalde).
    "Fisuricola" = list(
      nucleo = c(rock_vars, topo_vars),
      complementaria = c(forest_vars, water_vars)
    ),

    # DEFAULT: categoria no reconocida -> FAIL FAST
    NULL
  )

  if (is.null(resultado)) {
    stop(sprintf(
      "Categoria de refugio desconocida: '%s'.\n  Categorias validas: %s.\n  Anadir la nueva categoria a assign_priorities_refugio() en 02a_funciones_gremios.R\n  y a gremios_refugio.csv.",
      cat_refugio, paste(categorias_validas, collapse = ", ")))
  }

  resultado
}

#' Asignar prioridades segun gremio (eje alimentacion)
#'
#' Devuelve listas de variables "nucleo" y "complementaria" para cada
#' estrategia de forrajeo.
assign_priorities_alimentacion <- function(cat_alim) {

  # Categorias validas de alimentacion (deben coincidir con gremios_alimentacion.csv)
  categorias_validas <- c("Forestal", "Ripario", "Generalista",
                          "Mosaico", "Pastizal", "Aereo")

  resultado <- switch(cat_alim,

    # FORESTAL: Rhinolophus hipposideros, Plecotus auritus, Barbastella.
    # Cazan insectos volando entre la vegetacion o recogiendo presas de las
    # hojas (gleaning). Dependen de la estructura del bosque: cobertura,
    # densidad, altura del dosel, tipo de bosque (caducifolio vs conifera).
    "Forestal" = list(
      nucleo = c(forest_vars),
      complementaria = c(landscape_vars)
    ),

    # RIPARIO: Myotis daubentonii, M. capaccinii.
    # Cazan insectos que emergen del agua o vuelan rasantes sobre rios,
    # embalses y balsas de riego. Masas_agua, Riberas_arb y C_amb_acuat
    # son las variables mas predictivas.
    "Ripario" = list(
      nucleo = c(water_vars),
      complementaria = c(forest_vars)
    ),

    # GENERALISTA: Pipistrellus pipistrellus, Eptesicus serotinus.
    # Cazan en multiples habitats: bordes de bosque, farolas, sobre agua,
    # jardines. La heterogeneidad del paisaje (Shannon, Comple_veg) y la
    # disponibilidad de multiples coberturas son las mejores predictoras.
    "Generalista" = list(
      nucleo = c(landscape_vars),
      complementaria = c(forest_vars, water_vars, urban_vars)
    ),

    # MOSAICO: Rhinolophus ferrumequinum, R. euryale.
    # Cazan en mosaicos agro-pastorales con setos, olivares y bosquetes
    # intercalados. Mosaico_agri, Olivar y cultivos del Excel SEO son clave.
    "Mosaico" = list(
      nucleo = c(landscape_vars),
      complementaria = c(forest_vars)
    ),

    # PASTIZAL: Myotis myotis, M. blythii.
    # Cazan escarabajos y grillos posados en el suelo de pastizales abiertos
    # y dehesas. Herb_ralos, Herb_altos y Mosaico_agri son las variables
    # principales; la topografia complementa (terrenos llanos/ondulados).
    "Pastizal" = list(
      nucleo = c(landscape_vars),
      complementaria = c(topo_vars)
    ),

    # AEREO: Tadarida teniotis, Nyctalus lasiopterus, N. noctula.
    # Cazan insectos grandes (polillas, escarabajos voladores) en vuelo alto
    # y rapido sobre espacios abiertos. La heterogeneidad del paisaje y la
    # presencia de masas de agua (que concentran insectos) son importantes.
    "Aereo" = list(
      nucleo = c(landscape_vars, water_vars),
      complementaria = c(forest_vars, urban_vars)
    ),

    # DEFAULT: categoria no reconocida -> FAIL FAST
    NULL
  )

  if (is.null(resultado)) {
    stop(sprintf(
      "Categoria de alimentacion desconocida: '%s'.\n  Categorias validas: %s.\n  Anadir la nueva categoria a assign_priorities_alimentacion() en 02a_funciones_gremios.R\n  y a gremios_alimentacion.csv.",
      cat_alim, paste(categorias_validas, collapse = ", ")))
  }

  resultado
}

# ==============================================================================
# ANOTACION DE VARIABLES CON PRIORIDADES
# ==============================================================================

#' Anotar variables con prioridades segun gremio de la especie
#'
#' Para cada variable disponible en el PAxENV, asigna:
#' - tipo_base: categoria ecologica (climatica, topografica, forestal, etc.)
#' - prioridad: 4 (nucleo), 3 (climatica), 2 (complementaria), 1 (otra)
#' - peso: peso numerico proporcional a la prioridad
#'
#' La clasificacion usa un sistema de dos capas:
#' 1. Primero: busqueda exacta en los vectores hardcoded (clima_vars, etc.)
#' 2. Fallback: pattern matching via detect_variable_type()
#'
#' Esto garantiza que TODAS las variables se clasifiquen, incluso las que
#' tienen nombres no previstos en los vectores.
#'
#' @param especie Nombre de la especie
#' @param varnames Vector de nombres de variables disponibles
#' @param especies_gremios Tabla con columnas: especie, refugio, alimentacion
#' @return Tibble con: variable, prioridad, peso, tipo_base, es_climatica, es_gremio
annotate_variables_by_guild <- function(especie, varnames, especies_gremios) {

  sp_info <- especies_gremios %>% filter(especie == !!especie)

  if (nrow(sp_info) == 0) {
    warning(sprintf("Especie '%s' no encontrada", especie))
    # Sin informacion de gremio: clasificar por tipo pero sin prioridades de gremio
    tipos <- detect_variable_types(varnames)
    es_clima <- tipos == "climatica"
    return(tibble(
      variable = varnames,
      tipo_base = tipos,
      es_climatica = es_clima,
      es_gremio = FALSE,
      es_nucleo = FALSE,
      es_complementaria = FALSE,
      prioridad = ifelse(es_clima, 3L, 1L),
      peso = ifelse(es_clima, 3.0, 1.0)
    ))
  }

  cat_refugio <- sp_info$refugio[1]
  cat_alim <- sp_info$alimentacion[1]

  # Obtener prioridades de ambos ejes
  prio_ref <- assign_priorities_refugio(cat_refugio)
  prio_alim <- assign_priorities_alimentacion(cat_alim)

  # Combinar: nucleo y complementaria de ambos ejes
  nucleo_all <- unique(c(prio_ref$nucleo, prio_alim$nucleo))
  compl_all <- unique(c(prio_ref$complementaria, prio_alim$complementaria))

  # Determinar los tipos que son nucleo/complementarios para este gremio
  # (para el fallback por pattern matching)
  # Ejemplo: si un Cavernicola tiene rock_vars en nucleo, cualquier variable
  # detectada como "geologica" tambien deberia ser nucleo.
  nucleo_types <- unique(c(
    if (any(rock_vars %in% nucleo_all)) "geologica",
    if (any(forest_vars %in% nucleo_all)) "forestal",
    if (any(water_vars %in% nucleo_all)) "acuatica",
    if (any(urban_vars %in% nucleo_all)) "urbana",
    if (any(topo_vars %in% nucleo_all)) "topografica",
    if (any(landscape_vars %in% nucleo_all)) "paisaje"
  ))

  compl_types <- unique(c(
    if (any(rock_vars %in% compl_all)) "geologica",
    if (any(forest_vars %in% compl_all)) "forestal",
    if (any(water_vars %in% compl_all)) "acuatica",
    if (any(urban_vars %in% compl_all)) "urbana",
    if (any(topo_vars %in% compl_all)) "topografica",
    if (any(landscape_vars %in% compl_all)) "paisaje"
  ))

  # Asignar prioridades a cada variable
  resultado <- tibble(variable = varnames) %>%
    mutate(
      # Capa 1: Busqueda exacta en vectores hardcoded
      in_clima = variable %in% clima_vars,
      in_topo = variable %in% topo_vars,
      in_forest = variable %in% forest_vars,
      in_rock = variable %in% rock_vars,
      in_water = variable %in% water_vars,
      in_urban = variable %in% urban_vars,
      in_landscape = variable %in% landscape_vars,

      # Tipo base: primero por vectores hardcoded, luego fallback a pattern matching
      tipo_hardcoded = case_when(
        in_clima ~ "climatica",
        in_topo ~ "topografica",
        in_forest ~ "forestal",
        in_rock ~ "geologica",
        in_water ~ "acuatica",
        in_urban ~ "urbana",
        in_landscape ~ "paisaje",
        TRUE ~ NA_character_
      ),
      # Capa 2: Pattern matching para variables no reconocidas en vectores
      tipo_pattern = detect_variable_types(variable),
      # Tipo final: hardcoded tiene prioridad, pattern matching como fallback
      tipo_base = ifelse(!is.na(tipo_hardcoded), tipo_hardcoded, tipo_pattern),

      # Clasificacion climatica (siempre prioridad base)
      es_climatica = tipo_base == "climatica",

      # Pertenencia a nucleo/complementaria:
      # Capa 1: esta en los vectores directos?
      in_nucleo_exact = variable %in% nucleo_all,
      in_compl_exact = variable %in% compl_all,
      # Capa 2: su tipo (por pattern) coincide con una categoria de nucleo/compl?
      in_nucleo_type = tipo_base %in% nucleo_types,
      in_compl_type = tipo_base %in% compl_types,

      # Resultado final: nucleo si coincide por vector O por tipo
      es_nucleo = in_nucleo_exact | in_nucleo_type,
      es_complementaria = (in_compl_exact | in_compl_type) & !es_nucleo,
      es_gremio = es_nucleo | es_complementaria,

      # Asignar prioridad
      # 4 = nucleo de gremio (variables esenciales para el gremio)
      # 3 = climatica base (siempre relevante para modelado de distribucion)
      # 2 = complementaria (utiles pero no esenciales)
      # 1 = permitida (puede entrar en el modelo si aporta informacion)
      prioridad = case_when(
        es_nucleo ~ 4L,
        es_climatica ~ 3L,
        es_complementaria ~ 2L,
        TRUE ~ 1L
      ),

      # Peso para seleccion ponderada (select07)
      # Valores mas altos = mayor probabilidad de retencion en la seleccion
      peso = case_when(
        prioridad == 4L ~ 4.0,
        prioridad == 3L ~ 3.0,
        prioridad == 2L ~ 2.0,
        prioridad == 1L ~ 1.0,
        TRUE ~ 0.0
      )
    ) %>%
    # Limpiar columnas auxiliares
    select(variable, prioridad, peso, tipo_base, es_climatica, es_gremio,
           es_nucleo, es_complementaria)

  return(resultado)
}

# ==============================================================================
# RESUMEN
# ==============================================================================

#' Resumen del pool de variables anotadas
summarize_variable_pool <- function(var_info) {
  cat("\n--- Resumen del pool de variables ---\n")
  cat(sprintf("  Total: %d variables\n", nrow(var_info)))
  cat(sprintf("  Nucleo (p=4): %d\n", sum(var_info$prioridad == 4)))
  cat(sprintf("  Climaticas (p=3): %d\n", sum(var_info$prioridad == 3)))
  cat(sprintf("  Complementarias (p=2): %d\n", sum(var_info$prioridad == 2)))
  cat(sprintf("  Permitidas (p=1): %d\n", sum(var_info$prioridad == 1)))
  cat(sprintf("  Excluidas (p=0): %d\n", sum(var_info$prioridad == 0)))

  # Desglose por tipo
  cat("\n  Desglose por tipo:\n")
  type_counts <- var_info %>%
    count(tipo_base, sort = TRUE)
  for (i in seq_len(nrow(type_counts))) {
    cat(sprintf("    %-15s %d variables\n", type_counts$tipo_base[i], type_counts$n[i]))
  }
  cat("\n")
}

message("[OK] Sistema de gremios cargado desde CSV + prioridades (con pattern matching)")
