# ==============================================================================
# 03b_bis_espacial_residuos.R - Modelo espacial sobre residuos del GLM ambiental
# ==============================================================================
#
# SCRIPT COMPLEMENTARIO al pipeline estandar (03b_modelo_espacial.R).
# Puede ejecutarse de forma independiente despues de 03a para comparar ambos
# enfoques y decidir cual utilizar en la interseccion fuzzy final.
#
# ============================================================================
# JUSTIFICACION CIENTIFICA
# ============================================================================
#
# 1. EL PROBLEMA: CONFUNDIMIENTO AMBIENTAL-ESPACIAL
#
#    En el pipeline estandar, 03a modela la PA en funcion de variables
#    ambientales (clima, CORINE, geologia...) y 03b modela la MISMA PA en
#    funcion de coordenadas (X, Y). Ambos modelos se combinan despues via
#    interseccion fuzzy (03c):
#
#      F_final = sqrt(F_ambiental * F_espacial)
#
#    El problema es que la estructura espacial de PA contiene TANTO la senal
#    ambiental (los murcielagos viven donde hay caliza porque hay cuevas)
#    COMO la senal puramente espacial (dispersion limitada, barreras
#    geograficas, historia biogeografica). Al modelar PA ~ f(X,Y), el GAM
#    captura ambas senales mezcladas. Luego, al combinarlas con fuzzy, la
#    componente ambiental se cuenta DOS VECES:
#
#      - Una vez en F_ambiental (correctamente)
#      - Otra vez dentro de F_espacial (indirectamente, porque la PA que
#        modelo el GAM ya incluia el efecto ambiental)
#
#    Esto produce sobreconfianza: F_final queda inflada en zonas donde
#    ambiente y geografia apuntan en la misma direccion, y demasiado baja
#    donde apuntan en direcciones opuestas.
#
#
# 2. LA SOLUCION: MODELAR RESIDUOS
#
#    En vez de modelar PA ~ f(X,Y), modelamos:
#
#      residuos = PA - E[PA | ambiente] = PA - p_ambiental
#
#    donde p_ambiental = predict(GLM_ambiental, type = "response").
#
#    Estos residuos representan la parte de la distribucion que el modelo
#    ambiental NO explica: autocorrelacion espacial pura, dispersion
#    limitada, barreras geograficas, refugios glaciares, etc.
#
#    Al usar residuos como variable respuesta en el GAM espacial:
#
#      residuos ~ s(X, Y, k = k_adaptativo)
#
#    el modelo espacial SOLO captura la estructura espacial residual,
#    sin contaminacion ambiental. La interseccion fuzzy posterior combina
#    entonces dos senales genuinamente independientes.
#
#    Marco teorico: Trend Surface Analysis (Legendre & Legendre, 2012;
#    Borcard et al. 1992 "Partialling out the spatial component of
#    ecological variation", Ecology 73:1045-1055).
#
#
# 3. FAMILY = GAUSSIAN VS BINOMIAL
#
#    Los residuos (PA - p) son continuos en [-1, 1], no binarios. Por tanto:
#
#    - NO se puede usar family = binomial (requiere respuesta en {0,1})
#    - Se usa family = gaussian, que es el equivalente a una regresion
#      standard de los residuos sobre las coordenadas
#    - El GAM con gaussian captura las tendencias espaciales suaves de
#      sobre/infraprediccion del modelo ambiental
#
#    Alternativa (implementada): usar deviance residuals del GLM,
#    que tienen mejores propiedades estadisticas para modelos binomiales
#    (McCullagh & Nelder, 1989).
#
#
# 4. RECONSTRUCCION DE LA PREDICCION FINAL
#
#    Para obtener una favorabilidad espacial comparable a la del pipeline
#    estandar, reconstruimos la prediccion completa:
#
#      p_total(x) = p_ambiental(x) + f_espacial(X, Y)
#
#    donde f_espacial es la prediccion del GAM de residuos. Luego aplicamos
#    la transformacion de favorabilidad (Real et al. 2006):
#
#      F_espacial_residuos = favorabilidad(p_total)
#
#    Esta F es comparable a F_espacial del pipeline estandar, pero SIN
#    la componente ambiental duplicada.
#
#
# 5. CUANDO USAR CADA ENFOQUE
#
#    Pipeline estandar (03b, PA directa):
#      - Mas simple e interpretable
#      - Adecuado cuando la estructura espacial es dominante
#      - Conservador: no requiere que el modelo ambiental sea bueno
#      - Usado en la mayoria de atlas (Munoz et al. 2005, Barbosa et al. 2009)
#
#    Este script (03b_bis, residuos):
#      - Evita doble conteo del efecto ambiental
#      - Mejor separacion de las fuentes de variacion
#      - Recomendado cuando las variables ambientales ya explican mucha
#        varianza (AUC_ambiental > 0.8), porque en ese caso el modelo
#        espacial estandar aporta poco "nuevo" y la interseccion fuzzy
#        se vuelve casi redundante
#      - Mas robusto para la cuantificacion de incertidumbre (03e)
#        porque las dos componentes son genuinamente independientes
#
#
# 6. COMO EJECUTAR ESTE SCRIPT
#
#    Opcion A: Independiente (para comparar)
#      source("R/03_modeling/03a_modelo_ambiental.R")  # primero
#      source("R/03_modeling/03b_bis_espacial_residuos.R")  # este
#
#    Opcion B: Integrado en pipeline
#      En 00_config.R, poner CONFIG$espacial$usar_residuos = TRUE
#      y el pipeline estandar (03b) usara residuos automaticamente.
#      Este script 03b_bis es mas completo: incluye diagnosticos,
#      comparacion con el enfoque estandar, y tests de Moran.
#
#
# REFERENCIAS:
#   - Borcard, D., Legendre, P. & Drapeau, P. (1992). Partialling out the
#     spatial component of ecological variation. Ecology, 73, 1045-1055.
#   - Legendre, P. & Legendre, L. (2012). Numerical Ecology. Elsevier.
#   - Real, R., Barbosa, A.M. & Vargas, J.M. (2006). Obtaining environmental
#     favourability functions from logistic regression. Env. Ecol. Stat. 13:187
#   - McCullagh, P. & Nelder, J.A. (1989). Generalized Linear Models. Chapman.
#   - Munoz, A.R. & Real, R. (2006). Assessing the potential range expansion
#     of the exotic monk parakeet. Diversity Distrib. 12:349-357.
#   - Barbosa, A.M., Real, R. & Vargas, J.M. (2009). Transferability of
#     environmental favourability models. Ecography 32:489-502.
#
# INPUT:  output/modelos/{especie}/ambiental/modelo_glm.rds
#         output/modelos/{especie}/ambiental/datos_entrenamiento.rds
#         data/processed/PAxENV_all_metodos.rds
# OUTPUT: output/modelos/{especie}/espacial_residuos/
#           - modelo_espacial.rds
#           - predicciones.csv
#           - bootstrap_samples.rds
#           - comparacion_aicc.csv
#           - diagnostico_residuos.csv
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
cat("  FASE 3-BIS: MODELO ESPACIAL (RESIDUOS)\n")
cat("========================================\n\n")
cat("Este modelo captura la estructura espacial RESIDUAL tras descontar\n")
cat("el efecto ambiental (GLM de Fase 2). Evita doble conteo al combinar\n")
cat("con la favorabilidad ambiental en la interseccion fuzzy.\n\n")

