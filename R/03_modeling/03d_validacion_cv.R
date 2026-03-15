# ==============================================================================
# 03d_validacion_cv.R - Validacion cruzada espacial
# ==============================================================================
#
# INPUT:  data/processed/PAxENV_all_metodos.rds
#         output/seleccion_variables/variables_json/{especie}.json
# OUTPUT: output/modelos/{especie}/validacion/
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

if (!exists("CONFIG")) source("R/00_setup/00_config.R")
source("R/utils/utils_checkpoints.R")
source("R/utils/utils_favorabilidad.R")
source("R/utils/utils_metricas.R")
source("R/utils/utils_logging.R")

suppressPackageStartupMessages({
  library(tidyverse)
  library(jsonlite)
})

cat("\n========================================\n")
cat("  FASE 5: VALIDACION CRUZADA ESPACIAL\n")
cat("========================================\n\n")

datos_pa <- readRDS(CONFIG$paths$pa_data)

especies_gremios <- read_csv(CONFIG$paths$especies_gremios, show_col_types = FALSE) %>%
  filter(modelar == TRUE)

if (!is.null(CONFIG$especies$piloto)) {
  especies <- CONFIG$especies$piloto
} else {
  especies <- especies_gremios$especie
}
especies <- setdiff(especies, CONFIG$especies$excluir)

for (sp in especies) {
  cat(sprintf("\n--- %s ---\n", sp))

  if (!CONFIG$control$force_rerun &&
      checkpoint_exists(sp, CONFIG$output$base, "validacion")) {
    cat("  Ya completado\n")
    next
  }

  sp_file <- str_replace_all(sp, " ", "_")
  dir_out <- file.path(CONFIG$output$base, sp_file, "validacion")
  dir.create(dir_out, recursive = TRUE, showWarnings = FALSE)

  json_file <- file.path(CONFIG$paths$variables_json, paste0(sp_file, ".json"))
  if (!file.exists(json_file)) { cat("  [SKIP] Sin JSON\n"); next }

  vars_info <- fromJSON(json_file)
  vars_modelo <- vars_info$variables_finales$name

  sp_col <- paste0("sp_", sp)
  if (!sp_col %in% names(datos_pa)) sp_col <- sp
  datos_sp <- datos_pa %>%
    filter(muestreado == 1) %>%
    select(PA = all_of(sp_col), X, Y, all_of(vars_modelo)) %>%
    drop_na()

  n_pres <- sum(datos_sp$PA == 1)
  if (n_pres < CONFIG$ambiental$min_presencias) {
    log_event("validacion", sp, "WARN",
              sprintf("<%d presencias (n_pres=%d)", CONFIG$ambiental$min_presencias, n_pres))
    next
  }

  # CV con n_rep repeticiones (diferentes particiones por seed)
  n_rep <- CONFIG$validacion$n_rep
  resultados <- tibble()

  for (rep_i in 1:n_rep) {
    # Cada repeticion usa un seed diferente
    set.seed(CONFIG$validacion$seed + rep_i - 1)
    km <- kmeans(datos_sp[, c("X", "Y")], centers = CONFIG$validacion$k_folds, nstart = 25)
    datos_sp$fold <- km$cluster

    for (fold in 1:CONFIG$validacion$k_folds) {
      datos_train <- datos_sp %>% filter(fold != !!fold)
      datos_test <- datos_sp %>% filter(fold == !!fold)

      formula_glm <- as.formula(paste("PA ~", paste(vars_modelo, collapse = " + ")))
      modelo <- tryCatch(
        glm(formula_glm, data = datos_train, family = binomial),
        error = function(e) NULL
      )
      if (is.null(modelo)) next

      # Verificar que test tiene ambos niveles (0 y 1)
      if (length(unique(datos_test$PA)) < 2) next

      pred_prob <- predict(modelo, newdata = datos_test, type = "response")
      pred_fav <- favorabilidad(pred_prob, datos_train$PA)

      metricas_fold <- tryCatch(
        compute_metrics(datos_test$PA, pred_fav) %>% mutate(Fold = fold, Rep = rep_i),
        error = function(e) NULL
      )
      if (!is.null(metricas_fold)) resultados <- bind_rows(resultados, metricas_fold)
    }
  }

  if (nrow(resultados) > 0) {
    write_csv(resultados, file.path(dir_out, "metricas_cv.csv"))

    resumen <- resultados %>%
      summarise(AUC_mean = mean(AUC, na.rm = TRUE), AUC_sd = sd(AUC, na.rm = TRUE),
                TSS_mean = mean(TSS, na.rm = TRUE), TSS_sd = sd(TSS, na.rm = TRUE),
                n_folds_total = n(), n_rep = n_rep)
    write_csv(resumen, file.path(dir_out, "resumen_cv.csv"))

    log_event("validacion", sp, "INFO",
              sprintf("AUC=%.3f+/-%.3f TSS=%.3f+/-%.3f (%d rep x %d folds)",
                      resumen$AUC_mean, resumen$AUC_sd, resumen$TSS_mean, resumen$TSS_sd,
                      n_rep, CONFIG$validacion$k_folds))
  }

  create_checkpoint(sp, CONFIG$output$base, "validacion")
  cat("  [OK]\n")
}

cat("\n[OK] Fase 5 completada\n")
