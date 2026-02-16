# ==============================================================================
# 02c_diagnostico.R - Diagnostico de seleccion de variables
# ==============================================================================
#
# Lee los JSONs generados por 02d_ejecutar_seleccion.R (uno por especie) y
# produce un resumen tabular con metricas clave para evaluar la calidad de
# la seleccion de variables a traves de todas las especies.
#
# Salida: CSV "resumen_seleccion.csv" con las siguientes columnas:
#   - especie:       nombre cientifico de la especie
#   - refugio:       gremio de refugio asignado (Cavernicola, Arboricola, etc.)
#   - alimentacion:  gremio de alimentacion (Forestal, Ripario, Generalista, etc.)
#   - n_presencias:  numero de cuadriculas con presencia confirmada
#   - model_status:  estado del modelo ("modelo_completo", "modelo_simple",
#                    "no_modelizar"). "modelo_simple" indica pocas presencias
#                    (30-59); "no_modelizar" indica <30 presencias.
#   - n_variables:   numero de variables ambientales seleccionadas tras las
#                    7 fases del pipeline. Valores tipicos: 3-12.
#   - AUC_mean:      media del AUC (Area Under ROC Curve) en validacion k-fold.
#                    Valores: 0.5 = azar, >0.7 = aceptable, >0.8 = bueno.
#   - TSS_mean:      media del TSS (True Skill Statistic) en validacion k-fold.
#                    Valores: 0 = azar, >0.4 = aceptable, >0.6 = bueno.
#   - n_alertas:     numero de alertas generadas durante la seleccion
#                    (p.ej., sin variable climatica, conflicto VIF, etc.)
#   - variables:     lista de nombres de variables finales separadas por coma
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

# --- Carga condicional ---
if (!exists("CONFIG")) source("R/00_setup/00_config.R")

suppressPackageStartupMessages({
  library(tidyverse)
  library(jsonlite)
})

cat("\n=== DIAGNOSTICO DE SELECCION DE VARIABLES ===\n\n")

# --- Localizar JSONs de seleccion ---
# Cada JSON contiene la metadata completa de la seleccion para una especie:
# variables finales, eliminadas, metricas de validacion, alertas, etc.
json_dir <- CONFIG$paths$variables_json
jsons <- list.files(json_dir, pattern = "\\.json$", full.names = TRUE)

if (length(jsons) == 0) {
  cat("No se encontraron JSONs de seleccion\n")
  cat("Ejecuta primero 02d_ejecutar_seleccion.R\n")
  stop("Sin datos de seleccion")
}

# --- Construir tabla resumen ---
resumen <- tibble()

for (json_file in jsons) {
  info <- fromJSON(json_file)

  # Extraer nombres de variables finales del JSON
  n_vars <- length(info$variables_finales)
  if (is.list(info$variables_finales) && length(info$variables_finales) > 0) {
    var_names <- sapply(info$variables_finales, function(v) v$name)
  } else {
    var_names <- character(0)
  }

  resumen <- bind_rows(resumen, tibble(
    # Identificacion de la especie y su gremio
    especie = info$species,
    refugio = ifelse(is.null(info$gremio_refugio), NA, info$gremio_refugio),
    alimentacion = ifelse(is.null(info$gremio_alimentacion), NA, info$gremio_alimentacion),
    # Tamano muestral y estado del modelo
    n_presencias = info$n_presences,
    model_status = ifelse(is.null(info$model_status), "OK", info$model_status),
    # Resultado de la seleccion
    n_variables = n_vars,
    # Metricas de validacion predictiva (fase 7 del pipeline)
    # AUC_mean: capacidad discriminativa global (0.5 = azar, 1.0 = perfecto)
    AUC_mean = ifelse(is.null(info$validation$AUC_mean), NA, info$validation$AUC_mean),
    # TSS_mean: sensibilidad + especificidad - 1 (0 = azar, 1.0 = perfecto)
    TSS_mean = ifelse(is.null(info$validation$TSS_mean), NA, info$validation$TSS_mean),
    # Numero de alertas ecologicas o estadisticas detectadas
    n_alertas = length(info$alerts),
    # Variables seleccionadas (para inspeccion rapida)
    variables = paste(var_names, collapse = ", ")
  ))
}

# --- Imprimir resumen global ---
cat(sprintf("Especies procesadas: %d\n\n", nrow(resumen)))
# Estadisticos descriptivos del numero de variables seleccionadas
cat(sprintf("Variables por especie: %.1f +/- %.1f [%d, %d]\n",
            mean(resumen$n_variables), sd(resumen$n_variables),
            min(resumen$n_variables), max(resumen$n_variables)))

# AUC medio global (solo especies con validacion disponible)
if (any(!is.na(resumen$AUC_mean))) {
  cat(sprintf("AUC medio: %.3f +/- %.3f\n",
              mean(resumen$AUC_mean, na.rm = TRUE), sd(resumen$AUC_mean, na.rm = TRUE)))
}

# --- Desglose por gremio de refugio ---
# Permite detectar si algun gremio tiene sistematicamente peores metricas
# (p.ej., especies arboricolas con pocos datos)
cat("\nPor gremio de refugio:\n")
resumen %>% group_by(refugio) %>%
  summarise(n = n(), vars_media = mean(n_variables),
            AUC = mean(AUC_mean, na.rm = TRUE), .groups = "drop") %>%
  print()

# --- Desglose por gremio de alimentacion ---
cat("\nPor gremio de alimentacion:\n")
resumen %>% group_by(alimentacion) %>%
  summarise(n = n(), vars_media = mean(n_variables),
            AUC = mean(AUC_mean, na.rm = TRUE), .groups = "drop") %>%
  print()

# --- Desglose por estado del modelo ---
# "modelo_completo" = >=60 presencias, "modelo_simple" = 30-59, "no_modelizar" = <30
cat("\nPor status de modelo:\n")
print(table(resumen$model_status))

# --- Guardar CSV de diagnostico ---
dir.create(file.path(CONFIG$output$seleccion, "diagnosticos"), recursive = TRUE, showWarnings = FALSE)
write_csv(resumen, file.path(CONFIG$output$seleccion, "diagnosticos", "resumen_seleccion.csv"))
cat(sprintf("\n[OK] Guardado: %s\n",
            file.path(CONFIG$output$seleccion, "diagnosticos", "resumen_seleccion.csv")))
