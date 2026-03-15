# ==============================================================================
# 01e_procesar_geologia.R - Procesar variables geologicas
# ==============================================================================
#
# RAZON CIENTIFICA — KARST:
# La geologia karstica es el principal predictor de disponibilidad de refugios
# naturales (cuevas, simas, abrigos) para murcielagos cavernicolas. Especies
# como Rhinolophus ferrumequinum, R. euryale, Miniopterus schreibersii o
# Myotis blythii dependen de cavidades karsticas para hibernacion, cria y
# transito estacional. Las variables Karst_principal, Karst_secundario y
# Karst_total cuantifican la proporcion de sustrato karstico en cada
# cuadricula, capturando tanto las cuevas accesibles como el potencial
# geologico latente.
#
# RAZON CIENTIFICA — LITOLOGIA PCA:
# Los datos litologicos originales contienen 250+ codigos de tipo de roca
# (columnas lito_HISTO_*), lo que genera un espacio de predictores altamente
# dimensional y disperso. La mayoria de cuadriculas solo tienen 3-5 tipos.
# Un PCA reduce esta dimensionalidad a 5 ejes ortogonales que capturan los
# gradientes litologicos principales (e.g., PC1 = gradiente calizo vs.
# siliceo, PC2 = gradiente igneo vs. sedimentario). Esto evita sobreajuste
# y colinealidad en los modelos de Fase 2.
#
# INPUT:  CONFIG$paths$karst_csv
#         CONFIG$paths$lito_csv
# OUTPUT: CONFIG$paths$geo_features
#
# Aplica:
#   1. Agrupacion de Karst (principal, secundario, total)
#   2. Agrupacion de Litologia (karsticas, siliciclasticas, igneas, metamorficas)
#   3. Litologia dominante y diversidad (Shannon)
#   4. PCA de litologia (5 componentes, opcional)
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

# --- Cargar configuracion y utilidades (idempotente) ---
if (!exists("CONFIG")) source("R/00_setup/00_config.R")
if (!exists("norm_id")) source("R/utils/utils_checkpoints.R")
if (!exists("agrupar_karst")) source("R/utils/utils_geologia.R")
if (!exists("agrupar_litologia")) source("R/utils/utils_litologia.R")

suppressPackageStartupMessages(library(tidyverse))

cat("\n=== 01e: PROCESAR GEOLOGIA ===\n\n")

# --- 1. Cargar CSVs de Karst y Litologia ---
cat("Cargando datos geologicos...\n")

karst_raw <- NULL
if (file.exists(CONFIG$paths$karst_csv)) {
  karst_raw <- read_csv(CONFIG$paths$karst_csv, show_col_types = FALSE)
  karst_raw <- std_ids_tbl(karst_raw, canonical = "CUADRICULA")
  cat(sprintf("  Columna ID karst normalizada a 'CUADRICULA' (%d IDs unicos)\n",
              n_distinct(karst_raw$CUADRICULA)))

  # Renombrar HISTO_* -> Karst_HISTO_* (los CSVs crudos no traen prefijo)
  histo_cols_raw <- names(karst_raw)[str_detect(names(karst_raw), "^HISTO_[0-9]")]
  if (length(histo_cols_raw) > 0) {
    names(karst_raw)[names(karst_raw) %in% histo_cols_raw] <-
      paste0("Karst_", histo_cols_raw)
    cat(sprintf("  Renombradas %d columnas HISTO_* -> Karst_HISTO_*\n",
                length(histo_cols_raw)))
  }

  # Validar que existen columnas con el patron esperado Karst_HISTO_*
  karst_cols <- names(karst_raw)[str_detect(names(karst_raw), "^Karst_HISTO_")]
  if (length(karst_cols) == 0) {
    warning(
      "CSV de Karst cargado pero no contiene columnas con patron 'Karst_HISTO_'. ",
      "Columnas encontradas: ", paste(head(names(karst_raw), 10), collapse = ", "),
      if (ncol(karst_raw) > 10) " ..." else ""
    )
  } else {
    cat(sprintf("  Karst: %d filas x %d columnas (%d columnas Karst_HISTO_)\n",
                nrow(karst_raw), ncol(karst_raw), length(karst_cols)))
  }
} else {
  cat("  AVISO: Karst CSV no encontrado\n")
}

lito_raw <- NULL
if (file.exists(CONFIG$paths$lito_csv)) {
  lito_raw <- read_csv(CONFIG$paths$lito_csv, show_col_types = FALSE)
  lito_raw <- std_ids_tbl(lito_raw, canonical = "CUADRICULA")
  cat(sprintf("  Columna ID litologia normalizada a 'CUADRICULA' (%d IDs unicos)\n",
              n_distinct(lito_raw$CUADRICULA)))

  # Renombrar HISTO_* -> lito_HISTO_* (los CSVs crudos no traen prefijo)
  histo_cols_lito_raw <- names(lito_raw)[str_detect(names(lito_raw), "^HISTO_[0-9]")]
  if (length(histo_cols_lito_raw) > 0) {
    names(lito_raw)[names(lito_raw) %in% histo_cols_lito_raw] <-
      paste0("lito_", histo_cols_lito_raw)
    cat(sprintf("  Renombradas %d columnas HISTO_* -> lito_HISTO_*\n",
                length(histo_cols_lito_raw)))
  }

  # Validar que existen columnas con el patron esperado lito_HISTO_*
  lito_cols_check <- names(lito_raw)[str_detect(names(lito_raw), "^lito_HISTO_")]
  if (length(lito_cols_check) == 0) {
    warning(
      "CSV de Litologia cargado pero no contiene columnas con patron 'lito_HISTO_'. ",
      "Columnas encontradas: ", paste(head(names(lito_raw), 10), collapse = ", "),
      if (ncol(lito_raw) > 10) " ..." else ""
    )
  } else {
    cat(sprintf("  Litologia: %d filas x %d columnas (%d columnas lito_HISTO_)\n",
                nrow(lito_raw), ncol(lito_raw), length(lito_cols_check)))
  }
} else {
  cat("  AVISO: Litologia CSV no encontrado\n")
}