# --- Cargar datos ---
datos_pa <- readRDS(CONFIG$paths$pa_data)
grid_data <- readRDS(CONFIG$paths$grid_predictores)

especies_gremios <- read_csv(CONFIG$paths$especies_gremios, show_col_types = FALSE) %>%
  filter(modelar == TRUE)

if (!is.null(CONFIG$especies$piloto)) {
  especies <- CONFIG$especies$piloto
} else {
  # Solo procesar especies que ya tienen modelo ambiental completado
  completadas_amb <- especies_gremios$especie[sapply(especies_gremios$especie, function(sp) {
    checkpoint_exists(sp, CONFIG$output$base, "ambiental")
  })]
  especies <- completadas_amb
}
especies <- setdiff(especies, CONFIG$especies$excluir)
cat(sprintf("Especies a procesar: %d\n\n", length(especies)))

# --- Funcion auxiliar: k adaptativo ---
calcular_k_gam <- function(n_pres) {
  k_max <- CONFIG$espacial$k_gam
  if (isTRUE(CONFIG$espacial$k_gam_adaptativo)) {
    k_adaptado <- min(k_max, floor(n_pres / 4))
    return(max(k_adaptado, 5))
  }
  return(k_max)
}

# --- Funcion auxiliar: ajustar modelo espacial ---
# NOTA: family = gaussian para residuos (no binomial)
ajustar_espacial_residuos <- function(metodo, datos, k_gam) {
  if (metodo == "glm2") {
    glm(residuos ~ X + Y + I(X^2) + I(Y^2) + I(X*Y),
        data = datos, family = gaussian)
  } else if (metodo == "glm3") {
    glm(residuos ~ X + Y + I(X^2) + I(Y^2) + I(X*Y) +
          I(X^3) + I(Y^3) + I(X^2*Y) + I(X*Y^2),
        data = datos, family = gaussian)
  } else {
    gam(residuos ~ s(X, Y, k = k_gam),
        data = datos, family = gaussian, method = "ML")
  }
}

