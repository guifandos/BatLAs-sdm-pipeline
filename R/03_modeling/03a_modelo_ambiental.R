# ==============================================================================
# 03a_modelo_ambiental.R - GLM + Favorabilidad + Bootstrap
# ==============================================================================
#
# INPUT:  data/processed/PAxENV_all_metodos.rds
#         output/seleccion_variables/variables_json/{especie}.json
#         data/processed/predictores_all.rds
# OUTPUT: output/modelos/{especie}/ambiental/
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
cat("  FASE 2: MODELO AMBIENTAL (GLM)\n")
cat("========================================\n\n")

# Cargar datos
datos_pa <- readRDS(CONFIG$paths$pa_data)
grid_data <- readRDS(CONFIG$paths$grid_predictores)

# Cargar tabla de especies
especies_gremios <- read_csv(CONFIG$paths$especies_gremios, show_col_types = FALSE) %>%
  filter(modelar == TRUE)

# Determinar especies a procesar
if (!is.null(CONFIG$especies$piloto)) {
  especies <- CONFIG$especies$piloto
} else {
  json_dir <- CONFIG$paths$variables_json
  jsons <- list.files(json_dir, pattern = "\\.json$", full.names = TRUE)
  especies <- str_replace(basename(jsons), "\\.json$", "") %>%
    str_replace_all("_", " ")
}

especies <- setdiff(especies, CONFIG$especies$excluir)
cat(sprintf("Especies a procesar: %d\n\n", length(especies)))