# --- Deduplicar por CUADRICULA (CSVs crudos pueden tener filas duplicadas) ---
if (!is.null(karst_raw)) {
  n_dup_k <- nrow(karst_raw) - n_distinct(karst_raw$CUADRICULA)
  if (n_dup_k > 0) {
    karst_raw <- karst_raw %>% distinct(CUADRICULA, .keep_all = TRUE)
    cat(sprintf("  Karst: eliminadas %d filas duplicadas -> %d filas\n", n_dup_k, nrow(karst_raw)))
  }
}
if (!is.null(lito_raw)) {
  n_dup_l <- nrow(lito_raw) - n_distinct(lito_raw$CUADRICULA)
  if (n_dup_l > 0) {
    lito_raw <- lito_raw %>% distinct(CUADRICULA, .keep_all = TRUE)
    cat(sprintf("  Lito: eliminadas %d filas duplicadas -> %d filas\n", n_dup_l, nrow(lito_raw)))
  }
}

if (is.null(karst_raw) && is.null(lito_raw)) {
  cat("  Sin datos geologicos, creando tabla vacia\n")
  geo_features <- tibble(CUADRICULA = character())
  saveRDS(geo_features, CONFIG$paths$geo_features)
  cat("[OK] Geo features vacio guardado\n")
} else {
  # --- 2. Construir features geologicos ---
  # build_geo_features() integra karst y litologia en una unica tabla:
  #   - Karst_principal/secundario/total: proporcion de sustrato karstico
  #   - Lito_karsticas/siliciclasticas/igneas/metamorficas/otras: grupos litologicos
  #   - Lito_dominante, Lito_diversidad, Lito_n_tipos: indices de composicion
  cat("\nConstruyendo features geologicos...\n")

  # Determinar la columna ID (normalizada por std_ids_tbl a CUADRICULA)
  key <- "CUADRICULA"

  if (!is.null(karst_raw) && !is.null(lito_raw)) {
    geo_features <- build_geo_features(karst_raw, lito_raw, key = key)
  } else if (!is.null(karst_raw)) {
    # Solo karst disponible: extraer indices de karstificacion
    geo_features <- agrupar_karst(karst_raw) %>%
      select(all_of(key), Karst_principal, Karst_secundario, Karst_total)
  } else {
    # Solo litologia disponible: agrupar tipos y calcular indices
    geo_features <- agrupar_litologia(lito_raw) %>%
      select(all_of(key), Lito_karsticas, Lito_siliciclasticas, Lito_igneas,
             Lito_metamorficas, Lito_otras)
    geo_features <- calcular_litologia_dominante(geo_features)
    geo_features <- calcular_diversidad_litologica(geo_features)
  }

  # --- 3. PCA de litologia (opcional) ---
  # Reduccion de dimensionalidad: de 250+ tipos litologicos a 5 ejes ortogonales.
  # Solo se ejecuta si FactoMineR esta disponible y hay columnas lito_HISTO_*.
  if (!is.null(lito_raw) && requireNamespace("FactoMineR", quietly = TRUE)) {
    lito_cols <- names(lito_raw)[str_detect(names(lito_raw), "^lito_HISTO_[0-9]+$")]
    if (length(lito_cols) > 0) {
      cat(sprintf("\nRealizando PCA de litologia (%d columnas lito_HISTO)...\n",
                  length(lito_cols)))
      if (!exists("pca_litologia")) source("R/utils/utils_pca_litologia.R")
      resultado_pca <- pca_litologia(lito_raw, n_componentes = 5,
                                     save_plots = isTRUE(CONFIG$control$ejecutar$qa_mapas),
                                     plot_dir = CONFIG$output$figs)
      # Extraer componentes principales y unirlos a geo_features
      pcs <- resultado_pca$datos %>%
        select(all_of(key), starts_with("Lito_PC"))
      n_geo_pre <- nrow(geo_features)
      geo_features <- geo_features %>%
        left_join(pcs, by = key)
      stopifnot(
        "Join geo_features+PCA perdio o duplico filas" = nrow(geo_features) == n_geo_pre
      )
      cat(sprintf("  PCA unido: %d filas preservadas\n", nrow(geo_features)))
    }
  }

  # --- 4. Diagnostico ---
  cat("\nVariables geologicas creadas:\n")
  cat("  - Karst:", sum(str_detect(names(geo_features), "^Karst_")), "\n")
  cat("  - Litologia agrupada:", sum(str_detect(names(geo_features), "^Lito_(karsticas|siliciclasticas|igneas|metamorficas|otras)$")), "\n")
  cat("  - Litologia indices:", sum(str_detect(names(geo_features), "^Lito_(diversidad|n_tipos|dominancia|dominante)$")), "\n")
  cat("  - Litologia PCA:", sum(str_detect(names(geo_features), "^Lito_PC[0-9]")), "\n")
  cat(sprintf("  - Total: %d filas x %d columnas\n", nrow(geo_features), ncol(geo_features)))

  # --- 5. Guardar ---
  saveRDS(geo_features, CONFIG$paths$geo_features)
  cat(sprintf("\n[OK] Guardado: %s\n", CONFIG$paths$geo_features))
}
