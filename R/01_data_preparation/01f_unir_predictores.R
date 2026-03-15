# ==============================================================================
# 01f_unir_predictores.R - Unir predictores SEO + GEO y escalar
# ==============================================================================
#
# INPUT:  CONFIG$paths$predictores_seo (lista from 01c/01d)
#         CONFIG$paths$geo_features (from 01e)
# OUTPUT: CONFIG$paths$predictores_seo_geo
#         CONFIG$paths$predictores_seo_geo_sf
#
# ESCALADO (z-score) - Por que se hace aqui y no antes:
#   scale(x) = (x - mean(x)) / sd(x)
#   Si Peninsula y Baleares se escalaran por separado, cada region usaria
#   su propia media y SD, produciendo valores z-score NO comparables.
#   Al escalar DESPUES de unir, todas las cuadriculas comparten los mismos
#   estadisticos de referencia → los z-scores son coherentes entre regiones.
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

if (!exists("CONFIG")) source("R/00_setup/00_config.R")
source("R/utils/utils_checkpoints.R")

suppressPackageStartupMessages({
  library(tidyverse)
  library(sf)
})

cat("\n=== 01f: UNIR PREDICTORES SEO + GEO ===\n\n")

# --- 1. Cargar ---
predictores <- readRDS(CONFIG$paths$predictores_seo)
geo_features <- readRDS(CONFIG$paths$geo_features)

malla_union <- predictores$malla_union
ec <- predictores$ec
bal <- predictores$bal

cat(sprintf("Predictores SEO (EC): %d cuadriculas x %d vars\n", nrow(ec), ncol(ec) - 1))
if (!is.null(bal)) {
  cat(sprintf("Predictores SEO (BAL): %d cuadriculas x %d vars\n", nrow(bal), ncol(bal) - 1))
}
cat(sprintf("Geo features: %d cuadriculas x %d vars\n", nrow(geo_features), ncol(geo_features) - 1))

# --- 2. Unir EC con geo_features ---
# Normalizar IDs y RENOMBRAR columna a CUADRICULA (crucial para el join)
geo_features <- std_ids_tbl(geo_features, canonical = "CUADRICULA")

# Validar que ambas tablas comparten la clave de join
stopifnot(
  "EC no tiene columna CUADRICULA" = "CUADRICULA" %in% names(ec),
  "geo_features no tiene columna CUADRICULA" = "CUADRICULA" %in% names(geo_features)
)

# Diagnostico: cuantos IDs coinciden?
n_match <- length(intersect(ec$CUADRICULA, geo_features$CUADRICULA))
cat(sprintf("\nDiagnostico join: %d IDs EC, %d IDs GEO, %d en comun\n",
            n_distinct(ec$CUADRICULA), n_distinct(geo_features$CUADRICULA), n_match))
if (n_match == 0) {
  # Mostrar ejemplos para depuracion
  cat(sprintf("  CRITICO: 0 IDs en comun!\n"))
  cat(sprintf("  Ejemplo IDs EC: %s\n", paste(head(ec$CUADRICULA, 5), collapse = ", ")))
  cat(sprintf("  Ejemplo IDs GEO: %s\n", paste(head(geo_features$CUADRICULA, 5), collapse = ", ")))
  stop("Join EC+GEO fallaria: 0 IDs en comun. Revisar normalizacion de columnas de ID.")
}

cat("Uniendo EC + GEO...\n")
n_ec_pre <- nrow(ec)
ec_geo <- ec %>%
  left_join(geo_features, by = "CUADRICULA", suffix = c("", "_geo"))

# O8: Validacion post-join
stopifnot(
  "Join EC+GEO perdio filas" = nrow(ec_geo) == n_ec_pre
)
n_nuevas_na <- sum(is.na(ec_geo[[names(geo_features)[2]]]))
if (n_nuevas_na > 0) {
  cat(sprintf("  AVISO: %d cuadriculas sin datos geologicos (%.1f%%)\n",
              n_nuevas_na, 100 * n_nuevas_na / nrow(ec_geo)))
}

# Eliminar columnas duplicadas
dup_cols <- names(ec_geo)[duplicated(names(ec_geo))]
if (length(dup_cols) > 0) {
  cat(sprintf("  Eliminando %d columnas duplicadas\n", length(dup_cols)))
  ec_geo <- ec_geo[, !duplicated(names(ec_geo))]
}

# --- 3. Integrar Baleares si existe ---
if (!is.null(bal)) {
  cat("Integrando Baleares...\n")
  # Alinear columnas: bal puede no tener variables geo
  # Usar NA del tipo correcto para evitar errores en bind_rows
  cols_faltantes_bal <- setdiff(names(ec_geo), names(bal))
  for (col in cols_faltantes_bal) {
    if (col != "CUADRICULA") {
      if (is.character(ec_geo[[col]])) {
        bal[[col]] <- NA_character_
      } else {
        bal[[col]] <- NA_real_
      }
    }
  }
  # Seleccionar solo columnas que existen en ec_geo
  bal_aligned <- bal %>% select(any_of(names(ec_geo)))

  predictores_union <- bind_rows(ec_geo, bal_aligned) %>%
    distinct(CUADRICULA, .keep_all = TRUE)
  cat(sprintf("  Union EC+BAL: %d cuadriculas\n", nrow(predictores_union)))
} else {
  predictores_union <- ec_geo
}

