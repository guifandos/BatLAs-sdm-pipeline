# ==============================================================================
# 03c_interseccion_fuzzy.R - Interseccion fuzzy ambiental x espacial
# ==============================================================================
#
# F_final = sqrt(F_ambiental * F_espacial)  [metodo geometrico]
#
# INPUT:  output/modelos/{especie}/ambiental/bootstrap_samples.rds
#         output/modelos/{especie}/espacial/bootstrap_samples.rds
# OUTPUT: output/modelos/{especie}/interseccion/
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

if (!exists("CONFIG")) source("R/00_setup/00_config.R")
source("R/utils/utils_checkpoints.R")

suppressPackageStartupMessages({
  library(tidyverse)
  library(jsonlite)
})

# Funciones fuzzy
fuzzy_geometrica <- function(a, b) sqrt(a * b)
fuzzy_pmin <- function(a, b) pmin(a, b)
fuzzy_compensatoria <- function(a, b, gamma = 0.5) (a^gamma + b^gamma) / 2

cat("\n========================================\n")
cat("  FASE 4: INTERSECCION FUZZY\n")
cat("========================================\n\n")

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
      checkpoint_exists(sp, CONFIG$output$base, "interseccion")) {
    cat("  Ya completado\n")
    next
  }

  sp_file <- str_replace_all(sp, " ", "_")
  dir_amb <- file.path(CONFIG$output$base, sp_file, "ambiental")
  # Use spatial residuals when configured (avoids double-counting with environmental model)
  esp_subdir <- if (isTRUE(CONFIG$espacial$usar_residuos)) "espacial_residuos" else "espacial"
  dir_esp <- file.path(CONFIG$output$base, sp_file, esp_subdir)
  dir_out <- file.path(CONFIG$output$base, sp_file, "interseccion")
  dir.create(dir_out, recursive = TRUE, showWarnings = FALSE)

  boot_amb_file <- file.path(dir_amb, "bootstrap_samples.rds")
  boot_esp_file <- file.path(dir_esp, "bootstrap_samples.rds")

  if (!file.exists(boot_amb_file) || !file.exists(boot_esp_file)) {
    cat("  [SKIP] Faltan bootstraps\n")
    next
  }

  boot_amb <- readRDS(boot_amb_file)
  boot_esp <- readRDS(boot_esp_file)

  # Asegurar dimensiones compatibles
  n_pred <- nrow(boot_amb)
  n_boot_amb <- ncol(boot_amb)
  n_boot_esp <- ncol(boot_esp)
  n_boot <- min(n_boot_amb, n_boot_esp)
  if (n_boot_amb != n_boot_esp) {
    cat(sprintf("  [AVISO] Matrices bootstrap con dimensiones distintas: ambiental=%d, espacial=%d. Truncando a %d.\n",
                n_boot_amb, n_boot_esp, n_boot))
  }
  boot_amb <- boot_amb[, 1:n_boot]
  boot_esp <- boot_esp[, 1:n_boot]

  # Aplicar interseccion fuzzy a cada iteracion bootstrap
  boot_fuzzy <- matrix(NA, nrow = n_pred, ncol = n_boot)

  for (b in 1:n_boot) {
    a <- boot_amb[, b]
    e <- boot_esp[, b]
    idx <- !is.na(a) & !is.na(e)

    if (CONFIG$interseccion$metodo == "geometrica") {
      boot_fuzzy[idx, b] <- fuzzy_geometrica(a[idx], e[idx])
    } else if (CONFIG$interseccion$metodo == "pmin") {
      boot_fuzzy[idx, b] <- fuzzy_pmin(a[idx], e[idx])
    } else {
      boot_fuzzy[idx, b] <- fuzzy_compensatoria(a[idx], e[idx], CONFIG$interseccion$gamma)
    }
  }

  # Estadisticos
  F_mean <- rowMeans(boot_fuzzy, na.rm = TRUE)
  F_sd <- apply(boot_fuzzy, 1, sd, na.rm = TRUE)
  F_q025 <- apply(boot_fuzzy, 1, quantile, probs = 0.025, na.rm = TRUE)
  F_q975 <- apply(boot_fuzzy, 1, quantile, probs = 0.975, na.rm = TRUE)
  W_fuzzy <- F_q975 - F_q025

  predicciones <- tibble(F_final_mean = F_mean, F_final_sd = F_sd,
                         q025 = F_q025, q975 = F_q975, W_fuzzy = W_fuzzy)

  write_csv(predicciones, file.path(dir_out, "predicciones.csv"))
  saveRDS(boot_fuzzy, file.path(dir_out, "bootstrap_samples.rds"))

  create_checkpoint(sp, CONFIG$output$base, "interseccion")
  cat(sprintf("  [OK] F_mean: %.3f +/- %.3f\n", mean(F_mean, na.rm = TRUE), mean(F_sd, na.rm = TRUE)))
}

cat("\n[OK] Fase 4 completada\n")
