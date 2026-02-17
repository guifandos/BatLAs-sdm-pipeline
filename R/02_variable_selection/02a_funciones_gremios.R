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
#   - Se mantienen vectores hardcoded con nombres CONOCIDOS (CLC_, Karst_, Lito_,
#     y nombres comunes del Excel SEO).
#   - Se anade detect_variable_type() con pattern matching regex para clasificar
#     CUALQUIER nombre de variable, incluyendo los que no estan en los vectores.
#   - annotate_variables_by_guild() usa PRIMERO los vectores, y LUEGO fallback
#     al pattern matching para variables no reconocidas.
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

if (!exists("CONFIG")) source("R/00_setup/00_config.R")

suppressPackageStartupMessages(library(tidyverse))

cat("=== CARGANDO SISTEMA DE GREMIOS ===\n\n")

# ==============================================================================
# CATEGORIAS DE VARIABLES (referencia con nombres conocidos)
# ==============================================================================
# Estos vectores contienen nombres REALES que sabemos que existen en nuestros
# datos (del Excel SEO, CORINE, geologia). Sirven como primera capa de
# clasificacion. Variables que no aparezcan aqui seran clasificadas por
# detect_variable_type() usando pattern matching.
# ==============================================================================

# --- Climaticas (base, siempre prioridad >= 3) ---
# Incluye: bioclimaticas (bio1-bio19 del WorldClim), temperaturas estacionales
# del Excel SEO (T, TAut, TSpr, TSum, TWin, TJan, TJul, Tn, Tx),
# precipitaciones estacionales (P, PAut, PSpr, PSum, PWin),
# dias con precipitacion (DP01, DP1, DP10, DP30),
# dias con helada/calor (DTN0, DTN20, DTX25),
# y otros indices climaticos.
clima_vars <- c(
  # WorldClim bioclimaticas
  "bio1", "bio2", "bio3", "bio4", "bio5", "bio6", "bio7",
  "bio8", "bio9", "bio10", "bio11", "bio12", "bio13", "bio14",
  "bio15", "bio16", "bio17", "bio18", "bio19",
  # Temperaturas del Excel SEO
  "T", "TAut", "TSpr", "TSum", "TWin", "TJan", "TJul", "Tn", "Tx",
  # Precipitaciones del Excel SEO
  "P", "PAut", "PSpr", "PSum", "PWin",
  # Dias con precipitacion umbral
  "DP01", "DP1", "DP10", "DP30",
  # Dias con temperatura umbral (heladas, calor)
  "DTN0", "DTN20", "DTX25",
  # Indices climaticos genericos
  "temp_media", "prec_anual", "aridez", "PET", "ETP",
  "deficit_hidrico", "continentalidad"
)

# --- Topograficas ---
# Incluye variables de relieve del Excel SEO (Alt_rec, Slop_rec)
# y variables derivadas del MDT (pendiente, orientacion, rugosidad, etc.)
topo_vars <- c(
  # Del Excel SEO
  "Alt_rec", "Slop_rec",
  # Variables topograficas genericas/derivadas del MDT
  "altitud", "altitud_media", "altitud_sd", "pendiente",
  "pendiente_media", "orientacion", "rugosidad", "TRI", "TWI",
  "curvatura", "dist_costa",
  # Variables SRTM o radiacion
  "SRTM", "RA_anual", "WE_anual", "SE_anual"
)

# --- Forestales ---
# CLC_bosques viene de utils_corine.R. Las demas son variables de
# estructura forestal que pueden venir del Excel o fuentes adicionales.
# Incluye nombres que aparecian en versiones previas del PAxENV.
forest_vars <- c(
  # CORINE
  "CLC_bosques",
  # Indices de vegetacion
  "NDVI", "NDVI_medio", "NDVI_max",
  # Estructura forestal
  "cobertura_arborea", "densidad_arbolado", "altura_arbolado",
  "biomasa_forestal", "diversidad_forestal", "fcc", "vol_madera",
  # Tipos de bosque (si existen como columnas individuales)
  "Pina", "Haya", "Cast", "Chopo", "Roble", "Fres",
  "Enc_", "Planif", "Euca", "Pal", "Lauri",
  "C_forest", "biomas"
)