cat(sprintf("\nPredictores unidos (antes de escalar): %d cuadriculas x %d variables\n",
            nrow(predictores_union), ncol(predictores_union) - 1))

# --- 4. Escalar variables numericas (z-score) sobre el conjunto unido ---
#
# Columnas excluidas del escalado:
#   - CUADRICULA : identificador de cuadricula (character)
#   - La, Lo, La2, Lo2, LaLo : coordenadas geograficas, deben conservar
#     sus valores originales para interacciones espaciales
#   - Cualquier columna character/factor se omite automaticamente
#
# Matematicamente: z_i = (x_i - mean_union) / sd_union
# donde mean_union y sd_union se calculan sobre TODAS las cuadriculas
# (Peninsula + Baleares).  Si sd_union == 0 (variable constante),
# scale() produce NaN, que reemplazamos por 0.

cols_no_escalar <- c("CUADRICULA", "La", "Lo", "La2", "Lo2", "LaLo")

cat("\nEscalando variables numericas sobre el conjunto unido...\n")

cols_a_escalar <- names(predictores_union) %>%
  setdiff(cols_no_escalar) %>%
  .[sapply(., function(cn) is.numeric(predictores_union[[cn]]))]

cat(sprintf("  Variables a escalar: %d\n", length(cols_a_escalar)))
cat(sprintf("  Variables excluidas (coords/ID): %s\n",
            paste(intersect(cols_no_escalar, names(predictores_union)), collapse = ", ")))

predictores_union <- predictores_union %>%
  mutate(across(all_of(cols_a_escalar), ~ as.numeric(scale(.))))

# Reemplazar NaN por 0 (ocurre cuando sd == 0, es decir variable constante)
n_nan <- sum(is.nan(as.matrix(predictores_union[, cols_a_escalar])), na.rm = TRUE)
if (n_nan > 0) {
  cat(sprintf("  Reemplazando %d NaN (SD=0) por 0\n", n_nan))
  predictores_union <- predictores_union %>%
    mutate(across(all_of(cols_a_escalar), ~ replace(., is.nan(.), 0)))
}

cat(sprintf("\nPredictores finales (escalados): %d cuadriculas x %d variables\n",
            nrow(predictores_union), ncol(predictores_union) - 1))

# --- 4b. Alias X/Y para coordenadas (compatibilidad con 03b modelo espacial) ---
# El Excel SEO usa La (latitud) y Lo (longitud). Los scripts de modelado
# espacial (03b) esperan columnas X e Y. Convencion: Lo=X, La=Y.
if ("Lo" %in% names(predictores_union) && !"X" %in% names(predictores_union)) {
  predictores_union$X <- predictores_union$Lo  # Longitud = eje X
  predictores_union$Y <- predictores_union$La  # Latitud = eje Y
  cat("  Alias creados: Lo -> X, La -> Y\n")
}

# --- 5. Version con geometria (sf) ---
n_malla <- nrow(malla_union)
predictores_sf <- malla_union %>%
  left_join(st_drop_geometry(predictores_union), by = "CUADRICULA")

# O8: Validacion post-join sf
stopifnot(
  "Join malla+predictores perdio filas" = nrow(predictores_sf) == n_malla
)
cat(sprintf("Predictores SF: %d cuadriculas\n", nrow(predictores_sf)))

# --- 6. Verificacion ---
n_na_cols <- colSums(is.na(st_drop_geometry(predictores_sf)))
cols_mucho_na <- names(n_na_cols[n_na_cols > nrow(predictores_sf) * 0.5])
if (length(cols_mucho_na) > 0) {
  cat(sprintf("\n  AVISO: %d variables con >50%% NAs\n", length(cols_mucho_na)))
}

# --- 7. Validacion global: minimo de cuadriculas ---
# La malla PI+BAL debe tener ~5500+ cuadriculas. Si tenemos menos de 5000,
# algo fallo en los joins o filtrados anteriores.
validar_n_cuadriculas(predictores_union, min_rows = 5000,
                       context = "predictores_union en 01f")
validar_n_cuadriculas(predictores_sf, min_rows = 5000,
                       context = "predictores_sf en 01f")
cat(sprintf("  Validacion de filas: %d cuadriculas (OK, >= 5000)\n", nrow(predictores_sf)))

# --- 8. Guardar ---
saveRDS(predictores_union, CONFIG$paths$predictores_seo_geo)
saveRDS(predictores_sf, CONFIG$paths$predictores_seo_geo_sf)

cat(sprintf("\n[OK] Guardados:\n"))
cat(sprintf("  - %s\n", CONFIG$paths$predictores_seo_geo))
cat(sprintf("  - %s\n", CONFIG$paths$predictores_seo_geo_sf))
