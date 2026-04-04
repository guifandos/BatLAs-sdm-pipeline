# ==============================================================================
# 03d_bis_validacion_cv_integral.R - CV integral: F_amb + F_esp + F_final
# ==============================================================================
#
# Validates the full pipeline (GLM ambiental + GAM espacial + fuzzy intersection)
# using the same spatial block CV structure as 03d_validacion_cv.R.
#
# For each rep x fold:
#   1. Fit GLM ambiental on train -> predict F_amb on test
#   2. Fit GAM espacial (PA ~ s(X,Y)) on train -> predict F_esp on test
#   3. Compute F_final = sqrt(F_amb * F_esp) on test
#   4. Evaluate AUC, TSS, Sens, Spec for each of {F_amb, F_esp, F_final}
#
# INPUT:  data/processed/PAxENV_all_metodos.rds
#         output/seleccion_variables/variables_json/{especie}.json
# OUTPUT: output/modelos/{especie}/validacion/cv_integral.csv
#         output/modelos/{especie}/validacion/resumen_cv_integral.csv
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
  library(mgcv)
})

cat("\n========================================\n")
cat("  VALIDACION CRUZADA INTEGRAL\n")
cat("  (F_amb + F_esp + F_final)\n")
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

# --- Adaptive k for GAM ---
calcular_k_gam <- function(n_pres) {
  k_max <- CONFIG$espacial$k_gam
  if (isTRUE(CONFIG$espacial$k_gam_adaptativo)) {
    k_adaptado <- min(k_max, floor(n_pres / 4))
    return(max(k_adaptado, 5))
  }
  return(k_max)
}

# --- Fuzzy intersection ---
fuzzy_geometrica <- function(f_amb, f_esp) {
  sqrt(pmax(f_amb, 0) * pmax(f_esp, 0))
}

# --- Main loop ---
resumen_global <- tibble()