# --- Roquedo y geologia ---
# Variables de utils_geologia.R (Karst_, Lito_) y utils_pca_litologia.R (Lito_PC).
# CLC_rupicola viene de utils_corine.R (roquedos y cantiles).
rock_vars <- c(
  # CORINE: roquedos
  "CLC_rupicola",
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
# CLC_acuatico viene de utils_corine.R. Las demas pueden venir del Excel SEO
# o de fuentes hidrograficas adicionales.
water_vars <- c(
  # CORINE
  "CLC_acuatico",
  # Del Excel SEO o fuentes hidrograficas
  "dist_rio", "dist_rios", "dist_agua", "densidad_rios", "densid_rios",
  "longitud_rios", "orden_strahler", "caudal_medio", "caudal",
  "humedales_pct", "humedal",
  # Nombres posibles del Excel

  "Masas_agua", "Riberas", "LamArt", "AguEst"
)

# --- Urbanas/antropicas ---
# CLC_urbano viene de utils_corine.R. Las demas son variables de presion
# antropica que pueden venir del Excel o fuentes adicionales.
urban_vars <- c(
  # CORINE
  "CLC_urbano",
  # Del Excel SEO o fuentes de presion antropica
  "Ciudad", "Pueblo", "Urbaniz", "Otros_urba", "Carreteras",
  "dist_nucleos", "dist_nucleo", "densidad_poblacion", "densid_pobl",
  "luz_nocturna", "luz_noct", "dist_carreteras", "infraestructuras",
  "human_footprint", "Area_degrad"
)

# --- Paisaje/heterogeneidad ---
# Variables de estructura y diversidad del paisaje. CLC_mosaico, CLC_pastizal,
# CLC_cultivo_lenoso, CLC_cultivo_intensivo, CLC_perturbacion_costera vienen
# de utils_corine.R. Shannon y Comple_veg pueden venir del Excel SEO.
landscape_vars <- c(
  # CORINE
  "CLC_mosaico", "CLC_pastizal", "CLC_cultivo_lenoso",
  "CLC_cultivo_intensivo", "CLC_perturbacion_costera",
  # Del Excel SEO
  "Shannon", "Comple_veg",
  # Variables de paisaje genericas
  "diversidad_shannon", "n_parches", "edge_density", "fragmentacion",
  "Mosaico_agri", "Olivar", "Vid", "Frutales",
  # Cultivos y vegetacion abierta
  "Herb_", "Mat_", "Ene_sab", "Deforest"
)

# ==============================================================================
# DETECCION DE TIPO DE VARIABLE POR PATTERN MATCHING
# ==============================================================================
#
# Esta funcion clasifica CUALQUIER nombre de variable usando expresiones
# regulares. Es el fallback cuando una variable no aparece en los vectores
# hardcoded. Esto es necesario porque:
#
# 1. Los nombres del Excel SEO pueden variar entre versiones (Variables_EC.xlsx
#    vs Variables_BAL.xlsx).
# 2. Nuevas variables pueden anadirse al pipeline sin tener que actualizar
#    manualmente los vectores.
# 3. Algunas variables tienen prefijos predecibles (CLC_, Karst_, Lito_, bio)
#    que permiten clasificacion automatica fiable.
#
# Las reglas de pattern matching reflejan convenciones de nombrado en:
#   - WorldClim (bio1-bio19)
#   - Excel SEO (T, P, DP, DTN, DTX, Alt_rec, Slop_rec, Shannon, etc.)
#   - CORINE derivado (CLC_*)
#   - Geologia derivada (Karst_*, Lito_*)
#   - Variables topograficas comunes (SRTM, TRI, TWI, etc.)
# ==============================================================================

#' Detect variable type by pattern matching on the variable name
#'
#' @param varname Character scalar: name of the variable
#' @return Character scalar: one of "climatica", "topografica", "forestal",
#'   "geologica", "acuatica", "urbana", "paisaje", or "otra"
detect_variable_type <- function(varname) {
  # Orden de evaluacion: de mas especifico a mas generico para evitar

  # falsos positivos. Por ejemplo, "Lito_" debe evaluarse antes que patrones
  # mas amplios.

  # --- CLIMATICA ---
  # bio1-bio19 (WorldClim), temperaturas (T, Tx, Tn, TJan, TJul, TAut...),
  # precipitaciones (P, PAut, PSpr...), dias umbral (DP01, DTN0, DTX25),
  # indices climaticos (PET, ETP, aridez, deficit, continentalidad)
  if (str_detect(varname, "^(bio|Bio|BIO|T$|Tx|Tn|P$|PAut|PSpr|PSum|PWin|TAut|TSpr|TSum|TWin|TJan|TJul|DP|DTN|DTX|temp|prec|arid|PET|ETP|deficit|continental)")) {
    return("climatica")
  }


  # --- TOPOGRAFICA ---
  # Altitud (Alt, SRTM), pendiente (Slop, slope, pend), orientacion,
  # rugosidad (TRI, rugos), indice topografico de humedad (TWI),
  # curvatura, radiacion (RA_, WE_, SE_), distancia a costa
  if (str_detect(varname, "^(Alt|Slop|slope|alt|SRTM|RA_|WE_|SE_|pend|orient|rugos|TRI|TWI|curv|dist_costa)")) {
    return("topografica")
  }

  # --- GEOLOGICA ---
  # Karst (Karst_*), litologia (Lito_*), roquedos CORINE (CLC_rupicola)
  # Se evalua ANTES de forestal/paisaje porque CLC_rupicola podria confundirse
  if (str_detect(varname, "^(Karst|Lito_|K_|L_|CLC_rupicola|Roquedos)")) {
    return("geologica")
  }

  # --- FORESTAL ---
  # Bosques CORINE (CLC_bosques), NDVI, tipos de bosque (Pina, Haya, etc.),
  # estructura forestal (fcc, cobert, densid, altur, biomas, vol_madera)
  if (str_detect(varname, "^(CLC_bosques|NDVI|forest|bosque|Pina|Haya|Cast|Chopo|Roble|Fres|Enc_|Planif|Euca|Pal|Lauri|C_forest|fcc|vol_madera|cobert|densid_arb|altur|biomas|diversid_forest)")) {
    return("forestal")
  }

  # --- ACUATICA ---
  # Masas de agua CORINE (CLC_acuatico), distancia a rios/agua, densidad rios,
  # caudal, humedales, laminas artificiales (LamArt), aguas estancadas (AguEst)
  if (str_detect(varname, "^(CLC_acuatico|dist_rio|dist_agua|densid_rio|longitud_rio|orden_str|caudal|humedal|Masas_agua|Riberas|LamArt|AguEst|water)")) {
    return("acuatica")
  }

  # --- URBANA ---
  # Urbano CORINE (CLC_urbano), nucleos urbanos (Ciudad, Pueblo, Urbaniz),
  # carreteras, densidad poblacion, luz nocturna, huella humana
  if (str_detect(varname, "^(CLC_urbano|Ciudad|Pueblo|Urbaniz|Otros_urba|Carreteras|dist_nucleo|densid_pobl|luz_noct|infraestr|human_foot|Area_degrad)")) {
    return("urbana")
  }

  # --- PAISAJE ---
  # CORINE de paisaje (CLC_mosaico, CLC_pastizal, CLC_cultivo, CLC_perturbacion),
  # indices de diversidad de paisaje (Shannon, Comple_veg), cultivos (Olivar, Vid),
  # metricas de paisaje (n_parches, edge_dens, fragment)
  if (str_detect(varname, "^(CLC_mosaico|CLC_pastizal|CLC_cultivo|CLC_perturbacion|Shannon|Comple_veg|Mosaico_agri|Olivar|Vid|Frutales|Cul_|n_parches|edge_dens|fragment|diversid_shannon|Herb_|Mat_|Ene_sab|Deforest)")) {
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
  # Cavernicola, Arboricola, Antropofilo, Fisuricola, Rupicola, etc.
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
#   - Antropofilo: depende de edificaciones -> urbana es nucleo
#   - Fisuricola: depende de fisuras en roca -> geologica + topografia es nucleo
#   - Rupicola: depende de cantiles rocosos -> geologica + topografia es nucleo
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
    # las mas predictivas. CLC_rupicola y la topografia complementan porque
    # las cuevas suelen estar en zonas montanosas con afloramientos.
    "Cavernicola" = list(
      nucleo = c(rock_vars),
      complementaria = c(forest_vars, topo_vars)
    ),

    # ARBORICOLA: Nyctalus spp., Barbastella barbastellus, Plecotus spp.
    # Utilizan huecos de arboles, corteza desprendida, cajas nido.
    # Dependen de bosques maduros con arboles viejos y muertos en pie.
    # CLC_bosques y NDVI son los mejores proxies de disponibilidad de refugios.
    # La topografia y el paisaje complementan (bosques de ladera, fragmentacion).
    "Arboricola" = list(
      nucleo = c(forest_vars),
      complementaria = c(topo_vars, landscape_vars)
    ),

    # ANTROPOFILO: Pipistrellus pipistrellus, P. pygmaeus, Eptesicus serotinus,
    # Tadarida teniotis (en edificios). Utilizan construcciones humanas
    # (desvanes, juntas de dilatacion, puentes). Las variables urbanas y de
    # densidad de poblacion predicen la disponibilidad de edificios.
    "Antropofilo" = list(
      nucleo = c(urban_vars),
      complementaria = c(forest_vars, landscape_vars)
    ),

    # FISURICOLA: Tadarida teniotis (en roca), Pipistrellus kuhlii, Hypsugo savii.
    # Utilizan fisuras estrechas en paredes rocosas, cantiles, puentes.
    # Necesitan afloramientos rocosos (CLC_rupicola) con fisuras, tipicamente
    # en zonas de pendiente elevada y rugosidad alta (TRI).
    "Fisuricola" = list(
      nucleo = c(rock_vars, topo_vars),
      complementaria = c(forest_vars)
    ),

    # RUPICOLA: Myotis capaccinii (en cuevas/puentes sobre agua),
    # algunas poblaciones de Rhinolophus en grietas de cantiles.
    # Similar a fisuricola pero con mayor dependencia de cantiles rocosos
    # verticales. La pendiente y rugosidad son criticas.
    "Rupicola" = list(
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
    # embalses y balsas de riego. La distancia a masas de agua, la densidad
    # de la red fluvial y CLC_acuatico son las variables mas predictivas.
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
    # intercalados. Los mosaicos CORINE y cultivos lenosos son clave.
    "Mosaico" = list(
      nucleo = c(landscape_vars),
      complementaria = c(forest_vars)
    ),

    # PASTIZAL: Myotis myotis, M. blythii.
    # Cazan escarabajos y grillos posados en el suelo de pastizales abiertos
    # y dehesas. CLC_pastizal es la variable principal; la topografia
    # complementa (prefieren terrenos llanos o suavemente ondulados).
    "Pastizal" = list(
      nucleo = c("CLC_pastizal", landscape_vars),
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
