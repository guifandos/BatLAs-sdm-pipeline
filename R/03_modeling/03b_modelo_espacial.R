# ==============================================================================
# 03b_modelo_espacial.R - Modelo espacial (GAM/GLM seleccionado por AICc)
# ==============================================================================
#
# INPUT:  output/modelos/{especie}/ambiental/datos_entrenamiento.rds
#         data/processed/predictores_all.rds
# OUTPUT: output/modelos/{especie}/espacial/
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
  library(mgcv)
  library(MuMIn)
  library(jsonlite)
})

cat("\n========================================\n")
cat("  FASE 3: MODELO ESPACIAL\n")
cat("========================================\n\n")

datos_pa <- readRDS(CONFIG$paths$pa_data)
grid_data <- readRDS(CONFIG$paths$grid_predictores)

especies_gremios <- read_csv(CONFIG$paths$especies_gremios, show_col_types = FALSE) %>%
  filter(modelar == TRUE)

if (!is.null(CONFIG$especies$piloto)) {
  especies <- CONFIG$especies$piloto
} else {
  especies <- get_especies_pendientes(
    especies_gremios$especie, CONFIG$output$base, "ambiental"
  )
  # Only process species that have completed ambiental
  completadas <- setdiff(especies_gremios$especie, especies)
  especies <- completadas
}
especies <- setdiff(especies, CONFIG$especies$excluir)

# --- Funcion auxiliar: determinar k para GAM ---
calcular_k_gam <- function(n_pres) {
  k_max <- CONFIG$espacial$k_gam
  if (isTRUE(CONFIG$espacial$k_gam_adaptativo)) {
    k_adaptado <- min(k_max, floor(n_pres / 4))
    return(max(k_adaptado, 5))  # minimo razonable
  }
  return(k_max)
}

# --- Funcion auxiliar: ajustar modelo espacial por metodo ---
ajustar_espacial <- function(metodo, datos, k_gam) {
  if (metodo == "glm2") {
    glm(PA ~ X + Y + I(X^2) + I(Y^2) + I(X*Y), data = datos, family = binomial)
  } else if (metodo == "glm3") {
    glm(PA ~ X + Y + I(X^2) + I(Y^2) + I(X*Y) + I(X^3) + I(Y^3) + I(X^2*Y) + I(X*Y^2),
        data = datos, family = binomial)
  } else {
    gam(PA ~ s(X, Y, k = k_gam), data = datos, family = binomial, method = "ML")
  }
}

