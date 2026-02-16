# ==============================================================================
# 01b_cargar_malla.R - Cargar mallas UTM 10x10 (Peninsula + Baleares)
# ==============================================================================
#
# RAZON CIENTIFICA:
# La cuadricula UTM 10x10 km es la resolucion estandar de los atlas de
# distribucion de fauna en Espana (MAGRAMA, SEO/BirdLife, SECEMU). Esta
# escala ofrece un equilibrio entre detalle espacial y completitud de muestreo:
# cuadriculas mas pequenas (1x1, 2x2) resultarian en exceso de ceros por
# submuestreo, mientras que cuadriculas mas grandes (50x50) difuminarian los
# patrones ecologicos relevantes para la gestion de murcielagos.
#
# NOTA SOBRE BALEARES:
# Las Islas Baleares se cartografian originalmente en la zona UTM 31N
# (EPSG:25831), mientras que la Peninsula Iberica y las mallas de referencia
# usan la zona UTM 30N (EPSG:25830). Para poder operar espacialmente con un
# unico CRS (joins, overlays, mapas), reproyectamos Baleares a zona 30.
# La distorsion introducida a esta latitud (~39 N) es negligible para
# cuadriculas de 10 km.
#
# NOTA SOBRE CANARIAS:
# Las cuadriculas con prefijo 28R corresponden a las Islas Canarias,
# pertenecientes a la region biogeografica Macaronesica. Se excluyen porque
# su fauna quiropterologica (e.g., Plecotus teneriffae, Pipistrellus
# maderensis) es muy diferente de la ibero-balear, y los modelos de
# distribucion de la Peninsula no son extrapolables a ese contexto insular
# oceanico.
#
# INPUT:  CONFIG$paths$shapefile_peninsula
#         CONFIG$paths$shapefile_baleares (optional)
# OUTPUT: CONFIG$paths$malla_peninsula
#         CONFIG$paths$malla_baleares
#         CONFIG$paths$malla_union
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

# --- Cargar configuracion y utilidades (idempotente) ---
if (!exists("CONFIG")) source("R/00_setup/00_config.R")
if (!exists("norm_id")) source("R/utils/utils_checkpoints.R")

suppressPackageStartupMessages({
  library(tidyverse)
  library(sf)
})

cat("\n=== 01b: CARGAR MALLA UTM 10x10 ===\n\n")

# --- Funcion auxiliar: detectar y normalizar la columna ID de cuadricula ---
# Los shapefiles de distintas fuentes (MAGRAMA, SEO, descargas GBIF) usan
# nombres de columna diferentes para el identificador UTM. Probamos varios
# candidatos en orden de frecuencia para ser robustos.
normalizar_columna_id <- function(sf_obj) {
  # Candidatos ordenados por frecuencia de aparicion en fuentes habituales

  candidatos <- c("CUADRICULA", "UTMCODE", "UTM_CODE", "utm_code",
                  "cuadricula", "QUADRICULA", "CELLCODE", "CODE",
                  "UTM10X10", "UTM10", "ID", "id")
  encontrada <- NULL
  for (cand in candidatos) {
    if (cand %in% names(sf_obj)) {
      encontrada <- cand
      break
    }
  }
  if (is.null(encontrada)) {
    stop(
      "No se encontro columna de ID de cuadricula. ",
      "Columnas disponibles: ", paste(names(sf_obj), collapse = ", "), "\n",
      "Candidatos probados: ", paste(candidatos, collapse = ", ")
    )
  }
  if (encontrada != "CUADRICULA") {
    cat(sprintf("  Renombrando columna '%s' -> 'CUADRICULA'\n", encontrada))
    sf_obj <- sf_obj %>% rename(CUADRICULA = !!sym(encontrada))
  }
  sf_obj$CUADRICULA <- norm_id(sf_obj$CUADRICULA)
  return(sf_obj)
}

# --- 1. Malla Peninsula (zona UTM 30) ---
cat("Cargando malla Peninsula...\n")
malla_pi <- st_read(CONFIG$paths$shapefile_peninsula, quiet = TRUE) %>%
  st_make_valid()

# Normalizar ID probando multiples candidatos de nombre de columna
malla_pi <- normalizar_columna_id(malla_pi)

# Filtrar Canarias (28R): region Macaronesica, no incluida en el atlas iberico
malla_pi <- malla_pi %>% filter(!str_detect(CUADRICULA, "^28R"))

cat(sprintf("  Malla Peninsula: %d cuadriculas | CRS: %s\n",
            nrow(malla_pi), st_crs(malla_pi)$input))

# --- 2. Malla Baleares (zona UTM 31) ---
# Las Baleares se distribuyen en un shapefile separado porque su zona UTM
# nativa (31N) difiere de la peninsular (30N). Al cargarla, la reproyectamos
# al CRS de la Peninsula para garantizar coherencia espacial en todos los
# analisis posteriores (joins con predictores, mapas, overlays).
if (file.exists(CONFIG$paths$shapefile_baleares)) {
  cat("Cargando malla Baleares...\n")
  malla_bal <- st_read(CONFIG$paths$shapefile_baleares, quiet = TRUE) %>%
    st_make_valid()

  # Normalizar ID (misma logica robusta que para Peninsula)
  malla_bal <- normalizar_columna_id(malla_bal)

  # Reproyectar al CRS de la Peninsula si difiere (tipicamente 31N -> 30N)
  if (st_crs(malla_bal) != st_crs(malla_pi)) {
    cat("  Reproyectando Baleares al CRS de Peninsula (zona 31 -> zona 30)...\n")
    malla_bal <- st_transform(malla_bal, st_crs(malla_pi))
  }

  cat(sprintf("  Malla Baleares: %d cuadriculas\n", nrow(malla_bal)))
} else {
  cat("  AVISO: Shapefile Baleares no encontrado, solo Peninsula\n")
  malla_bal <- NULL
}

# --- 3. Union ---
# Combinamos ambas mallas en una unica capa sf. Se alinean las columnas
# para evitar errores de bind_rows cuando los shapefiles tienen atributos
# diferentes, y se eliminan duplicados por CUADRICULA.
if (!is.null(malla_bal)) {
  cols_comunes <- intersect(names(malla_pi), names(malla_bal))
  malla_union <- bind_rows(
    malla_pi %>% select(all_of(cols_comunes)),
    malla_bal %>% select(all_of(cols_comunes))
  ) %>%
    distinct(CUADRICULA, .keep_all = TRUE)
} else {
  malla_union <- malla_pi
}

# Eliminar duplicados (por si acaso alguna cuadricula fronteriza aparece en ambos)
malla_union <- malla_union %>% distinct(CUADRICULA, .keep_all = TRUE)

cat(sprintf("\nMalla union: %d cuadriculas\n", nrow(malla_union)))

# Validacion: la malla debe tener >= 5000 cuadriculas (PI+BAL ~5500)
validar_n_cuadriculas(malla_union, min_rows = 5000,
                       context = "malla_union en 01b")
cat(sprintf("  Validacion de filas: %d cuadriculas (OK, >= 5000)\n", nrow(malla_union)))

# --- 4. Guardar ---
saveRDS(malla_pi, CONFIG$paths$malla_peninsula)
if (!is.null(malla_bal)) saveRDS(malla_bal, CONFIG$paths$malla_baleares)
saveRDS(malla_union, CONFIG$paths$malla_union)

cat("[OK] Mallas guardadas\n")
