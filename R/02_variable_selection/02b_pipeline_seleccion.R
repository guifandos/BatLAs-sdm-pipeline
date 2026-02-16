# ==============================================================================
# 02b_pipeline_seleccion.R - Pipeline de seleccion de variables (7 fases)
# ==============================================================================
#
# Pipeline completo de seleccion de variables ambientales con:
#   1. Preseleccion por gremio (pool ecologico)
#   2. Limpieza basica (NAs, varianza, separacion perfecta)
#   3. select07 ponderado + salvaguarda 1
#   4. VIF iterativo ponderado
#   5. Control muestral N/p + salvaguarda 2
#   6. Validacion ecologica + salvaguarda 3
#   7. Validacion predictiva (AUC, TSS, Kappa)
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

# --- Carga condicional de dependencias ---
# Solo cargamos CONFIG y funciones si no estan ya en el entorno.
# Esto permite usar el script tanto de forma aislada como desde run_pipeline.R
# sin duplicar cargas.
if (!exists("CONFIG")) source("R/00_setup/00_config.R")
if (!exists("annotate_variables_by_guild")) source("R/02_variable_selection/02a_funciones_gremios.R")
if (!exists("normalizar_id_tabla")) source("R/utils/utils_checkpoints.R")

suppressPackageStartupMessages({
  library(tidyverse)
  library(tibble)
  library(car)
  library(jsonlite)
  library(mgcv)
})

if (requireNamespace("modEvA", quietly = TRUE)) {
  library(modEvA)
  use_modeva <- TRUE
} else {
  use_modeva <- FALSE
}

# ==============================================================================
# UTILIDADES
# ==============================================================================

#' Calcula el AIC de un GLM cuadratico univariado
#' Se usa para rankear variables por capacidad explicativa individual
calc_univariate_aic <- function(var, response, family = "binomial", weights = NULL) {
  tryCatch({
    m <- glm(response ~ poly(var, 2), family = family, weights = weights)
    return(AIC(m))
  }, error = function(e) NA_real_)
}

# ==============================================================================
# FASE 1: PRESELECCION POR GREMIO
# ==============================================================================
# POR QUE: Los murcielagos tienen requerimientos ecologicos fuertemente
# ligados a su gremio de refugio (cavernicola, arboricola, etc.) y de
# alimentacion (forestal, ripario, etc.). La preseleccion por gremio reduce
# la dimensionalidad de forma ecologicamente informada: descarta a priori
# variables que no tienen relacion biologica con la especie (p.ej., variables
# rupicolas para una especie arboricola). Esto mejora la interpretabilidad
# del modelo resultante y evita encontrar correlaciones espurias con
# variables ecologicamente irrelevantes.
# ==============================================================================

fase1_preseleccion_gremio <- function(df, especie, especies_gremios, response_col = "presencia") {
  varnames <- setdiff(names(df), response_col)
  var_info <- annotate_variables_by_guild(especie, varnames, especies_gremios)
  vars_permitidas <- var_info %>% filter(prioridad > 0) %>% pull(variable)
  data_out <- df[, c(response_col, vars_permitidas), drop = FALSE]
  especie_info <- especies_gremios %>% filter(especie == !!especie)
  n_excluidas <- sum(var_info$prioridad == 0)
  message(sprintf("  FASE 1: Pool inicial = %d variables (%d excluidas a priori)",
                  length(vars_permitidas), n_excluidas))
  list(data = data_out, var_info = var_info %>% filter(prioridad > 0),
       especie_info = especie_info,
       vars_excluidas = var_info %>% filter(prioridad == 0))
}

# ==============================================================================
# FASE 2: LIMPIEZA BASICA
# ==============================================================================
# POR QUE: Antes de aplicar metodos de seleccion multivariante, es necesario
# eliminar variables que violarian los supuestos estadisticos del GLM:
#   - NAs > 30%: demasiados datos faltantes reducen el tamano efectivo de
#     muestra y sesgan las estimaciones. El umbral del 30% es conservador.
#   - Varianza cero o cuasi-cero: si una variable es constante, no puede
#     discriminar entre presencia y ausencia (pendiente indefinida en GLM).
#   - Separacion perfecta (o cuasi-completa): cuando una variable predice
#     perfectamente la respuesta, el GLM no converge (coeficientes -> Inf).
#     Estas variables son artefactos o casos degenerados, no predictores
#     fiables para prediccion espacial.
# ==============================================================================