# --- Funcion de modelado espacial por especie ---
modelar_espacial_sp <- function(sp, datos_pa, grid_data) {

  sp_file <- str_replace_all(sp, " ", "_")
  dir_amb <- file.path(CONFIG$output$base, sp_file, "ambiental")
  dir_out <- file.path(CONFIG$output$base, sp_file, "espacial")
  dir.create(dir_out, recursive = TRUE, showWarnings = FALSE)

  if (!CONFIG$control$force_rerun &&
      checkpoint_exists(sp, CONFIG$output$base, "espacial")) {
    log_event("espacial", sp, "INFO", "Ya completado (checkpoint)")
    return(list(status = "skip", sp = sp))
  }

  if (!file.exists(file.path(dir_amb, "datos_entrenamiento.rds"))) {
    log_event("espacial", sp, "WARN", "Sin modelo ambiental")
    return(list(status = "skip", sp = sp))
  }

  # Preparar datos con coordenadas (columnas sp_ desde 01g)
  sp_col <- paste0("sp_", sp)
  if (!sp_col %in% names(datos_pa)) sp_col <- sp  # fallback sin prefijo
  datos_sp <- datos_pa %>%
    filter(muestreado == 1) %>%
    select(PA = all_of(sp_col), X, Y) %>%
    drop_na()

  n_pres <- sum(datos_sp$PA == 1)

  # O2: k adaptativo
  k_gam <- calcular_k_gam(n_pres)

  # Comparar modelos por AICc
  resultados_aicc <- tibble(metodo = character(), AICc = numeric())

  for (metodo in CONFIG$espacial$metodos) {
    modelo_temp <- tryCatch(ajustar_espacial(metodo, datos_sp, k_gam),
                            error = function(e) NULL)
    if (!is.null(modelo_temp)) {
      aicc_val <- AICc(modelo_temp)
      resultados_aicc <- bind_rows(resultados_aicc,
                                   tibble(metodo = metodo, AICc = aicc_val))
    }
  }

  if (nrow(resultados_aicc) == 0) {
    log_event("espacial", sp, "WARN", "Ningun modelo espacial convergio")
    return(list(status = "error", sp = sp))
  }

  mejor_metodo <- resultados_aicc %>% filter(AICc == min(AICc)) %>% pull(metodo)
  log_event("espacial", sp, "INFO",
            sprintf("Mejor: %s (AICc=%.1f, k_gam=%d)", mejor_metodo,
                    min(resultados_aicc$AICc), k_gam))

  # Ajustar modelo final
  modelo_final <- ajustar_espacial(mejor_metodo, datos_sp, k_gam)

  # Prediccion en grid
  if (!is.null(grid_data$malla_union)) {
    coords_pred <- grid_data$malla_union %>% select(X, Y)
    if (inherits(coords_pred, "sf")) coords_pred <- sf::st_drop_geometry(coords_pred)
  } else {
    coords_pred <- datos_pa %>% select(X, Y)
  }

  pred_prob <- predict(modelo_final, newdata = coords_pred, type = "response")
  pred_fav <- favorabilidad(pred_prob, datos_sp$PA)

  # Bootstrap espacial
  n_pred <- nrow(coords_pred)
  boot_matrix <- matrix(NA, nrow = n_pred, ncol = CONFIG$espacial$n_bootstrap)

  for (b in 1:CONFIG$espacial$n_bootstrap) {
    boot_idx <- sample(1:nrow(datos_sp), replace = TRUE)
    datos_boot <- datos_sp[boot_idx, ]
    modelo_boot <- tryCatch(ajustar_espacial(mejor_metodo, datos_boot, k_gam),
                            error = function(e) NULL)
    if (!is.null(modelo_boot)) {
      p_boot <- predict(modelo_boot, newdata = coords_pred, type = "response")
      boot_matrix[, b] <- favorabilidad(p_boot, datos_boot$PA)
    }
  }

  # Guardar
  predicciones <- tibble(F_esp_mean = rowMeans(boot_matrix, na.rm = TRUE),
                         F_esp_sd = apply(boot_matrix, 1, sd, na.rm = TRUE))
  write_csv(predicciones, file.path(dir_out, "predicciones.csv"))
  write_csv(resultados_aicc, file.path(dir_out, "comparacion_aicc.csv"))
  saveRDS(modelo_final, file.path(dir_out, "modelo_espacial.rds"))
  saveRDS(boot_matrix, file.path(dir_out, "bootstrap_samples.rds"))

  create_checkpoint(sp, CONFIG$output$base, "espacial",
                    metadata = list(metodo = mejor_metodo, k_gam = k_gam))

  log_event("espacial", sp, "INFO", "Completado")
  return(list(status = "ok", sp = sp, metodo = mejor_metodo))
}

# --- Ejecucion: paralela o secuencial ---
if (isTRUE(CONFIG$control$usar_parallel) && CONFIG$control$n_cores > 1) {
  suppressPackageStartupMessages({ library(future); library(future.apply) })
  plan(multisession, workers = CONFIG$control$n_cores)
  cat(sprintf("Ejecucion paralela: %d cores\n\n", CONFIG$control$n_cores))
  resultados <- future_lapply(especies, modelar_espacial_sp,
                              datos_pa = datos_pa, grid_data = grid_data,
                              future.seed = CONFIG$espacial$seed)
  plan(sequential)
} else {
  resultados <- list()
  for (i in seq_along(especies)) {
    sp <- especies[i]
    cat(sprintf("\n--- [%d/%d] %s ---\n", i, length(especies), sp))
    resultados[[i]] <- modelar_espacial_sp(sp, datos_pa, grid_data)
  }
}

n_ok <- sum(sapply(resultados, function(r) r$status == "ok"))
n_skip <- sum(sapply(resultados, function(r) r$status == "skip"))
n_err <- sum(sapply(resultados, function(r) r$status == "error"))
cat(sprintf("\n[OK] Fase 3: %d completadas, %d omitidas, %d errores\n", n_ok, n_skip, n_err))