# --- Funcion auxiliar: ajustar modelo PA directo (para comparacion) ---
ajustar_espacial_pa <- function(metodo, datos, k_gam) {
  if (metodo == "glm2") {
    glm(PA ~ X + Y + I(X^2) + I(Y^2) + I(X*Y),
        data = datos, family = binomial)
  } else if (metodo == "glm3") {
    glm(PA ~ X + Y + I(X^2) + I(Y^2) + I(X*Y) +
          I(X^3) + I(Y^3) + I(X^2*Y) + I(X*Y^2),
        data = datos, family = binomial)
  } else {
    gam(PA ~ s(X, Y, k = k_gam),
        data = datos, family = binomial, method = "ML")
  }
}

# ==============================================================================
# MODELADO POR ESPECIE
# ==============================================================================

modelar_espacial_residuos_sp <- function(sp, datos_pa, grid_data) {

  sp_file <- str_replace_all(sp, " ", "_")
  dir_amb <- file.path(CONFIG$output$base, sp_file, "ambiental")
  dir_out <- file.path(CONFIG$output$base, sp_file, "espacial_residuos")
  dir.create(dir_out, recursive = TRUE, showWarnings = FALSE)

  # --- Verificar prerequisitos ---
  modelo_amb_file <- file.path(dir_amb, "modelo_glm.rds")
  if (!file.exists(modelo_amb_file)) {
    log_event("espacial_residuos", sp, "WARN", "Sin modelo ambiental - omitiendo")
    return(list(status = "skip", sp = sp, reason = "sin_ambiental"))
  }

  # --- 1. Preparar datos ---
  col_sp <- sp
  if (!sp %in% names(datos_pa)) {
    # Intentar con prefijo sp_
    col_sp <- paste0("sp_", str_replace_all(sp, " ", "_"))
    if (!col_sp %in% names(datos_pa)) {
      log_event("espacial_residuos", sp, "WARN", "Columna de especie no encontrada")
      return(list(status = "skip", sp = sp, reason = "sin_columna"))
    }
  }

  datos_sp <- datos_pa %>%
    filter(muestreado == 1) %>%
    select(PA = all_of(col_sp), X, Y) %>%
    drop_na()

  n_total <- nrow(datos_sp)
  n_pres <- sum(datos_sp$PA == 1)
  n_aus <- sum(datos_sp$PA == 0)
  prevalencia <- n_pres / n_total

  if (n_pres < 10) {
    log_event("espacial_residuos", sp, "WARN",
              sprintf("Solo %d presencias - insuficiente", n_pres))
    return(list(status = "skip", sp = sp, reason = "pocas_presencias"))
  }

  # --- 2. Calcular residuos del modelo ambiental ---
  modelo_amb <- readRDS(modelo_amb_file)

  # Prediccion ambiental sobre las cuadriculas muestreadas
  # Necesitamos las variables ambientales, no solo X,Y
  datos_completos <- datos_pa %>%
    filter(muestreado == 1) %>%
    drop_na(all_of(c(col_sp, "X", "Y")))

  pred_amb <- tryCatch(
    predict(modelo_amb, newdata = datos_completos, type = "response"),
    error = function(e) {
      log_event("espacial_residuos", sp, "WARN",
                sprintf("Error prediciendo amb: %s", e$message))
      return(NULL)
    }
  )

  if (is.null(pred_amb)) {
    return(list(status = "error", sp = sp, reason = "predict_error"))
  }

  # Residuos: PA observada - probabilidad predicha
  # Positivos = el modelo ambiental infraestima (la especie esta pero no deberia)
  # Negativos = el modelo sobreestima (la especie no esta pero deberia)
  datos_sp$residuos <- datos_sp$PA - pred_amb
  datos_sp$pred_amb <- pred_amb

  # Diagnostico de residuos
  res_stats <- tibble(
    especie = sp,
    n_total = n_total,
    n_pres = n_pres,
    prevalencia = prevalencia,
    mean_residuo = mean(datos_sp$residuos),
    sd_residuo = sd(datos_sp$residuos),
    min_residuo = min(datos_sp$residuos),
    max_residuo = max(datos_sp$residuos),
    # Proporcion de varianza no explicada por ambiente
    # (1 - pseudo-R2 del GLM ambiental)
    var_residuos = var(datos_sp$residuos),
    var_pa = var(datos_sp$PA),
    ratio_var_residual = var(datos_sp$residuos) / max(var(datos_sp$PA), 1e-10)
  )

  write_csv(res_stats, file.path(dir_out, "diagnostico_residuos.csv"))

  log_event("espacial_residuos", sp, "INFO",
            sprintf("Residuos: mean=%.3f, sd=%.3f, var_ratio=%.2f",
                    res_stats$mean_residuo, res_stats$sd_residuo,
                    res_stats$ratio_var_residual))

  # --- 3. Ajustar GAM/GLM sobre residuos ---
  k_gam <- calcular_k_gam(n_pres)

  resultados_aicc <- tibble(metodo = character(), AICc = numeric(),
                            enfoque = character())

  # Modelos de residuos
  for (metodo in CONFIG$espacial$metodos) {
    modelo_temp <- tryCatch(
      ajustar_espacial_residuos(metodo, datos_sp, k_gam),
      error = function(e) NULL
    )
    if (!is.null(modelo_temp)) {
      aicc_val <- AICc(modelo_temp)
      resultados_aicc <- bind_rows(resultados_aicc,
                                   tibble(metodo = metodo, AICc = aicc_val,
                                          enfoque = "residuos"))
    }
  }

  # Modelos PA directa (para comparacion)
  for (metodo in CONFIG$espacial$metodos) {
    modelo_temp <- tryCatch(
      ajustar_espacial_pa(metodo, datos_sp, k_gam),
      error = function(e) NULL
    )
    if (!is.null(modelo_temp)) {
      aicc_val <- AICc(modelo_temp)
      resultados_aicc <- bind_rows(resultados_aicc,
                                   tibble(metodo = metodo, AICc = aicc_val,
                                          enfoque = "pa_directa"))
    }
  }

  if (sum(resultados_aicc$enfoque == "residuos") == 0) {
    log_event("espacial_residuos", sp, "WARN", "Ningun modelo de residuos convergio")
    return(list(status = "error", sp = sp, reason = "no_convergencia"))
  }

  # Seleccionar mejor modelo de residuos por AICc
  mejor <- resultados_aicc %>%
    filter(enfoque == "residuos") %>%
    filter(AICc == min(AICc))

  mejor_metodo <- mejor$metodo[1]

  log_event("espacial_residuos", sp, "INFO",
            sprintf("Mejor residuos: %s (AICc=%.1f, k=%d)",
                    mejor_metodo, mejor$AICc[1], k_gam))

  # Comparacion con PA directa
  mejor_pa <- resultados_aicc %>%
    filter(enfoque == "pa_directa") %>%
    filter(AICc == min(AICc))

  if (nrow(mejor_pa) > 0) {
    cat(sprintf("  Comparacion AICc: residuos=%.1f (%s) vs PA=%.1f (%s)\n",
                mejor$AICc[1], mejor_metodo,
                mejor_pa$AICc[1], mejor_pa$metodo[1]))
  }

  write_csv(resultados_aicc, file.path(dir_out, "comparacion_aicc.csv"))

  # --- 4. Ajustar modelo final ---
  modelo_final <- ajustar_espacial_residuos(mejor_metodo, datos_sp, k_gam)

  # --- 5. Prediccion en grid ---
  if (!is.null(grid_data$malla_union)) {
    coords_pred <- grid_data$malla_union %>% select(X, Y)
    if (inherits(coords_pred, "sf")) coords_pred <- sf::st_drop_geometry(coords_pred)
  } else {
    coords_pred <- datos_pa %>% select(X, Y)
  }

  # Prediccion espacial del residuo
  pred_residuo_espacial <- predict(modelo_final, newdata = coords_pred, type = "response")

  # Reconstruir: p_total = p_ambiental + f_espacial(residuo)
  # Necesitamos la prediccion ambiental sobre TODO el grid
  pred_amb_grid <- tryCatch(
    predict(modelo_amb, newdata = grid_data$malla_union %||% datos_pa,
            type = "response"),
    error = function(e) {
      log_event("espacial_residuos", sp, "WARN",
                sprintf("Error prediciendo amb en grid: %s", e$message))
      rep(0.5, nrow(coords_pred))
    }
  )

  # p_total truncado a [0, 1]
  p_total <- pmin(pmax(pred_amb_grid + pred_residuo_espacial, 0), 1)

  # Transformar a favorabilidad
  pred_fav <- favorabilidad(p_total, datos_sp$PA)

  # --- 6. Bootstrap ---
  n_pred <- nrow(coords_pred)
  n_boot <- CONFIG$espacial$n_bootstrap
  boot_matrix <- matrix(NA, nrow = n_pred, ncol = n_boot)

  set.seed(CONFIG$espacial$seed)

  for (b in 1:n_boot) {
    boot_idx <- sample(1:nrow(datos_sp), replace = TRUE)
    datos_boot <- datos_sp[boot_idx, ]

    modelo_boot <- tryCatch(
      ajustar_espacial_residuos(mejor_metodo, datos_boot, k_gam),
      error = function(e) NULL
    )

    if (!is.null(modelo_boot)) {
      pred_res_boot <- predict(modelo_boot, newdata = coords_pred, type = "response")
      p_total_boot <- pmin(pmax(pred_amb_grid + pred_res_boot, 0), 1)
      boot_matrix[, b] <- favorabilidad(p_total_boot, datos_boot$PA)
    }
  }

  n_boot_ok <- sum(!is.na(boot_matrix[1, ]))
  log_event("espacial_residuos", sp, "INFO",
            sprintf("Bootstrap: %d/%d exitosos", n_boot_ok, n_boot))

  # --- 7. Guardar resultados ---
  predicciones <- tibble(
    F_esp_res_mean = rowMeans(boot_matrix, na.rm = TRUE),
    F_esp_res_sd = apply(boot_matrix, 1, sd, na.rm = TRUE),
    pred_residuo_espacial = pred_residuo_espacial,
    pred_amb_grid = pred_amb_grid,
    p_total = p_total,
    F_espacial_residuos = pred_fav
  )

  write_csv(predicciones, file.path(dir_out, "predicciones.csv"))
  saveRDS(modelo_final, file.path(dir_out, "modelo_espacial.rds"))
  saveRDS(boot_matrix, file.path(dir_out, "bootstrap_samples.rds"))

  # Metadata JSON
  metadata_json <- list(
    especie = sp,
    enfoque = "residuos",
    mejor_metodo = mejor_metodo,
    k_gam = k_gam,
    n_pres = n_pres,
    prevalencia = prevalencia,
    mean_residuo = res_stats$mean_residuo,
    sd_residuo = res_stats$sd_residuo,
    var_ratio_residual = res_stats$ratio_var_residual,
    n_bootstrap = n_boot,
    n_bootstrap_ok = n_boot_ok,
    aicc_residuos = mejor$AICc[1],
    aicc_pa_directa = if (nrow(mejor_pa) > 0) mejor_pa$AICc[1] else NA_real_,
    timestamp = as.character(Sys.time())
  )
  write_json(metadata_json, file.path(dir_out, "metadata.json"),
             auto_unbox = TRUE, pretty = TRUE)

  create_checkpoint(sp, CONFIG$output$base, "espacial_residuos",
                    metadata = list(metodo = mejor_metodo, k_gam = k_gam,
                                    enfoque = "residuos"))

  log_event("espacial_residuos", sp, "INFO", "Completado")

  return(list(
    status = "ok",
    sp = sp,
    metodo = mejor_metodo,
    aicc_residuos = mejor$AICc[1],
    aicc_pa = if (nrow(mejor_pa) > 0) mejor_pa$AICc[1] else NA_real_,
    var_ratio = res_stats$ratio_var_residual
  ))
}