fase2_limpieza_basica <- function(data, response_col, var_info,
                                  max_na = 0.3) {
  vars <- setdiff(names(data), response_col)
  response <- data[[response_col]]
  removed <- tibble(variable = character(), phase = character(), reason = character())

  for (v in vars) {
    x <- data[[v]]
    drop <- FALSE; reason <- NA_character_

    # Excluir variables con >30% de valores faltantes
    if (mean(is.na(x)) > max_na) { drop <- TRUE; reason <- paste0("NA > ", max_na * 100, "%") }
    # Excluir variables categoricas (el pipeline usa GLM numerico)
    if (!drop && (is.factor(x) || is.character(x))) { drop <- TRUE; reason <- "variable_categorica" }
    if (!drop && !is.numeric(x)) { drop <- TRUE; reason <- "no_numerica" }
    # Excluir variables con varianza cero o casi cero
    if (!drop) {
      var_x <- var(x, na.rm = TRUE)
      if (is.na(var_x) || var_x < 1e-10) { drop <- TRUE; reason <- "varianza_cero" }
    }
    if (!drop && length(unique(x[!is.na(x)])) == 1) { drop <- TRUE; reason <- "constante" }
    # Excluir variables que causan separacion perfecta en GLM univariado
    if (!drop) {
      test_glm <- tryCatch({ glm(response ~ x, family = binomial); FALSE },
                            warning = function(w) grepl("perfect", tolower(w$message)),
                            error = function(e) TRUE)
      if (test_glm) { drop <- TRUE; reason <- "separacion_perfecta" }
    }
    if (drop) {
      removed <- bind_rows(removed, tibble(variable = v, phase = "fase2", reason = reason))
      data[[v]] <- NULL
    }
  }
  vars_kept <- setdiff(names(data), response_col)
  var_info <- var_info %>% filter(variable %in% vars_kept)
  message(sprintf("  FASE 2: %d variables eliminadas por limpieza basica", nrow(removed)))
  list(data = data, var_info = var_info, removed = removed)
}

# ==============================================================================
# FASE 3: SELECT07 PONDERADO + SALVAGUARDA 1
# ==============================================================================
# POR QUE - select07 ponderado: Implementa el metodo de Munoz & Real (2006)
# para seleccion de variables basada en correlacion. La idea central es
# recorrer las variables ordenadas por importancia (AIC univariado) e ir
# anadiendo solo aquellas cuya correlacion con las ya seleccionadas no supere
# un umbral (por defecto r = 0.8). Esto elimina redundancia preservando las
# variables mas informativas. La ponderacion por prioridad de gremio es
# nuestra extension: al ordenar primero por prioridad ecologica y despues
# por AIC, las variables ecologicamente esenciales para la especie tienen
# preferencia de entrada, asegurando que el modelo resultante sea
# ecologicamente interpretable y no solo estadisticamente optimo.
#
# POR QUE - Salvaguarda 1 (rescate de variables de gremio): Tras select07
# puede ocurrir que variables de gremio (prioridad >= 2) queden excluidas
# por estar correlacionadas con otras variables de menor interes ecologico
# que entraron primero. Para evitar perder predictores ecologicamente
# esenciales, se rescatan hasta min_gremio variables de gremio (las de
# mejor AIC entre las excluidas), reintroduciendolas en el conjunto
# seleccionado.
# ==============================================================================

#' Nucleo del algoritmo select07 (Munoz & Real 2006)
#'
#' Recorre las variables en un orden dado (sequence) y selecciona solo aquellas
#' cuya correlacion (Spearman) con las previamente seleccionadas esta por
#' debajo del umbral (threshold).
select07_core <- function(X, y, family = "binomial", univar = "glm2",
                          threshold = NULL, method = "spearman",
                          sequence = NULL, weights = NULL) {
  if (is.null(threshold)) threshold <- CONFIG$seleccion$correlation_threshold
  var.imp <- function(variable, response, univar, family, weights) {
    m1 <- switch(univar,
      glm1 = glm(response ~ variable, family = family, weights = weights),
      glm2 = glm(response ~ poly(variable, 2), family = family, weights = weights),
      gam = mgcv::gam(response ~ s(variable, k = 4), family = family, weights = weights))
    AIC(m1)
  }
  cm <- tryCatch(cor(X, method = method, use = "pairwise.complete.obs"),
                 error = function(e) cor(X, method = "pearson", use = "pairwise.complete.obs"))
  diag(cm)[is.na(diag(cm))] <- 1
  cm[is.na(cm)] <- 0

  if (is.null(sequence)) {
    imp <- apply(X, 2, var.imp, response = y, family = family,
                 univar = univar, weights = weights)
    sort.imp <- names(sort(imp))
  } else {
    sort.imp <- sequence
  }

  j <- 0
  selected.vars <- character(0)
  repeat {
    j <- j + 1
    i <- sort.imp[j]
    if (j == 1) {
      selected.vars <- i
    } else {
      correlations <- abs(cm[i, selected.vars])
      if (all(correlations < threshold, na.rm = TRUE) && !any(is.na(correlations))) {
        selected.vars <- c(selected.vars, i)
      }
    }
    if (j == length(sort.imp)) break
  }
  return(selected.vars)
}

