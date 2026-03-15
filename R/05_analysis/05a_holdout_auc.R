# ==============================================================================
# 05a_holdout_auc.R - AUC hold-out comparable con pipeline v1
# ==============================================================================
#
# Calcula AUC y TSS con hold-out aleatorio (70/30) para cada especie,
# replicando la metodologia del pipeline v1. Esto permite una comparacion
# directa con los resultados de atlas_murcielagos_pipeline_26112025.
#
# OUTPUT: output/modelos/metricas_holdout_comparables.csv
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

if (!exists("CONFIG")) source("R/00_setup/00_config.R")
source("R/utils/utils_favorabilidad.R")
source("R/utils/utils_metricas.R")

suppressPackageStartupMessages({
  library(tidyverse)
  library(jsonlite)
})

cat("\n========================================\n")
cat("  AUC HOLD-OUT (comparable con v1)\n")
cat("========================================\n\n")

# Cargar datos
datos_pa <- readRDS(CONFIG$paths$pa_data)

# Especies con modelo completo (tienen checkpoint_mapas o al menos ambiental)
especies_gremios <- read_csv(CONFIG$paths$especies_gremios, show_col_types = FALSE) %>%
  filter(modelar == TRUE)

json_dir <- CONFIG$paths$variables_json
jsons <- list.files(json_dir, pattern = "\\.json$", full.names = TRUE)
especies <- str_replace(basename(jsons), "\\.json$", "") %>%
  str_replace_all("_", " ")

# Excluir especies sin modelo completo (sin checkpoint_ambiental)
especies <- especies[sapply(especies, function(sp) {
  sp_file <- str_replace_all(sp, " ", "_")
  file.exists(file.path(CONFIG$output$base, sp_file, "ambiental", "checkpoint_ambiental.txt"))
})]

cat(sprintf("Especies a evaluar: %d\n\n", length(especies)))

# Parametros hold-out (mismos que v1)
prop_train <- 0.70
seed <- 123

resultados <- tibble()

for (sp in especies) {
  cat(sprintf("--- %s ---\n", sp))

  sp_file <- str_replace_all(sp, " ", "_")
  json_file <- file.path(json_dir, paste0(sp_file, ".json"))
  vars_info <- fromJSON(json_file)
  vars_modelo <- vars_info$variables_finales$name

  # Preparar datos
  sp_col <- paste0("sp_", sp)
  if (!sp_col %in% names(datos_pa)) sp_col <- sp

  datos_sp <- datos_pa %>%
    filter(muestreado == 1) %>%
    select(PA = all_of(sp_col), all_of(vars_modelo)) %>%
    drop_na()

  n_pres <- sum(datos_sp$PA == 1)
  n_aus <- sum(datos_sp$PA == 0)

  if (n_pres < 10) {
    cat(sprintf("  [SKIP] Solo %d presencias\n", n_pres))
    next
  }

  # Hold-out split (mismo seed que v1)
  set.seed(seed)
  idx_train <- sample(1:nrow(datos_sp), size = floor(prop_train * nrow(datos_sp)))
  datos_train <- datos_sp[idx_train, ]
  datos_test <- datos_sp[-idx_train, ]

  # GLM
  formula_glm <- as.formula(paste("PA ~", paste(vars_modelo, collapse = " + ")))
  modelo <- tryCatch(
    glm(formula_glm, data = datos_train, family = binomial),
    error = function(e) NULL
  )

  if (is.null(modelo)) {
    cat("  [ERROR] GLM fallo\n")
    next
  }

  # Prediccion y favorabilidad en test
  pred_prob <- predict(modelo, newdata = datos_test, type = "response")
  pred_fav <- favorabilidad(pred_prob, datos_train$PA)

  # Metricas
  metricas <- tryCatch(
    compute_metrics(datos_test$PA, pred_fav),
    error = function(e) {
      cat(sprintf("  [ERROR] Metricas: %s\n", e$message))
      NULL
    }
  )

  if (!is.null(metricas)) {
    metricas <- metricas %>%
      mutate(
        especie = sp,
        n_presencias = n_pres,
        n_ausencias = n_aus,
        n_variables = length(vars_modelo),
        prevalencia = n_pres / (n_pres + n_aus)
      )
    resultados <- bind_rows(resultados, metricas)
    cat(sprintf("  AUC=%.3f  TSS=%.3f  (n_pres=%d, n_vars=%d)\n",
                metricas$AUC, metricas$TSS, n_pres, length(vars_modelo)))
  }
}

# Guardar resultados
if (nrow(resultados) > 0) {
  out_file <- file.path(CONFIG$output$base, "metricas_holdout_comparables.csv")
  resultados <- resultados %>%
    select(especie, AUC, TSS, Sens, Spec, Threshold,
           n_presencias, n_ausencias, n_variables, prevalencia) %>%
    arrange(desc(AUC))
  write_csv(resultados, out_file)
  cat(sprintf("\n[OK] Resultados guardados en %s\n", out_file))

  cat("\n========================================\n")
  cat("  RESUMEN\n")
  cat("========================================\n")
  cat(sprintf("  Especies evaluadas: %d\n", nrow(resultados)))
  cat(sprintf("  AUC medio:  %.3f (rango: %.3f - %.3f)\n",
              mean(resultados$AUC, na.rm = TRUE),
              min(resultados$AUC, na.rm = TRUE),
              max(resultados$AUC, na.rm = TRUE)))
  cat(sprintf("  TSS medio:  %.3f (rango: %.3f - %.3f)\n",
              mean(resultados$TSS, na.rm = TRUE),
              min(resultados$TSS, na.rm = TRUE),
              max(resultados$TSS, na.rm = TRUE)))
}

cat("\n[OK] Completado\n")