# --- Funcion de modelado por especie (encapsulada para paralelizacion) ---
modelar_ambiental_sp <- function(sp, datos_pa, grid_data) {

  sp_file <- str_replace_all(sp, " ", "_")
  dir_out <- file.path(CONFIG$output$base, sp_file, "ambiental")

  # Checkpoint
  if (!CONFIG$control$force_rerun &&
      checkpoint_exists(sp, CONFIG$output$base, "ambiental")) {
    log_event("ambiental", sp, "INFO", "Ya completado (checkpoint)")
    return(list(status = "skip", sp = sp))
  }

  crear_estructura_especie(sp, CONFIG$output$base)

  # Cargar variables seleccionadas
  json_file <- file.path(CONFIG$paths$variables_json, paste0(sp_file, ".json"))
  if (!file.exists(json_file)) {
    log_event("ambiental", sp, "WARN", "Sin JSON de variables")
    return(list(status = "skip", sp = sp))
  }
  vars_info <- fromJSON(json_file)
  vars_modelo <- vars_info$variables_finales$name

  # Preparar datos (columnas de especie tienen prefijo sp_ desde 01g)
  sp_col <- paste0("sp_", sp)
  if (!sp_col %in% names(datos_pa)) sp_col <- sp  # fallback sin prefijo
  datos_sp <- datos_pa %>%
    filter(muestreado == 1) %>%
    select(PA = all_of(sp_col), all_of(vars_modelo)) %>%
    drop_na()

  n_pres <- sum(datos_sp$PA == 1)
  n_aus <- sum(datos_sp$PA == 0)

  if (n_pres < CONFIG$ambiental$min_presencias ||
      n_aus < CONFIG$ambiental$min_ausencias) {
    log_event("ambiental", sp, "WARN",
              sprintf("Datos insuficientes (%d pres, %d aus)", n_pres, n_aus))
    return(list(status = "skip", sp = sp))
  }

  # Hold-out split estratificado (mantiene proporcion presencias/ausencias)
  set.seed(CONFIG$ambiental$seed)
  idx_pres <- which(datos_sp$PA == 1)
  idx_aus <- which(datos_sp$PA == 0)
  n_train_pres <- floor(CONFIG$ambiental$prop_train * length(idx_pres))
  n_train_aus <- floor(CONFIG$ambiental$prop_train * length(idx_aus))
  idx_train <- c(
    sample(idx_pres, size = n_train_pres),
    sample(idx_aus, size = n_train_aus)
  )
  datos_train <- datos_sp[idx_train, ]
  datos_test <- datos_sp[-idx_train, ]

  # Ajustar GLM
  formula_glm <- as.formula(paste("PA ~", paste(vars_modelo, collapse = " + ")))
  modelo <- tryCatch(
    glm(formula_glm, data = datos_train, family = binomial),
    error = function(e) {
      log_event("ambiental", sp, "ERROR", paste("GLM:", e$message))
      NULL
    }
  )
  if (is.null(modelo)) return(list(status = "error", sp = sp))

  # Predicciones en test
  pred_test <- predict(modelo, newdata = datos_test, type = "response")
  fav_test <- favorabilidad(pred_test, datos_train$PA)
  metricas <- compute_metrics(datos_test$PA, fav_test)

  log_event("ambiental", sp, "INFO",
            sprintf("AUC=%.3f TSS=%.3f", metricas$AUC, metricas$TSS))

  # Preparar grid para prediccion
  if (!is.null(grid_data$vars_all)) {
    datos_pred <- grid_data$vars_all
  } else {
    datos_pred <- datos_pa %>% select(all_of(vars_modelo))
  }

  # Imputacion de NAs con mediana del training set
  medians <- sapply(datos_train[, vars_modelo], median, na.rm = TRUE)
  datos_pred_imp <- impute_median(datos_pred[, vars_modelo, drop = FALSE], medians)

  # Bootstrap
  n_pred <- nrow(datos_pred_imp)
  boot_matrix <- matrix(NA, nrow = n_pred, ncol = CONFIG$ambiental$n_bootstrap)

  for (b in 1:CONFIG$ambiental$n_bootstrap) {
    boot_idx <- sample(1:nrow(datos_train), replace = TRUE)
    datos_boot <- datos_train[boot_idx, ]
    modelo_boot <- tryCatch(
      glm(formula_glm, data = datos_boot, family = binomial),
      error = function(e) NULL
    )
    if (!is.null(modelo_boot)) {
      p_boot <- predict(modelo_boot, newdata = datos_pred_imp, type = "response")
      boot_matrix[, b] <- favorabilidad(p_boot, datos_boot$PA)
    }
  }

  # Resumen bootstrap
  F_mean <- rowMeans(boot_matrix, na.rm = TRUE)
  F_sd <- apply(boot_matrix, 1, sd, na.rm = TRUE)
  F_q025 <- apply(boot_matrix, 1, quantile, probs = 0.025, na.rm = TRUE)
  F_q975 <- apply(boot_matrix, 1, quantile, probs = 0.975, na.rm = TRUE)
  W_glm <- F_q975 - F_q025

  # Guardar outputs
  predicciones <- tibble(F_glm_mean = F_mean, F_glm_sd = F_sd,
                         q025 = F_q025, q975 = F_q975, W_glm = W_glm)
  write_csv(predicciones, file.path(dir_out, "predicciones.csv"))
  write_csv(metricas, file.path(dir_out, "metricas_holdout.csv"))

  coefs <- broom::tidy(modelo, conf.int = TRUE) %>%
    rename(Variable = term, IC_low = conf.low, IC_high = conf.high, p = p.value)
  write_csv(coefs, file.path(dir_out, "coeficientes_glm.csv"))

  saveRDS(modelo, file.path(dir_out, "modelo_glm.rds"))
  saveRDS(boot_matrix, file.path(dir_out, "bootstrap_samples.rds"))
  saveRDS(datos_train, file.path(dir_out, "datos_entrenamiento.rds"))

  write_json(list(especie = sp, n_pres = n_pres, n_aus = n_aus,
                  n_vars = length(vars_modelo), AUC = metricas$AUC, TSS = metricas$TSS,
                  n_bootstrap = CONFIG$ambiental$n_bootstrap, fecha = as.character(Sys.time())),
             file.path(dir_out, "metadata.json"), pretty = TRUE, auto_unbox = TRUE)

  create_checkpoint(sp, CONFIG$output$base, "ambiental",
                    metadata = list(AUC = round(metricas$AUC, 3), TSS = round(metricas$TSS, 3)))

  log_event("ambiental", sp, "INFO", "Completado")
  return(list(status = "ok", sp = sp, AUC = metricas$AUC, TSS = metricas$TSS))
}

# --- Ejecucion: paralela o secuencial ---
if (isTRUE(CONFIG$control$usar_parallel) && CONFIG$control$n_cores > 1) {
  suppressPackageStartupMessages({ library(future); library(future.apply) })
  plan(multisession, workers = CONFIG$control$n_cores)
  cat(sprintf("Ejecucion paralela: %d cores\n\n", CONFIG$control$n_cores))
  resultados <- future_lapply(especies, modelar_ambiental_sp,
                              datos_pa = datos_pa, grid_data = grid_data,
                              future.seed = CONFIG$ambiental$seed)
  plan(sequential)
} else {
  resultados <- list()
  for (i in seq_along(especies)) {
    sp <- especies[i]
    cat(sprintf("\n--- [%d/%d] %s ---\n", i, length(especies), sp))
    resultados[[i]] <- modelar_ambiental_sp(sp, datos_pa, grid_data)
  }
}

# Resumen
n_ok <- sum(sapply(resultados, function(r) r$status == "ok"))
n_skip <- sum(sapply(resultados, function(r) r$status == "skip"))
n_err <- sum(sapply(resultados, function(r) r$status == "error"))
cat(sprintf("\n[OK] Fase 2: %d completadas, %d omitidas, %d errores\n", n_ok, n_skip, n_err))
