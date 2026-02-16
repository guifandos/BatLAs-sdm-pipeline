# ==============================================================================
# 03e_incertidumbre.R - Incertidumbre compuesta
# ==============================================================================
#
# U = w1*MESS_norm + w2*W_bootstrap_norm + w3*factor_esfuerzo
#
# INPUT:  output/modelos/{especie}/ambiental/
#         output/modelos/{especie}/interseccion/
#         data/processed/esfuerzo_por_metodo.rds
# OUTPUT: output/modelos/{especie}/incertidumbre/
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

source("R/00_setup/00_config.R")
source("R/utils/utils_checkpoints.R")
source("R/utils/utils_logging.R")

suppressPackageStartupMessages({
  library(tidyverse)
  library(jsonlite)
})

# MESS calculation
calcular_mess <- function(datos_train, datos_pred) {
  vars <- intersect(names(datos_train), names(datos_pred))
  datos_train <- datos_train[, vars, drop = FALSE]
  datos_pred <- datos_pred[, vars, drop = FALSE]

  n_pred <- nrow(datos_pred)
  n_vars <- length(vars)
  sim_matrix <- matrix(NA, nrow = n_pred, ncol = n_vars)

  for (i in 1:n_vars) {
    train_min <- min(datos_train[[vars[i]]], na.rm = TRUE)
    train_max <- max(datos_train[[vars[i]]], na.rm = TRUE)
    train_range <- train_max - train_min

    if (train_range == 0) { sim_matrix[, i] <- 100; next }

    pred_vals <- datos_pred[[vars[i]]]
    sim <- rep(NA, n_pred)
    idx_na <- is.na(pred_vals)
    if (any(idx_na)) sim[idx_na] <- -100

    pv <- pred_vals[!idx_na]
    iv <- which(!idx_na)

    if (length(pv) > 0) {
      in_range <- pv >= train_min & pv <= train_max
      if (any(in_range)) {
        d_min <- (pv[in_range] - train_min) / train_range * 100
        d_max <- (train_max - pv[in_range]) / train_range * 100
        sim[iv[in_range]] <- pmin(d_min, d_max)
      }
      low <- pv < train_min
      if (any(low)) sim[iv[low]] <- -abs((train_min - pv[low]) / train_range * 100)
      high <- pv > train_max
      if (any(high)) sim[iv[high]] <- -abs((pv[high] - train_max) / train_range * 100)
    }
    sim_matrix[, i] <- sim
  }

  apply(sim_matrix, 1, min, na.rm = TRUE)
}

cat("\n========================================\n")
cat("  FASE 6: INCERTIDUMBRE\n")
cat("========================================\n\n")

esfuerzo <- readRDS(CONFIG$paths$esfuerzo)
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
      checkpoint_exists(sp, CONFIG$output$base, "incertidumbre")) {
    cat("  Ya completado\n")
    next
  }

  sp_file <- str_replace_all(sp, " ", "_")
  dir_amb <- file.path(CONFIG$output$base, sp_file, "ambiental")
  dir_int <- file.path(CONFIG$output$base, sp_file, "interseccion")
  dir_out <- file.path(CONFIG$output$base, sp_file, "incertidumbre")
  dir.create(dir_out, recursive = TRUE, showWarnings = FALSE)

  pred_file <- file.path(dir_int, "predicciones.csv")
  if (!file.exists(pred_file)) { cat("  [SKIP] Sin interseccion\n"); next }

  pred_int <- read_csv(pred_file, show_col_types = FALSE)

  # 1. MESS
  mess_vals <- rep(0, nrow(pred_int))
  if (CONFIG$incertidumbre$usar_mess && file.exists(file.path(dir_amb, "datos_entrenamiento.rds"))) {
    json_file <- file.path(CONFIG$paths$variables_json, paste0(sp_file, ".json"))
    if (file.exists(json_file)) {
      vars_modelo <- fromJSON(json_file)$variables_finales$name
      datos_train <- readRDS(file.path(dir_amb, "datos_entrenamiento.rds"))
      datos_pred_vars <- datos_pa[, vars_modelo, drop = FALSE]
      mess_vals <- calcular_mess(datos_train[, vars_modelo], datos_pred_vars)
    }
  }
  mess_norm <- pmin(pmax(-mess_vals / 100, 0), 1)

  # 2. Bootstrap width
  W_boot <- pred_int$W_fuzzy
  max_W <- max(W_boot, na.rm = TRUE)
  if (is.finite(max_W) && max_W > 0) {
    W_norm <- W_boot / max_W
  } else {
    W_norm <- rep(0, length(W_boot))
    log_event("incertidumbre", sp, "WARN",
              "W_boot max es 0 o no finito; W_norm fijado a 0")
  }
  W_norm[is.na(W_norm)] <- 1

  # 3. Esfuerzo
  factor_esf <- esfuerzo$factor_incert
  if (length(factor_esf) != nrow(pred_int)) {
    factor_esf <- rep(1, nrow(pred_int))
  }

  # Combinar: pesos fijos o adaptativos
  if (isTRUE(CONFIG$incertidumbre$pesos_adaptativos)) {
    # Pesos adaptativos: proporcionales a la varianza de cada componente
    # Componentes con mayor variabilidad espacial contribuyen mas al indice
    v_mess <- var(mess_norm, na.rm = TRUE)
    v_boot <- var(W_norm, na.rm = TRUE)
    v_esf <- var(factor_esf, na.rm = TRUE)
    v_total <- v_mess + v_boot + v_esf

    if (v_total > 0) {
      w_mess <- v_mess / v_total
      w_boot <- v_boot / v_total
      w_esf <- v_esf / v_total
    } else {
      # Fallback a pesos fijos si todas las varianzas son 0
      w_mess <- CONFIG$incertidumbre$peso_mess
      w_boot <- CONFIG$incertidumbre$peso_bootstrap
      w_esf <- CONFIG$incertidumbre$peso_esfuerzo
    }
    log_event("incertidumbre", sp, "INFO",
              sprintf("Pesos adaptativos: MESS=%.2f Boot=%.2f Esf=%.2f", w_mess, w_boot, w_esf))
  } else {
    w_mess <- CONFIG$incertidumbre$peso_mess
    w_boot <- CONFIG$incertidumbre$peso_bootstrap
    w_esf <- CONFIG$incertidumbre$peso_esfuerzo
  }

  U_final <- w_mess * mess_norm + w_boot * W_norm + w_esf * factor_esf
  U_final <- pmin(U_final, 1)

  resultados <- tibble(MESS = mess_vals, MESS_norm = mess_norm,
                       W_bootstrap = W_boot, W_norm = W_norm,
                       factor_esfuerzo = factor_esf, U_final = U_final,
                       peso_mess = w_mess, peso_bootstrap = w_boot,
                       peso_esfuerzo = w_esf)

  write_csv(resultados, file.path(dir_out, "incertidumbre.csv"))
  saveRDS(resultados, file.path(dir_out, "incertidumbre.rds"))

  create_checkpoint(sp, CONFIG$output$base, "incertidumbre")
  log_event("incertidumbre", sp, "INFO",
            sprintf("U_mean=%.3f", mean(U_final, na.rm = TRUE)))
}

cat("\n[OK] Fase 6 completada\n")