#' select07 con ponderacion por prioridad ecologica
#'
#' Ordena las variables primero por prioridad de gremio (descendente) y
#' despues por AIC univariado (ascendente, menor AIC = mejor). Este orden
#' garantiza que las variables ecologicamente relevantes se evaluen primero
#' y tengan preferencia en la seleccion.
select07_weighted <- function(X, y, var_info, threshold = NULL, ...) {
  if (is.null(threshold)) threshold <- CONFIG$seleccion$correlation_threshold
  aic_univar <- sapply(names(X), function(v) calc_univariate_aic(X[[v]], y))
  var_info <- var_info %>% mutate(AIC_univar = aic_univar[variable])
  sequence <- var_info %>% arrange(desc(prioridad), AIC_univar) %>% pull(variable)
  selected <- select07_core(X = X, y = y, threshold = threshold, sequence = sequence, ...)
  var_info <- var_info %>% mutate(selected = variable %in% selected)
  list(selected_vars = selected, var_info = var_info)
}

#' Fase 3 completa: select07 ponderado + Salvaguarda 1
fase3_select_weighted <- function(data, response_col, var_info,
                                  threshold = NULL, min_gremio = 3) {
  if (is.null(threshold)) threshold <- CONFIG$seleccion$correlation_threshold
  vars <- setdiff(names(data), response_col)
  X <- data[, vars, drop = FALSE]
  y <- data[[response_col]]
  result <- select07_weighted(X, y, var_info, threshold = threshold)
  selected_vars <- result$selected_vars
  var_info <- result$var_info

  # --- SALVAGUARDA 1: Rescatar variables de gremio ---
  # Si select07 dejo menos de min_gremio variables de gremio (prioridad >= 2),
  # rescatamos las mejores (por AIC) entre las excluidas. Esto evita que el
  # modelo pierda predictores ecologicamente esenciales solo porque estaban
  # correlacionadas con variables de menor relevancia ecologica que entraron
  # primero en select07.
  n_gremio <- sum(var_info$selected & var_info$prioridad >= 2)
  if (n_gremio < min_gremio) {
    candidatas <- var_info %>% filter(!selected, prioridad >= 2) %>%
      arrange(AIC_univar) %>% head(min_gremio - n_gremio)
    if (nrow(candidatas) > 0) {
      selected_vars <- c(selected_vars, candidatas$variable)
      var_info <- var_info %>% mutate(selected = variable %in% selected_vars)
      message(sprintf("    SALVAGUARDA 1: Rescatadas %d variables de gremio", nrow(candidatas)))
    }
  }
  removed <- var_info %>% filter(!selected) %>%
    transmute(variable, phase = "fase3", reason = "no_seleccionada_select07")
  var_info_out <- var_info %>% filter(selected)
  data_out <- data[, c(response_col, var_info_out$variable), drop = FALSE]
  message(sprintf("  FASE 3: select07 -> %d variables (threshold=%.2f)",
                  nrow(var_info_out), threshold))
  list(data = data_out, var_info = var_info_out, removed = removed)
}

# ==============================================================================
# FASE 4: VIF ITERATIVO PONDERADO
# ==============================================================================
# POR QUE: Aunque select07 elimina pares altamente correlacionados, la
# multicolinealidad puede persistir en combinaciones multivariantes (una
# variable puede ser una combinacion lineal de varias otras). El VIF
# (Variance Inflation Factor) detecta esta multicolinealidad residual:
# un VIF > 10 indica que la varianza del coeficiente de esa variable esta
# inflada al menos 10x por la colinealidad, haciendo el coeficiente
# inestable y poco fiable. El umbral de 10 es el estandar mas extendido
# en ecologia y estadistica aplicada (Dormann et al. 2013).
#
# El algoritmo es iterativo y ponderado: en cada paso elimina la variable
# con mayor VIF, pero prioriza eliminar variables de baja prioridad
# ecologica (prioridad 1 antes que 2, 2 antes que 3-4). Asi se conservan
# los predictores ecologicamente relevantes siempre que sea posible.
# ==============================================================================