for (sp in especies) {
  cat(sprintf("\n--- %s ---\n", sp))

  sp_file <- str_replace_all(sp, " ", "_")
  dir_out <- file.path(CONFIG$output$base, sp_file, "validacion")
  dir.create(dir_out, recursive = TRUE, showWarnings = FALSE)

  # Skip if already done (unless force_rerun)
  cv_integral_file <- file.path(dir_out, "cv_integral.csv")
  if (!CONFIG$control$force_rerun && file.exists(cv_integral_file)) {
    cat("  CV integral ya completada\n")
    next
  }

  # Load variable selection
  json_file <- file.path(CONFIG$paths$variables_json, paste0(sp_file, ".json"))
  if (!file.exists(json_file)) { cat("  [SKIP] Sin JSON\n"); next }

  vars_info <- fromJSON(json_file)
  vars_modelo <- vars_info$variables_finales$name

  # Prepare species data
  sp_col <- paste0("sp_", sp)
  if (!sp_col %in% names(datos_pa)) sp_col <- sp
  datos_sp <- datos_pa %>%
    filter(muestreado == 1) %>%
    select(PA = all_of(sp_col), X, Y, all_of(vars_modelo)) %>%
    drop_na()

  n_pres <- sum(datos_sp$PA == 1)
  if (n_pres < CONFIG$ambiental$min_presencias) {
    cat(sprintf("  [SKIP] <%d presencias (n=%d)\n", CONFIG$ambiental$min_presencias, n_pres))
    next
  }

  k_gam <- calcular_k_gam(n_pres)

  # CV loop
  n_rep <- CONFIG$validacion$n_rep
  resultados <- tibble()

  for (rep_i in 1:n_rep) {
    set.seed(CONFIG$validacion$seed + rep_i - 1)
    km <- kmeans(datos_sp[, c("X", "Y")], centers = CONFIG$validacion$k_folds, nstart = 25)
    datos_sp$fold <- km$cluster

    for (fold in 1:CONFIG$validacion$k_folds) {
      datos_train <- datos_sp %>% filter(fold != !!fold)
      datos_test  <- datos_sp %>% filter(fold == !!fold)

      # Need both classes in test
      if (length(unique(datos_test$PA)) < 2) next

      # --- 1. GLM ambiental ---
      formula_glm <- as.formula(paste("PA ~", paste(vars_modelo, collapse = " + ")))
      glm_amb <- tryCatch(
        glm(formula_glm, data = datos_train, family = binomial),
        error = function(e) NULL
      )
      if (is.null(glm_amb)) next

      pred_prob_amb <- predict(glm_amb, newdata = datos_test, type = "response")
      f_amb_test <- favorabilidad(pred_prob_amb, datos_train$PA)

      # --- 2. GAM espacial (PA ~ s(X,Y), directo) ---
      n_pres_train <- sum(datos_train$PA == 1)
      k_fold <- max(min(k_gam, floor(n_pres_train / 4)), 5)

      gam_esp <- tryCatch(
        gam(PA ~ s(X, Y, k = k_fold), data = datos_train, family = binomial, method = "ML"),
        error = function(e) NULL
      )
      if (is.null(gam_esp)) next

      pred_prob_esp <- predict(gam_esp, newdata = datos_test, type = "response")
      f_esp_test <- favorabilidad(pred_prob_esp, datos_train$PA)

      # --- 3. F_final (fuzzy intersection) ---
      f_final_test <- fuzzy_geometrica(f_amb_test, f_esp_test)

      # --- 4. Evaluate all three ---
      met_amb <- tryCatch(
        compute_metrics(datos_test$PA, f_amb_test) %>% mutate(modelo = "F_amb"),
        error = function(e) NULL
      )
      met_esp <- tryCatch(
        compute_metrics(datos_test$PA, f_esp_test) %>% mutate(modelo = "F_esp"),
        error = function(e) NULL
      )
      met_final <- tryCatch(
        compute_metrics(datos_test$PA, f_final_test) %>% mutate(modelo = "F_final"),
        error = function(e) NULL
      )

      fold_results <- bind_rows(met_amb, met_esp, met_final) %>%
        mutate(Rep = rep_i, Fold = fold)

      resultados <- bind_rows(resultados, fold_results)
    }
  }

  # --- Save results ---
  if (nrow(resultados) > 0) {
    resultados <- resultados %>%
      mutate(especie = sp) %>%
      select(especie, Rep, Fold, modelo, AUC, TSS, Sens, Spec, Threshold, n)

    write_csv(resultados, cv_integral_file)

    resumen <- resultados %>%
      group_by(modelo) %>%
      summarise(
        AUC_mean = mean(AUC, na.rm = TRUE), AUC_sd = sd(AUC, na.rm = TRUE),
        TSS_mean = mean(TSS, na.rm = TRUE), TSS_sd = sd(TSS, na.rm = TRUE),
        Sens_mean = mean(Sens, na.rm = TRUE),
        Spec_mean = mean(Spec, na.rm = TRUE),
        n_folds = n(),
        .groups = "drop"
      ) %>%
      mutate(especie = sp) %>%
      select(especie, everything())

    write_csv(resumen, file.path(dir_out, "resumen_cv_integral.csv"))

    # Log summary
    for (m in c("F_amb", "F_esp", "F_final")) {
      r <- resumen %>% filter(modelo == m)
      if (nrow(r) > 0) {
        cat(sprintf("  %s: AUC=%.3f±%.3f  TSS=%.3f±%.3f\n",
                    m, r$AUC_mean, r$AUC_sd, r$TSS_mean, r$TSS_sd))
      }
    }

    resumen_global <- bind_rows(resumen_global, resumen)
  } else {
    cat("  [WARN] Sin resultados validos\n")
  }
}

# --- Global summary ---
if (nrow(resumen_global) > 0) {
  dir_global <- file.path(CONFIG$output$base, "..", "validacion_integral")
  dir.create(dir_global, recursive = TRUE, showWarnings = FALSE)
  write_csv(resumen_global, file.path(dir_global, "resumen_cv_integral_todas.csv"))

  cat("\n\n========================================\n")
  cat("  RESUMEN GLOBAL CV INTEGRAL\n")
  cat("========================================\n\n")

  resumen_print <- resumen_global %>%
    group_by(modelo) %>%
    summarise(
      AUC = sprintf("%.3f ± %.3f", mean(AUC_mean), sd(AUC_mean)),
      TSS = sprintf("%.3f ± %.3f", mean(TSS_mean), sd(TSS_mean)),
      n_sp = n(),
      .groups = "drop"
    )
  print(as.data.frame(resumen_print))
}

cat("\n[OK] Validacion cruzada integral completada\n")
