# ==============================================================================
# run_pipeline.R - SCRIPT MAESTRO
# ==============================================================================
#
# Ejecuta el pipeline completo desde datos brutos hasta mapas finales.
# Cada fase puede ejecutarse independientemente o como parte del flujo completo.
#
# Flujo general:
#   Fase 0: Preparacion de datos (01a-01h)
#           - Lee presencias brutas, malla UTM, variables Excel/CSV
#           - Genera PAxENV por metodo (formato listo para modelado)
#   Fase 1: Seleccion de variables (02a-02d)
#           - Pipeline de 7 fases con salvaguardas ecologicas
#           - Genera JSON por especie con variables seleccionadas
#   Fase 2: Modelo ambiental (GLM + Favorabilidad)
#   Fase 3: Modelo espacial (GAM seleccionado por AICc)
#   Fase 4: Interseccion fuzzy (combina ambiental y espacial)
#   Fase 5: Validacion cruzada (k-fold espacial)
#   Fase 6: Incertidumbre (MESS + bootstrap + esfuerzo)
#   Fase 7: Mapas atlas (favorabilidad + incertidumbre)
#
# USO:
#   source("R/run_pipeline.R")
#
# CONFIGURACION:
#   Editar R/00_setup/00_config.R para modificar parametros, rutas y fases.
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

cat("\n")
cat("================================================================================\n")
cat("  ATLAS DE MURCIELAGOS DE LA PENINSULA IBERICA - SECEMU\n")
cat("  Pipeline de modelizacion de distribucion de especies\n")
cat("================================================================================\n\n")

# --- SETUP ---
# Registro del tiempo de inicio para el resumen final
t_inicio <- Sys.time()

# Cargar paquetes y configuracion centralizada
source("R/00_setup/00_packages.R")
source("R/00_setup/00_config.R")
source("R/utils/utils_logging.R")

# Validar configuracion: verifica que existen archivos criticos, parametros
# numericos son validos, pesos suman 1, etc. Detiene el pipeline si hay errores.
validar_config()

# --- PRE-FLIGHT: verificar datos procesados si fases 0-1 desactivadas ---
# Si las fases de preparacion/seleccion estan desactivadas, los datos intermedios
# deben existir ya. Sin ellos, las fases 2-7 fallaran silenciosamente.
if (!isTRUE(CONFIG$control$ejecutar$preparacion_datos)) {
  archivos_requeridos_fase0 <- c(CONFIG$paths$pa_data, CONFIG$paths$esfuerzo)
  faltantes <- archivos_requeridos_fase0[!file.exists(archivos_requeridos_fase0)]
  if (length(faltantes) > 0) {
    cat("\n[AVISO PRE-FLIGHT] Fase 0 desactivada pero faltan datos procesados:\n")
    for (f in faltantes) cat(sprintf("  - %s\n", f))
    cat("  Active preparacion_datos=TRUE en CONFIG o proporcione estos archivos.\n\n")
    if (isTRUE(CONFIG$control$ejecutar$modelo_ambiental) ||
        isTRUE(CONFIG$control$ejecutar$modelo_espacial)) {
      stop("Pre-flight fallido: datos procesados requeridos para fases 2+ no encontrados.")
    }
  }
}

if (!isTRUE(CONFIG$control$ejecutar$seleccion_variables) &&
    isTRUE(CONFIG$control$ejecutar$modelo_ambiental)) {
  json_dir <- CONFIG$paths$variables_json
  if (!dir.exists(json_dir) || length(list.files(json_dir, pattern = "\\.json$")) == 0) {
    cat("\n[AVISO PRE-FLIGHT] Fase 1 desactivada pero no hay JSONs de variables en:\n")
    cat(sprintf("  %s\n", json_dir))
    cat("  Active seleccion_variables=TRUE o ejecute la Fase 1 previamente.\n\n")
    stop("Pre-flight fallido: JSONs de variables requeridos para Fase 2+ no encontrados.")
  }
}

# Inicializar log centralizado
init_log()
log_event("pipeline", "", "INFO", "Pipeline iniciado")

# Imprimir resumen de configuracion actual
print_config()