fase4_vif_ponderado <- function(data, response_col, var_info,
                                vif_threshold = NULL, max_iter = 50) {
  if (is.null(vif_threshold)) vif_threshold <- CONFIG$seleccion$vif_threshold
  vars <- setdiff(names(data), response_col)
  response <- data[[response_col]]
  removed <- tibble(variable = character(), phase = character(),
                    reason = character(), vif = numeric(), prioridad = integer())
  conflicto_obligatorias <- FALSE
  iter <- 0

  repeat {
    iter <- iter + 1
    if (length(vars) <= 2 || iter > max_iter) break
    X <- data[, vars, drop = FALSE]
    vif_vals <- tryCatch({ car::vif(lm(response ~ ., data = cbind(response, X))) },
                         error = function(e) rep(1, length(vars)))
    if (is.matrix(vif_vals)) vif_vals <- vif_vals[, "GVIF"]
    names(vif_vals) <- vars
    if (max(vif_vals, na.rm = TRUE) <= vif_threshold) break

    # Eliminar la variable con mayor VIF, priorizando las de menor relevancia
    # ecologica (prioridad 1 primero, luego 2, etc.)
    problem_vars <- names(vif_vals)[vif_vals > vif_threshold]
    var_info_problem <- var_info %>% filter(variable %in% problem_vars) %>%
      mutate(vif = vif_vals[variable])
    cand_p1 <- var_info_problem %>% filter(prioridad == 1)
    if (nrow(cand_p1) > 0) {
      drop_var <- cand_p1 %>% slice_max(vif, n = 1) %>% pull(variable)
    } else {
      cand_p2 <- var_info_problem %>% filter(prioridad == 2)
      if (nrow(cand_p2) > 0) {
        drop_var <- cand_p2 %>% slice_max(vif, n = 1) %>% pull(variable)
      } else {
        # Conflicto: todas las variables problematicas son de alta prioridad.
        # Eliminamos la de peor AIC entre ellas.
        conflicto_obligatorias <- TRUE
        drop_var <- var_info_problem %>% arrange(desc(AIC_univar)) %>%
          slice(1) %>% pull(variable)
      }
    }
    drop_info <- var_info %>% filter(variable == drop_var)
    removed <- bind_rows(removed, tibble(variable = drop_var, phase = "fase4",
                                          reason = "VIF_colinealidad",
                                          vif = vif_vals[drop_var],
                                          prioridad = drop_info$prioridad))
    vars <- setdiff(vars, drop_var)
    data[[drop_var]] <- NULL
  }

  if (length(vars) > 1) {
    X <- data[, vars, drop = FALSE]
    vif_final <- tryCatch({ car::vif(lm(response ~ ., data = cbind(response, X))) },
                          error = function(e) rep(NA_real_, length(vars)))
    if (is.matrix(vif_final)) vif_final <- vif_final[, "GVIF"]
    names(vif_final) <- vars
    var_info <- var_info %>% filter(variable %in% vars) %>%
      mutate(VIF_final = vif_final[variable])
    max_vif_final <- max(vif_final, na.rm = TRUE)
  } else {
    var_info <- var_info %>% filter(variable %in% vars)
    max_vif_final <- NA
  }
  message(sprintf("  FASE 4: VIF iterativo -> %d variables (VIF max = %.2f)",
                  nrow(var_info), max_vif_final))
  list(data = data, var_info = var_info, removed = removed,
       conflicto_colinealidad_obligatorias = conflicto_obligatorias)
}

# ==============================================================================
# FASE 5: CONTROL MUESTRAL + SALVAGUARDA 2
# ==============================================================================
# POR QUE - Ratio N/p >= 8 (Harrell's rule): En regresion logistica, el
# numero de parametros estimables esta limitado por el numero de eventos
# (presencias). Si se incluyen demasiadas variables para pocas presencias,
# el modelo sobreajusta: los coeficientes son inestables y la capacidad
# predictiva fuera de muestra colapsa. La regla de Harrell (1 parametro
# por cada 8-10 eventos) es el estandar mas conservador. Con GLM
# cuadraticos (2 parametros por variable), se necesitan ~16 presencias
# por variable. Aqui usamos ratio_Np = 8 con GLM lineales.
#
# Para especies con pocas presencias (30-60), se limita a midsize_max_vars
# variables (modelo simple) para evitar sobreajuste.
#
# POR QUE - Salvaguarda 2 (swap de variables en modelos simples): Cuando el
# modelo simple tiene un limite estricto de variables y las seleccionadas
# incluyen variables de baja prioridad ecologica (prioridad 1) pero faltan
# variables de gremio (prioridad >= 2), se intercambian: se sustituyen las
# de menor prioridad por variables de gremio con mejor AIC. Esto preserva
# la relevancia ecologica del modelo incluso bajo restricciones muestrales.
# ==============================================================================