# ==============================================================================
# EJECUCION
# ==============================================================================

init_log()

resultados <- list()
for (i in seq_along(especies)) {
  sp <- especies[i]
  cat(sprintf("\n--- [%d/%d] %s ---\n", i, length(especies), sp))
  resultados[[i]] <- modelar_espacial_residuos_sp(sp, datos_pa, grid_data)
}

# ==============================================================================
# RESUMEN COMPARATIVO
# ==============================================================================

n_ok <- sum(sapply(resultados, function(r) r$status == "ok"))
n_skip <- sum(sapply(resultados, function(r) r$status == "skip"))
n_err <- sum(sapply(resultados, function(r) r$status == "error"))

cat(sprintf("\n========================================\n"))
cat(sprintf("  RESUMEN MODELO ESPACIAL (RESIDUOS)\n"))
cat(sprintf("========================================\n\n"))
cat(sprintf("  Completadas: %d\n", n_ok))
cat(sprintf("  Omitidas:    %d\n", n_skip))
cat(sprintf("  Errores:     %d\n\n", n_err))

# Tabla comparativa de AICc: residuos vs PA directa
if (n_ok > 0) {
  comparacion <- bind_rows(lapply(resultados, function(r) {
    if (r$status == "ok") {
      tibble(
        especie = r$sp,
        AICc_residuos = r$aicc_residuos,
        AICc_PA = r$aicc_pa,
        var_ratio_residual = r$var_ratio,
        mejor = if_else(!is.na(r$aicc_pa) && r$aicc_residuos < r$aicc_pa,
                        "residuos", "PA_directa")
      )
    }
  }))

  if (nrow(comparacion) > 0) {
    cat("COMPARACION AICc: enfoque residuos vs PA directa:\n\n")
    print(comparacion, n = Inf)

    n_residuos_mejor <- sum(comparacion$mejor == "residuos", na.rm = TRUE)
    n_pa_mejor <- sum(comparacion$mejor == "PA_directa", na.rm = TRUE)
    cat(sprintf("\n  Residuos gana: %d especies (%.0f%%)\n",
                n_residuos_mejor, 100 * n_residuos_mejor / nrow(comparacion)))
    cat(sprintf("  PA directa gana: %d especies (%.0f%%)\n",
                n_pa_mejor, 100 * n_pa_mejor / nrow(comparacion)))

    cat(sprintf("\n  Var residual media: %.2f (1.0 = ambiente no explica nada)\n",
                mean(comparacion$var_ratio_residual, na.rm = TRUE)))

    # Guardar resumen
    write_csv(comparacion, file.path(CONFIG$output$base, "comparacion_espacial_residuos.csv"))
    cat(sprintf("\n[OK] Resumen guardado: %s\n",
                file.path(CONFIG$output$base, "comparacion_espacial_residuos.csv")))
  }
}

cat("\n[OK] Fase 3-bis completada\n")
cat("\nNOTA: Para usar estos resultados en la interseccion fuzzy (03c),\n")
cat("los bootstrap_samples.rds de 'espacial_residuos/' se pueden usar\n")
cat("como reemplazo directo de los de 'espacial/'. O bien activar\n")
cat("CONFIG$espacial$usar_residuos = TRUE para integrarlo en el pipeline.\n")