# Crear directorios de salida (idempotente)
dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
dir.create("data/modelado_ready", recursive = TRUE, showWarnings = FALSE)
dir.create(CONFIG$output$base, recursive = TRUE, showWarnings = FALSE)
dir.create(CONFIG$output$logs, recursive = TRUE, showWarnings = FALSE)
dir.create(CONFIG$output$checks, recursive = TRUE, showWarnings = FALSE)
dir.create(CONFIG$output$figs, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(CONFIG$output$seleccion, "variables_json"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(CONFIG$output$seleccion, "diagnosticos"), recursive = TRUE, showWarnings = FALSE)

# Tabla para registrar tiempos por fase
tiempos_fases <- list()

# ==============================================================================
# FASE 0: PREPARACION DE DATOS
# ==============================================================================
# Lee datos brutos (presencias CSV, shapefiles UTM, variables Excel, geologia CSV)
# y produce los ficheros PAxENV listos para modelado.

if (isTRUE(CONFIG$control$ejecutar$preparacion_datos)) {

  cat("\n>>> FASE 0: PREPARACION DE DATOS <<<\n\n")
  t0 <- Sys.time()

  cat("--- 01a: Preparar PA por metodo + complejos ---\n")
  source("R/01_data_preparation/01a_preparar_PA_metodo.R")

  cat("\n--- 01b: Cargar malla UTM (Peninsula + Baleares) ---\n")
  source("R/01_data_preparation/01b_cargar_malla.R")

  cat("\n--- 01c: Cargar variables desde Excel ---\n")
  source("R/01_data_preparation/01c_cargar_variables_excel.R")

  cat("\n--- 01d: Agrupar CORINE ---\n")
  source("R/01_data_preparation/01d_agrupar_corine.R")

  cat("\n--- 01e: Procesar geologia + geo features ---\n")
  source("R/01_data_preparation/01e_procesar_geologia.R")

  cat("\n--- 01f: Unir predictores (SEO + GEO) ---\n")
  source("R/01_data_preparation/01f_unir_predictores.R")

  cat("\n--- 01g: Crear PAxENV por metodo ---\n")
  source("R/01_data_preparation/01g_crear_PAxENV_metodo.R")

  if (isTRUE(CONFIG$control$ejecutar$qa_mapas)) {
    cat("\n--- 01h: Mapas de chequeo (QA) ---\n")
    source("R/01_data_preparation/01h_mapa_chequeo.R")
  }

  t0_dur <- difftime(Sys.time(), t0, units = "mins")
  tiempos_fases[["Fase 0: Preparacion"]] <- t0_dur
  cat(sprintf("\n[OK] Fase 0 completada en %s\n", format(round(t0_dur, 1))))

} else {
  cat(">>> FASE 0: Preparacion de datos [OMITIDA]\n")
}

# ==============================================================================
# FASE 1: SELECCION DE VARIABLES
# ==============================================================================
# Ejecuta el pipeline de 7 fases (02b) para cada especie modelizable.
# Genera un JSON por especie con variables seleccionadas + metricas.

if (isTRUE(CONFIG$control$ejecutar$seleccion_variables)) {

  cat("\n>>> FASE 1: SELECCION DE VARIABLES <<<\n\n")
  t1 <- Sys.time()

  source("R/02_variable_selection/02d_ejecutar_seleccion.R")

  t1_dur <- difftime(Sys.time(), t1, units = "mins")
  tiempos_fases[["Fase 1: Seleccion"]] <- t1_dur
  cat(sprintf("\n[OK] Fase 1 completada en %s\n", format(round(t1_dur, 1))))

} else {
  cat(">>> FASE 1: Seleccion de variables [OMITIDA]\n")
}

# ==============================================================================
# FASE 2: MODELO AMBIENTAL (GLM + Favorabilidad)
# ==============================================================================
# Ajusta GLMs binomiales con las variables seleccionadas en Fase 1.
# Calcula favorabilidad ambiental (Real et al. 2006) para cada cuadricula.

if (isTRUE(CONFIG$control$ejecutar$modelo_ambiental)) {

  cat("\n>>> FASE 2: MODELO AMBIENTAL <<<\n\n")
  t2 <- Sys.time()

  source("R/03_modeling/03a_modelo_ambiental.R")

  t2_dur <- difftime(Sys.time(), t2, units = "mins")
  tiempos_fases[["Fase 2: Modelo ambiental"]] <- t2_dur
  cat(sprintf("\n[OK] Fase 2 completada en %s\n", format(round(t2_dur, 1))))

} else {
  cat(">>> FASE 2: Modelo ambiental [OMITIDA]\n")
}

# ==============================================================================
# FASE 3: MODELO ESPACIAL (GAM seleccionado por AICc)
# ==============================================================================
# Ajusta modelos espaciales (GAM/GLM polinomico) para capturar
# autocorrelacion espacial residual.

if (isTRUE(CONFIG$control$ejecutar$modelo_espacial)) {

  cat("\n>>> FASE 3: MODELO ESPACIAL <<<\n\n")
  t3 <- Sys.time()

  source("R/03_modeling/03b_modelo_espacial.R")

  t3_dur <- difftime(Sys.time(), t3, units = "mins")
  tiempos_fases[["Fase 3: Modelo espacial"]] <- t3_dur
  cat(sprintf("\n[OK] Fase 3 completada en %s\n", format(round(t3_dur, 1))))

} else {
  cat(">>> FASE 3: Modelo espacial [OMITIDA]\n")
}

# ==============================================================================
# FASE 4: INTERSECCION FUZZY
# ==============================================================================
# Combina favorabilidad ambiental y espacial mediante operadores fuzzy
# (media geometrica por defecto) para generar la favorabilidad final.

if (isTRUE(CONFIG$control$ejecutar$interseccion)) {

  cat("\n>>> FASE 4: INTERSECCION FUZZY <<<\n\n")
  t4 <- Sys.time()

  source("R/03_modeling/03c_interseccion_fuzzy.R")

  t4_dur <- difftime(Sys.time(), t4, units = "mins")
  tiempos_fases[["Fase 4: Interseccion"]] <- t4_dur
  cat(sprintf("\n[OK] Fase 4 completada en %s\n", format(round(t4_dur, 1))))

} else {
  cat(">>> FASE 4: Interseccion fuzzy [OMITIDA]\n")
}

# ==============================================================================
# FASE 5: VALIDACION CRUZADA
# ==============================================================================
# Validacion k-fold espacial (bloques por k-means) para evaluar la capacidad
# predictiva del modelo completo fuera de muestra.

if (isTRUE(CONFIG$control$ejecutar$validacion)) {

  cat("\n>>> FASE 5: VALIDACION CRUZADA <<<\n\n")
  t5 <- Sys.time()

  source("R/03_modeling/03d_validacion_cv.R")

  t5_dur <- difftime(Sys.time(), t5, units = "mins")
  tiempos_fases[["Fase 5: Validacion"]] <- t5_dur
  cat(sprintf("\n[OK] Fase 5 completada en %s\n", format(round(t5_dur, 1))))

} else {
  cat(">>> FASE 5: Validacion cruzada [OMITIDA]\n")
}

# ==============================================================================
# FASE 6: INCERTIDUMBRE
# ==============================================================================
# Combina tres fuentes de incertidumbre: MESS (extrapolacion ambiental),
# bootstrap (variabilidad de coeficientes), y esfuerzo de muestreo.

if (isTRUE(CONFIG$control$ejecutar$incertidumbre)) {

  cat("\n>>> FASE 6: INCERTIDUMBRE <<<\n\n")
  t6 <- Sys.time()

  source("R/03_modeling/03e_incertidumbre.R")

  t6_dur <- difftime(Sys.time(), t6, units = "mins")
  tiempos_fases[["Fase 6: Incertidumbre"]] <- t6_dur
  cat(sprintf("\n[OK] Fase 6 completada en %s\n", format(round(t6_dur, 1))))

} else {
  cat(">>> FASE 6: Incertidumbre [OMITIDA]\n")
}

# ==============================================================================
# FASE 7: MAPAS
# ==============================================================================
# Genera mapas del atlas: favorabilidad y incertidumbre por especie.

if (isTRUE(CONFIG$control$ejecutar$mapas)) {

  cat("\n>>> FASE 7: MAPAS ATLAS <<<\n\n")
  t7 <- Sys.time()

  source("R/04_visualization/04a_mapas_atlas.R")

  t7_dur <- difftime(Sys.time(), t7, units = "mins")
  tiempos_fases[["Fase 7: Mapas"]] <- t7_dur
  cat(sprintf("\n[OK] Fase 7 completada en %s\n", format(round(t7_dur, 1))))

} else {
  cat(">>> FASE 7: Mapas [OMITIDA]\n")
}

# ==============================================================================
# RESUMEN FINAL
# ==============================================================================

t_total <- difftime(Sys.time(), t_inicio, units = "mins")

cat("\n")
cat("================================================================================\n")
cat("  PIPELINE COMPLETADO\n")
cat("================================================================================\n\n")

# --- Resumen de tiempos por fase ---
if (length(tiempos_fases) > 0) {
  cat("TIEMPOS POR FASE:\n")
  for (fase_nombre in names(tiempos_fases)) {
    cat(sprintf("  %-30s %s\n", fase_nombre,
                format(round(tiempos_fases[[fase_nombre]], 1))))
  }
  cat("\n")
}

cat(sprintf("Tiempo total: %s\n", format(round(t_total, 1))))
cat(sprintf("Fecha: %s\n", Sys.time()))
cat(sprintf("Output: %s\n\n", CONFIG$output$base))

# Contar especies con pipeline completamente terminado (con mapas generados)
if (dir.exists(CONFIG$output$base)) {
  dirs_sp <- list.dirs(CONFIG$output$base, recursive = FALSE)
  if (length(dirs_sp) > 0) {
    n_completadas <- sum(vapply(dirs_sp, function(d) {
      file.exists(file.path(d, "mapas", "checkpoint_mapas.txt"))
    }, logical(1)))
    cat(sprintf("Especies con pipeline completo: %d\n", n_completadas))
  } else {
    cat("Especies con pipeline completo: 0 (sin directorios de especie)\n")
  }
}

# Resumen del log de ejecucion
log_event("pipeline", "", "INFO", sprintf("Pipeline completado en %s", format(round(t_total, 1))))
cat("\nLOG DE EJECUCION:\n")
log_summary()

cat("\n================================================================================\n")