fase5_control_muestral <- function(data, response_col, var_info,
                                   min_presences = NULL, midsize_max_vars = NULL,
                                   ratio_Np = NULL, min_gremio_final = NULL) {
  if (is.null(min_presences)) min_presences <- CONFIG$seleccion$min_presencias
  if (is.null(midsize_max_vars)) midsize_max_vars <- CONFIG$seleccion$midsize_max_vars
  if (is.null(ratio_Np)) ratio_Np <- CONFIG$seleccion$ratio_Np
  if (is.null(min_gremio_final)) min_gremio_final <- CONFIG$seleccion$min_gremio_final

  vars <- setdiff(names(data), response_col)
  response <- data[[response_col]]
  n_pres <- sum(response == 1)
  removed <- tibble(variable = character(), phase = character(), reason = character())

  # Si hay menos de min_presences (30), la especie no es modelizable
  if (n_pres < min_presences) {
    message(sprintf("  FASE 5: N=%d < %d -> NO MODELIZAR", n_pres, min_presences))
    return(list(data = data[, response_col, drop = FALSE], var_info = var_info[0, ],
                removed = tibble(variable = vars, phase = "fase5", reason = "insuficientes_presencias"),
                status = "no_modelizar", n_pres = n_pres, alerts = c("insuficientes_presencias")))
  }

  # Modelo simple: 30-59 presencias -> limitar a midsize_max_vars variables
  if (n_pres < 60) {
    status <- "modelo_simple"
    if (length(vars) > midsize_max_vars) {
      var_info_ord <- var_info %>% arrange(desc(prioridad), AIC_univar)
      keep_vars <- head(var_info_ord$variable, midsize_max_vars)

      # --- SALVAGUARDA 2: Swap de variables de baja prioridad por gremio ---
      # Si entre las variables seleccionadas para el modelo simple hay pocas
      # de gremio (< min_gremio_final), sustituimos variables de prioridad 1
      # (las de peor AIC) por variables de gremio que quedaron fuera (las de
      # mejor AIC). Esto asegura que el modelo conserve relevancia ecologica
      # aun cuando el tamano muestral fuerza un modelo parsimonioso.
      n_gremio_keep <- sum(var_info$variable %in% keep_vars & var_info$prioridad >= 2)
      if (n_gremio_keep < min_gremio_final) {
        n_faltan <- min_gremio_final - n_gremio_keep
        cand_gremio <- var_info %>% filter(prioridad >= 2, !variable %in% keep_vars) %>%
          arrange(AIC_univar) %>% head(n_faltan)
        cand_eliminar <- var_info %>% filter(prioridad == 1, variable %in% keep_vars) %>%
          arrange(desc(AIC_univar)) %>% head(n_faltan)
        if (nrow(cand_gremio) > 0 && nrow(cand_eliminar) > 0) {
          keep_vars <- setdiff(keep_vars, cand_eliminar$variable)
          keep_vars <- c(keep_vars, cand_gremio$variable)
          message(sprintf("    SALVAGUARDA 2: Swap de %d variables", nrow(cand_gremio)))
        }
      }
      drop_vars <- setdiff(vars, keep_vars)
      removed <- tibble(variable = drop_vars, phase = "fase5", reason = "modelo_simple_max_vars")
      vars <- keep_vars
      var_info <- var_info %>% filter(variable %in% vars)
    }
    data_out <- data[, c(response_col, vars), drop = FALSE]
    message(sprintf("  FASE 5: Modelo simple (N=%d) -> %d variables", n_pres, length(vars)))
  } else {
    # Modelo completo: >= 60 presencias -> limitar segun ratio N/p
    status <- "modelo_completo"
    max_vars <- floor(n_pres / ratio_Np)
    while (length(vars) > max_vars) {
      cand <- var_info %>% arrange(prioridad, desc(AIC_univar))
      n_gremio <- sum(var_info$prioridad >= 2)
      if (n_gremio > min_gremio_final) {
        cand_drop <- cand %>% filter(prioridad == 1)
        if (nrow(cand_drop) == 0) cand_drop <- cand
      } else { cand_drop <- cand }
      drop_var <- cand_drop$variable[1]
      removed <- bind_rows(removed, tibble(variable = drop_var, phase = "fase5", reason = "ajuste_Np"))
      vars <- setdiff(vars, drop_var)
      var_info <- var_info %>% filter(variable %in% vars)
    }
    data_out <- data[, c(response_col, vars), drop = FALSE]
    message(sprintf("  FASE 5: Modelo completo (N=%d, ratio=%d) -> %d variables",
                    n_pres, ratio_Np, length(vars)))
  }
  list(data = data_out, var_info = var_info, removed = removed,
       status = status, n_pres = n_pres,
       alerts = if (status == "modelo_simple") c("modelo_simple_30_60") else character(0))
}

# ==============================================================================
# FASE 6: VALIDACION ECOLOGICA + SALVAGUARDA 3
# ==============================================================================
# POR QUE: Despues de todas las fases estadisticas (limpieza, correlacion,
# VIF, control muestral) podria darse el caso de que el conjunto final
# carezca de variables climaticas o de variables especificas del gremio.
# Un modelo sin ninguna variable climatica carece de la base ambiental
# necesaria para proyectar distribuciones; un modelo sin variables de gremio
# pierde la especificidad ecologica que lo diferencia de un modelo generico.
# Esta fase verifica que al menos una variable climatica y una de gremio
# hayan sobrevivido las fases anteriores.
#
# POR QUE - Salvaguarda 3 (rescate de climatica/gremio faltante): Si la
# validacion detecta que falta una variable climatica o de gremio, se
# rescata la mejor candidata (por AIC) de entre las eliminadas en fases
# anteriores. Esto asegura el minimo de interpretabilidad ecologica del
# modelo: al menos un predictor climatico y al menos uno del gremio.
# ==============================================================================

