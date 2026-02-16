# ==============================================================================
# 01c_cargar_variables_excel.R - Cargar variables ambientales desde Excel
# ==============================================================================
#
# INPUT:  CONFIG$paths$variables_excel_ec
#         CONFIG$paths$variables_excel_bal
#         CONFIG$paths$malla_union (from 01b)
# OUTPUT: CONFIG$paths$predictores_seo (lista con tablas de variables)
#
# NOTA IMPORTANTE:
#   Las variables numericas NO se escalan (z-score) en este paso.
#   El escalado se aplica en 01f_unir_predictores.R, DESPUES de unir
#   Peninsula y Baleares, para que todas las cuadriculas compartan la misma
#   media y desviacion tipica.  Si se escalara aqui, cada region tendria
#   estadisticos propios y los valores z-score no serian comparables.
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

if (!exists("CONFIG")) source("R/00_setup/00_config.R")
source("R/utils/utils_checkpoints.R")

suppressPackageStartupMessages({
  library(tidyverse)
  library(readxl)
  library(sf)
})

cat("\n=== 01c: CARGAR VARIABLES DESDE EXCEL ===\n\n")

# --- 1. Variables Peninsula + Canarias (EC) ---
cat("Cargando Variables_EC.xlsx...\n")
ec_raw <- read_excel(CONFIG$paths$variables_excel_ec) %>%
  std_ids_tbl("CUADRICULA")

cat(sprintf("  EC: %d filas x %d columnas\n", nrow(ec_raw), ncol(ec_raw)))

# Filtrar Canarias (28R)
n_antes <- nrow(ec_raw)
ec_raw <- ec_raw %>% filter(!str_detect(CUADRICULA, "^28R"))
cat(sprintf("  Tras filtrar Canarias: %d filas (-%d)\n",
            nrow(ec_raw), n_antes - nrow(ec_raw)))

# --- 2. Variables Baleares (BAL) ---
if (file.exists(CONFIG$paths$variables_excel_bal)) {
  cat("Cargando Variables_BAL.xlsx...\n")
  bal_raw <- read_excel(CONFIG$paths$variables_excel_bal) %>%
    std_ids_tbl("CUADRICULA")
  cat(sprintf("  BAL: %d filas x %d columnas\n", nrow(bal_raw), ncol(bal_raw)))
} else {
  cat("  AVISO: Variables_BAL.xlsx no encontrado\n")
  bal_raw <- NULL
}

# --- 3. Codigos de variables (opcional) ---
codigos <- NULL
if (file.exists(CONFIG$paths$codigos_variables)) {
  cat("Cargando Codigos_variables.xlsx...\n")
  codigos <- read_excel(CONFIG$paths$codigos_variables)
  cat(sprintf("  Codigos: %d variables documentadas\n", nrow(codigos)))
}

# --- 4. Cargar malla union ---
malla_union <- readRDS(CONFIG$paths$malla_union)

# --- 5. Construir objeto predictores (sin escalar) ---
# Se almacenan los datos crudos.  El escalado (z-score) se pospone a
# 01f_unir_predictores.R para garantizar que scale() use la media y SD
# calculadas sobre Peninsula + Baleares juntas.
#
# Columnas que NUNCA deben escalarse (coordenadas / IDs):
#   CUADRICULA, La, Lo, La2, Lo2, LaLo
# Nota: NaN producidos por scale() cuando SD=0 se reemplazaran por 0 en 01f.

predictores <- list(
  malla_union = malla_union,
  ec          = ec_raw,
  bal         = bal_raw,
  codigos     = codigos,
  ec_raw      = ec_raw,
  bal_raw     = bal_raw
)

# Validacion: EC debe tener >= 5000 cuadriculas (Peninsula sin Canarias ~5300+)
validar_n_cuadriculas(ec_raw, min_rows = 5000,
                       context = "ec_raw (Variables_EC) en 01c")

cat(sprintf("\nPredictores construidos (datos crudos, sin escalar):\n"))
cat(sprintf("  EC:  %d cuadriculas, %d variables (OK, >= 5000)\n",
            nrow(ec_raw), ncol(ec_raw) - 1))
if (!is.null(bal_raw)) {
  cat(sprintf("  BAL: %d cuadriculas, %d variables\n",
              nrow(bal_raw), ncol(bal_raw) - 1))
}

# --- 6. Guardar ---
saveRDS(predictores, CONFIG$paths$predictores_seo)
cat(sprintf("[OK] Guardado: %s\n", CONFIG$paths$predictores_seo))