fase6_control_ecologico <- function(data, response_col, var_info,
                                    vars_eliminadas_anteriores) {
  alerts <- character(0)
  rescatadas <- character(0)

  # Verificar que hay al menos una variable climatica
  if (!any(var_info$es_climatica)) {
    alerts <- c(alerts, "sin_climatica")
    mejor_clima <- vars_eliminadas_anteriores %>%
      filter(es_climatica) %>% arrange(AIC_univar) %>% head(1)
    if (nrow(mejor_clima) > 0) {
      rescatadas <- c(rescatadas, mejor_clima$variable)
      message(sprintf("    SALVAGUARDA 3: Rescatada climatica '%s'", mejor_clima$variable))
    }
  }

  # Verificar que hay al menos una variable de gremio (prioridad >= 2)
  if (!any(var_info$prioridad >= 2)) {
    alerts <- c(alerts, "sin_variable_gremio")
    mejor_gremio <- vars_eliminadas_anteriores %>%
      filter(prioridad >= 2) %>% arrange(AIC_univar) %>% head(1)
    if (nrow(mejor_gremio) > 0) {
      rescatadas <- c(rescatadas, mejor_gremio$variable)
      message(sprintf("    SALVAGUARDA 3: Rescatada gremio '%s'", mejor_gremio$variable))
    }
  }

  # Alerta informativa si falta una variable nucleo de gremio (p=4)
  if (!any(var_info$prioridad == 4)) alerts <- c(alerts, "sin_variable_nucleo_gremio")

  if (length(rescatadas) > 0) {
    var_info <- bind_rows(var_info,
                          vars_eliminadas_anteriores %>% filter(variable %in% rescatadas))
    alerts <- setdiff(alerts, c("sin_climatica", "sin_variable_gremio"))
  }
  if (length(alerts) == 0) message("  FASE 6: Validacion ecologica OK")
  else message(sprintf("  FASE 6: Alertas: %s", paste(alerts, collapse = ", ")))

  list(var_info = var_info, alerts = alerts, rescatadas = rescatadas)
}

# ==============================================================================
# FASE 7: VALIDACION PREDICTIVA
# ==============================================================================
# POR QUE: Las fases 1-6 seleccionan variables por criterios ecologicos y
# estadisticos, pero no evaluan directamente la capacidad predictiva del
# modelo resultante. La validacion k-fold (por defecto k=5) estima el
# rendimiento fuera de muestra (out-of-sample) mediante tres metricas
# complementarias:
#   - AUC (Area Under ROC Curve): capacidad de discriminacion global,
#     independiente del umbral de clasificacion.
#   - TSS (True Skill Statistic): sensibilidad + especificidad - 1,
#     corregida por prevalencia, estandar en SDMs (Allouche et al. 2006).
#   - Kappa (Cohen's Kappa): acuerdo observado vs. esperado por azar.
#
# Si el AUC es bajo (~0.5), el conjunto de variables seleccionadas no tiene
# poder predictivo, lo que senala un problema (pocas presencias, variables
# inadecuadas, etc.). Esta fase es informativa: no elimina variables, sino
# que registra las metricas para diagnostico posterior.
# ==============================================================================

fase7_validacion_predictiva <- function(data, response_col, var_info,
                                        k = NULL) {
  if (is.null(k)) k <- CONFIG$seleccion$k_folds_validation
  if (nrow(var_info) == 0) { message("  FASE 7: Sin variables"); return(list(metrics = NULL)) }

  vars_all <- var_info$variable
  # Limitar a 15 variables para evitar sobreajuste en validacion
  if (length(vars_all) > 15) {
    var_info_sorted <- var_info %>% arrange(AIC_univar)
    vars <- var_info_sorted$variable[1:15]
  } else { vars <- vars_all }

  X <- data[, vars, drop = FALSE]
  y <- as.numeric(data[[response_col]])
  for (v in vars) { if (!is.numeric(X[[v]])) X[[v]] <- as.numeric(as.character(X[[v]])) }

  complete_cases <- complete.cases(X, y)
  X <- X[complete_cases, , drop = FALSE]; y <- y[complete_cases]
  if (nrow(X) < 50) { message("  FASE 7: Pocas observaciones (<50)"); return(list(metrics = NULL)) }

  n <- nrow(X); folds <- sample(rep(1:k, length.out = n))
  auc_vals <- tss_vals <- kappa_vals <- rep(NA_real_, k)

  # Calculo manual de AUC (probabilistico) para no depender de paquetes extra
  calc_auc <- function(obs, pred) {
    if (length(unique(obs)) < 2) return(NA_real_)
    pos_pred <- pred[obs == 1]; neg_pred <- pred[obs == 0]
    if (length(pos_pred) == 0 || length(neg_pred) == 0) return(NA_real_)
    (sum(outer(pos_pred, neg_pred, ">")) + 0.5 * sum(outer(pos_pred, neg_pred, "=="))) /
      (length(pos_pred) * length(neg_pred))
  }

  for (i in 1:k) {
    train_idx <- which(folds != i); test_idx <- which(folds == i)
    X_train <- X[train_idx, , drop = FALSE]; y_train <- y[train_idx]
    X_test <- X[test_idx, , drop = FALSE]; y_test <- y[test_idx]
    if (length(y_train) < 30 || length(y_test) < 5) next
    if (sum(y_train) < 5 || sum(y_train == 0) < 5) next

    model <- tryCatch(suppressWarnings(
      glm(y_train ~ ., data = as.data.frame(X_train), family = binomial,
          control = glm.control(maxit = 100, epsilon = 1e-6))),
      error = function(e) NULL)
    if (is.null(model) || !model$converged) next

    pred_prob <- tryCatch(as.numeric(predict(model, newdata = as.data.frame(X_test), type = "response")),
                          error = function(e) NULL)
    if (is.null(pred_prob) || any(is.na(pred_prob)) || any(is.infinite(pred_prob))) next

    auc_vals[i] <- calc_auc(y_test, pred_prob)
    pred_bin <- as.integer(pred_prob > 0.5)
    tp <- sum(y_test == 1 & pred_bin == 1); tn <- sum(y_test == 0 & pred_bin == 0)
    fp <- sum(y_test == 0 & pred_bin == 1); fn <- sum(y_test == 1 & pred_bin == 0)
    total <- tp + tn + fp + fn; if (total == 0) next
    sens <- if ((tp + fn) > 0) tp / (tp + fn) else 0
    spec <- if ((tn + fp) > 0) tn / (tn + fp) else 0
    tss_vals[i] <- sens + spec - 1
    po <- (tp + tn) / total
    pe <- ((tp + fn) * (tp + fp) + (tn + fp) * (tn + fn)) / (total^2)
    if (pe < 1) kappa_vals[i] <- (po - pe) / (1 - pe)
  }

  n_success <- sum(!is.na(auc_vals))
  if (n_success == 0) { message("  FASE 7: Validacion fallo"); return(list(metrics = NULL)) }

  metrics <- list(
    AUC_mean = mean(auc_vals, na.rm = TRUE), AUC_sd = sd(auc_vals, na.rm = TRUE),
    TSS_mean = mean(tss_vals, na.rm = TRUE), TSS_sd = sd(tss_vals, na.rm = TRUE),
    Kappa_mean = mean(kappa_vals, na.rm = TRUE), Kappa_sd = sd(kappa_vals, na.rm = TRUE),
    n_folds_success = n_success, n_vars_validation = length(vars))
  message(sprintf("  FASE 7: AUC=%.3f (+/-%.3f), TSS=%.3f (%d/%d folds)",
                  metrics$AUC_mean, metrics$AUC_sd, metrics$TSS_mean, n_success, k))
  list(metrics = metrics)
}

# ==============================================================================
# FUNCION MAESTRA: PIPELINE COMPLETO
# ==============================================================================
#
# Ejecuta las 7 fases secuencialmente para una especie. Genera un JSON
# con toda la metadata de la seleccion (variables finales, eliminadas,
# metricas de validacion, alertas, parametros usados).
# ==============================================================================

run_pipeline_especie <- function(df, especie, especies_gremios,
                                 response_col = "presencia",
                                 output_json_dir = NULL,
                                 run_validation = NULL) {
  if (is.null(output_json_dir)) output_json_dir <- CONFIG$paths$variables_json
  if (is.null(run_validation)) run_validation <- CONFIG$seleccion$run_validation
  if (!dir.exists(output_json_dir)) dir.create(output_json_dir, recursive = TRUE)

  message(sprintf("\n=== PIPELINE: %s ===", especie))

  # Fase 1: Filtrar variables por gremio ecologico
  f1 <- fase1_preseleccion_gremio(df, especie, especies_gremios, response_col)
  # Fase 2: Eliminar variables con problemas estadisticos basicos
  f2 <- fase2_limpieza_basica(f1$data, response_col, f1$var_info)
  # Fase 3: Seleccion por correlacion ponderada (Munoz & Real) + salvaguarda 1
  f3 <- fase3_select_weighted(f2$data, response_col, f2$var_info)
  # Fase 4: Eliminacion iterativa por multicolinealidad (VIF)
  f4 <- fase4_vif_ponderado(f3$data, response_col, f3$var_info)
  # Fase 5: Control del ratio N/p (Harrell) + salvaguarda 2
  f5 <- fase5_control_muestral(f4$data, response_col, f4$var_info)

  # Recopilar todas las variables eliminadas en fases 2-4 para posible rescate
  vars_eliminadas_todas <- bind_rows(f2$var_info, f3$var_info, f4$var_info) %>%
    filter(!variable %in% f5$var_info$variable)
  # Fase 6: Validacion ecologica + salvaguarda 3
  f6 <- fase6_control_ecologico(f5$data, response_col, f5$var_info, vars_eliminadas_todas)

  # Fase 7: Validacion predictiva k-fold (solo si la especie es modelizable)
  if (run_validation && f5$status != "no_modelizar" && nrow(f6$var_info) > 0) {
    f7 <- fase7_validacion_predictiva(f5$data, response_col, f6$var_info)
  } else { f7 <- list(metrics = NULL) }

  # Stability selection (opcional): bootstrap de select07 para robustez
  stability_info <- NULL
  if (isTRUE(CONFIG$seleccion$stability_selection) &&
      f5$status != "no_modelizar" && nrow(f2$var_info) > 2) {
    message("  Stability selection...")
    vars_f2 <- setdiff(names(f2$data), response_col)
    X_stab <- f2$data[, vars_f2, drop = FALSE]
    y_stab <- f2$data[[response_col]]
    stability_info <- stability_selection(X_stab, y_stab, f2$var_info,
                                          n_boot = CONFIG$seleccion$n_boot_stability)
    message(sprintf("  Stability: %d vars con freq > 0.6",
                    sum(stability_info$stability_freq > 0.6)))
  }

  # Compilar alertas de todas las fases
  alerts <- unique(c(f5$alerts,
                     if (f4$conflicto_colinealidad_obligatorias) "conflicto_VIF_obligatorias",
                     f6$alerts))
  removed_all <- bind_rows(f2$removed, f3$removed, f4$removed, f5$removed)

  # Generar metadata JSON para la especie
  info_sp <- f1$especie_info
  metadata <- list(
    species = especie,
    gremio_refugio = info_sp$refugio[1],
    gremio_alimentacion = info_sp$alimentacion[1],
    n_presences = f5$n_pres,
    model_status = f5$status,
    variables_finales = lapply(seq_len(nrow(f6$var_info)), function(i) {
      row <- f6$var_info[i, ]
      stab_freq <- if (!is.null(stability_info) && row$variable %in% stability_info$variable) {
        stability_info$stability_freq[stability_info$variable == row$variable]
      } else { NULL }
      list(name = row$variable, prioridad = row$prioridad, peso = row$peso,
           tipo_base = row$tipo_base, es_climatica = row$es_climatica,
           es_gremio = row$es_gremio,
           AIC_univar = if ("AIC_univar" %in% names(row)) row$AIC_univar else NULL,
           VIF_final = if ("VIF_final" %in% names(row)) row$VIF_final else NULL,
           stability_freq = stab_freq)
    }),
    variables_eliminadas = removed_all %>% pmap(function(...) {
      row <- list(...)
      list(name = row$variable, phase = row$phase, reason = row$reason)
    }),
    validation = f7$metrics,
    stability = if (!is.null(stability_info)) as.list(deframe(stability_info)) else NULL,
    alerts = alerts,
    parameters = list(
      correlation_threshold = CONFIG$seleccion$correlation_threshold,
      vif_threshold = CONFIG$seleccion$vif_threshold,
      min_presences = CONFIG$seleccion$min_presencias,
      ratio_Np = CONFIG$seleccion$ratio_Np,
      stability_n_boot = CONFIG$seleccion$n_boot_stability)
  )

  file_json <- file.path(output_json_dir,
                         paste0(gsub("[^A-Za-z0-9]+", "_", especie), ".json"))
  jsonlite::write_json(metadata, file_json, auto_unbox = TRUE, pretty = TRUE)
  message(sprintf("  JSON guardado: %s\n", file_json))

  invisible(list(metadata = metadata, data_final = f5$data, var_info_final = f6$var_info,
                 removed_all = removed_all, alerts = alerts, validation = f7$metrics,
                 file_json = file_json))
}

# ==============================================================================
# STABILITY SELECTION (opcional)
# ==============================================================================
# Ejecuta N bootstrap de select07 para cuantificar la robustez de cada variable.
# stability_freq: fraccion de bootstraps donde la variable fue seleccionada.
# Variables con stability_freq > 0.6 son robustamente seleccionadas.
# ==============================================================================

stability_selection <- function(X, y, var_info, n_boot = 100,
                                threshold = NULL, seed = 123) {
  if (is.null(threshold)) threshold <- CONFIG$seleccion$correlation_threshold
  n <- nrow(X)
  var_counts <- setNames(rep(0L, ncol(X)), names(X))

  for (b in 1:n_boot) {
    set.seed(seed + b)
    idx <- sample(1:n, size = floor(n * 0.8), replace = FALSE)
    X_boot <- X[idx, , drop = FALSE]
    y_boot <- y[idx]
    selected <- tryCatch({
      res <- select07_weighted(X_boot, y_boot, var_info, threshold = threshold)
      res$selected_vars
    }, error = function(e) character(0))
    for (v in selected) {
      if (v %in% names(var_counts)) var_counts[v] <- var_counts[v] + 1L
    }
  }

  tibble(variable = names(var_counts),
         stability_freq = var_counts / n_boot) %>%
    arrange(desc(stability_freq))
}

message("[OK] Pipeline de seleccion cargado (7 fases + stability selection)")
