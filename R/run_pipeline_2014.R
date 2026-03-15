# ==============================================================================
# run_pipeline_2014.R - Pipeline completo con datos desde 2014
# ==============================================================================
#
# Ejecuta el pipeline identico al principal pero filtrando presencias con
# año >= 2014. Los resultados se guardan en carpetas separadas para no
# sobreescribir los resultados del pipeline original.
#
# USO:
#   source("R/run_pipeline_2014.R")
#
# OUTPUT:
#   data/processed_2014/       - datos intermedios filtrados
#   data/modelado_ready_2014/  - PAxENV filtrados
#   output_2014/               - modelos, mapas, logs, etc.
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

cat("\n")
cat("================================================================================\n")
cat("  PIPELINE 2014+ : Solo datos con año >= 2014\n")
cat("================================================================================\n\n")

# --- 1. Cargar configuracion base ---
source("R/00_setup/00_packages.R")
source("R/00_setup/00_config.R")

# --- 2. Modificar CONFIG para filtro temporal y rutas de salida ---

# Activar filtro temporal
CONFIG$datos$anio_min <- 2014

# Redirigir datos procesados a carpetas separadas
CONFIG$paths$presencias_std        <- "data/processed_2014/presencias_std.rds"
CONFIG$paths$pa_metodo             <- "data/processed_2014/pa_metodo.rds"
CONFIG$paths$muestras_metodo       <- "data/processed_2014/muestras_metodo.rds"
CONFIG$paths$muestras_metodo_wide  <- "data/processed_2014/muestras_metodo_wide.rds"
CONFIG$paths$tabla_cripticos       <- "data/processed_2014/tabla_cripticos.rds"
CONFIG$paths$resumen_muestreo      <- "data/processed_2014/resumen_muestreo.rds"
CONFIG$paths$candidatos_por_metodo <- "data/processed_2014/candidatos_por_metodo.rds"
CONFIG$paths$malla_union           <- "data/processed_2014/malla_union.rds"
CONFIG$paths$malla_peninsula       <- "data/processed_2014/malla_peninsula.rds"
CONFIG$paths$malla_baleares        <- "data/processed_2014/malla_baleares.rds"
CONFIG$paths$predictores_seo       <- "data/processed_2014/predictores_SEO.rds"
CONFIG$paths$geo_features          <- "data/processed_2014/geo_features.rds"
CONFIG$paths$predictores_seo_geo   <- "data/processed_2014/predictores_SEO_GEO.rds"
CONFIG$paths$predictores_seo_geo_sf <- "data/processed_2014/predictores_SEO_GEO_sf.rds"
CONFIG$paths$pa_data               <- "data/processed_2014/PAxENV_all_metodos.rds"
CONFIG$paths$esfuerzo              <- "data/processed_2014/esfuerzo_por_metodo.rds"
CONFIG$paths$grid_predictores      <- "data/processed_2014/predictores_SEO_GEO.rds"

CONFIG$paths$modelado_ready_dir    <- "data/modelado_ready_2014"
CONFIG$paths$paxenv_all            <- "data/modelado_ready_2014/PAxENV_por_metodo_all.rds"
CONFIG$paths$paxenv_acustica       <- "data/modelado_ready_2014/PAxENV_acustica.rds"
CONFIG$paths$paxenv_captura        <- "data/modelado_ready_2014/PAxENV_captura.rds"
CONFIG$paths$paxenv_cuevas         <- "data/modelado_ready_2014/PAxENV_cuevas.rds"
CONFIG$paths$paxenv_otros          <- "data/modelado_ready_2014/PAxENV_otros.rds"

# Redirigir salidas
CONFIG$output$base      <- "output_2014/modelos"
CONFIG$output$seleccion <- "output_2014/seleccion_variables"
CONFIG$output$logs      <- "output_2014/logs"
CONFIG$output$checks    <- "output_2014/checks"
CONFIG$output$figs      <- "output_2014/figs"
CONFIG$paths$variables_json <- "output_2014/seleccion_variables/variables_json"

# Activar fases (desactivar las ya completadas para re-ejecucion)
CONFIG$control$ejecutar$preparacion_datos   <- FALSE  # Ya completada
CONFIG$control$ejecutar$seleccion_variables <- FALSE  # Ya completada
CONFIG$control$ejecutar$modelo_ambiental    <- TRUE
CONFIG$control$ejecutar$modelo_espacial     <- TRUE
CONFIG$control$ejecutar$interseccion        <- TRUE
CONFIG$control$ejecutar$validacion          <- TRUE
CONFIG$control$ejecutar$incertidumbre       <- TRUE
CONFIG$control$ejecutar$mapas               <- TRUE
CONFIG$control$force_rerun                  <- TRUE

cat(sprintf("Filtro temporal: año >= %d\n", CONFIG$datos$anio_min))
cat(sprintf("Datos procesados: data/processed_2014/\n"))
cat(sprintf("Output: output_2014/\n\n"))

# --- 3. Ejecutar pipeline (mismo flujo que run_pipeline.R) ---
source("R/utils/utils_logging.R")
validar_config()
init_log()
log_event("pipeline", "", "INFO",
          sprintf("Pipeline iniciado con filtro temporal: año >= %d", CONFIG$datos$anio_min))
print_config()

# Crear directorios de salida
dir.create("data/processed_2014", recursive = TRUE, showWarnings = FALSE)
dir.create("data/modelado_ready_2014", recursive = TRUE, showWarnings = FALSE)
dir.create(CONFIG$output$base, recursive = TRUE, showWarnings = FALSE)
dir.create(CONFIG$output$logs, recursive = TRUE, showWarnings = FALSE)
dir.create(CONFIG$output$checks, recursive = TRUE, showWarnings = FALSE)
dir.create(CONFIG$output$figs, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(CONFIG$output$seleccion, "variables_json"),
           recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(CONFIG$output$seleccion, "diagnosticos"),
           recursive = TRUE, showWarnings = FALSE)

t_inicio <- Sys.time()
tiempos_fases <- list()

# === FASE 0: PREPARACION DE DATOS ===
if (isTRUE(CONFIG$control$ejecutar$preparacion_datos)) {
  cat("\n>>> FASE 0: PREPARACION DE DATOS (2014+) <<<\n\n")
  t0 <- Sys.time()
  source("R/01_data_preparation/01a_preparar_PA_metodo.R")
  cat("\n--- 01b: Cargar malla UTM ---\n")
  source("R/01_data_preparation/01b_cargar_malla.R")
  cat("\n--- 01c: Cargar variables Excel ---\n")
  source("R/01_data_preparation/01c_cargar_variables_excel.R")
  cat("\n--- 01d: Agrupar CORINE ---\n")
  source("R/01_data_preparation/01d_agrupar_corine.R")
  cat("\n--- 01e: Procesar geologia ---\n")
  source("R/01_data_preparation/01e_procesar_geologia.R")
  cat("\n--- 01f: Unir predictores ---\n")
  source("R/01_data_preparation/01f_unir_predictores.R")
  cat("\n--- 01g: Crear PAxENV por metodo ---\n")
  source("R/01_data_preparation/01g_crear_PAxENV_metodo.R")
  t0_dur <- difftime(Sys.time(), t0, units = "mins")
  tiempos_fases[["Fase 0: Preparacion"]] <- t0_dur
  cat(sprintf("\n[OK] Fase 0 completada en %s\n", format(round(t0_dur, 1))))
}

# === FASE 1: SELECCION DE VARIABLES ===
if (isTRUE(CONFIG$control$ejecutar$seleccion_variables)) {
  cat("\n>>> FASE 1: SELECCION DE VARIABLES <<<\n\n")
  t1 <- Sys.time()
  source("R/02_variable_selection/02d_ejecutar_seleccion.R")
  t1_dur <- difftime(Sys.time(), t1, units = "mins")
  tiempos_fases[["Fase 1: Seleccion"]] <- t1_dur
  cat(sprintf("\n[OK] Fase 1 completada en %s\n", format(round(t1_dur, 1))))
}

# === FASE 2: MODELO AMBIENTAL ===
if (isTRUE(CONFIG$control$ejecutar$modelo_ambiental)) {
  cat("\n>>> FASE 2: MODELO AMBIENTAL <<<\n\n")
  t2 <- Sys.time()
  source("R/03_modeling/03a_modelo_ambiental.R")
  t2_dur <- difftime(Sys.time(), t2, units = "mins")
  tiempos_fases[["Fase 2: Modelo ambiental"]] <- t2_dur
  cat(sprintf("\n[OK] Fase 2 completada en %s\n", format(round(t2_dur, 1))))
}

# === FASE 3: MODELO ESPACIAL ===
if (isTRUE(CONFIG$control$ejecutar$modelo_espacial)) {
  cat("\n>>> FASE 3: MODELO ESPACIAL <<<\n\n")
  t3 <- Sys.time()
  source("R/03_modeling/03b_modelo_espacial.R")
  t3_dur <- difftime(Sys.time(), t3, units = "mins")
  tiempos_fases[["Fase 3: Modelo espacial"]] <- t3_dur
  cat(sprintf("\n[OK] Fase 3 completada en %s\n", format(round(t3_dur, 1))))
}

# === FASE 4: INTERSECCION FUZZY ===
if (isTRUE(CONFIG$control$ejecutar$interseccion)) {
  cat("\n>>> FASE 4: INTERSECCION FUZZY <<<\n\n")
  t4 <- Sys.time()
  source("R/03_modeling/03c_interseccion_fuzzy.R")
  t4_dur <- difftime(Sys.time(), t4, units = "mins")
  tiempos_fases[["Fase 4: Interseccion"]] <- t4_dur
  cat(sprintf("\n[OK] Fase 4 completada en %s\n", format(round(t4_dur, 1))))
}

# === FASE 5: VALIDACION CRUZADA ===
if (isTRUE(CONFIG$control$ejecutar$validacion)) {
  cat("\n>>> FASE 5: VALIDACION CRUZADA <<<\n\n")
  t5 <- Sys.time()
  source("R/03_modeling/03d_validacion_cv.R")
  t5_dur <- difftime(Sys.time(), t5, units = "mins")
  tiempos_fases[["Fase 5: Validacion"]] <- t5_dur
  cat(sprintf("\n[OK] Fase 5 completada en %s\n", format(round(t5_dur, 1))))
}

# === FASE 6: INCERTIDUMBRE ===
if (isTRUE(CONFIG$control$ejecutar$incertidumbre)) {
  cat("\n>>> FASE 6: INCERTIDUMBRE <<<\n\n")
  t6 <- Sys.time()
  source("R/03_modeling/03e_incertidumbre.R")
  t6_dur <- difftime(Sys.time(), t6, units = "mins")
  tiempos_fases[["Fase 6: Incertidumbre"]] <- t6_dur
  cat(sprintf("\n[OK] Fase 6 completada en %s\n", format(round(t6_dur, 1))))
}

# === FASE 7: MAPAS ===
if (isTRUE(CONFIG$control$ejecutar$mapas)) {
  cat("\n>>> FASE 7: MAPAS ATLAS <<<\n\n")
  t7 <- Sys.time()
  source("R/04_visualization/04a_mapas_atlas.R")
  t7_dur <- difftime(Sys.time(), t7, units = "mins")
  tiempos_fases[["Fase 7: Mapas"]] <- t7_dur
  cat(sprintf("\n[OK] Fase 7 completada en %s\n", format(round(t7_dur, 1))))
}

# === RESUMEN FINAL ===
t_total <- difftime(Sys.time(), t_inicio, units = "mins")

cat("\n")
cat("================================================================================\n")
cat("  PIPELINE 2014+ COMPLETADO\n")
cat("================================================================================\n\n")

if (length(tiempos_fases) > 0) {
  cat("TIEMPOS POR FASE:\n")
  for (fase_nombre in names(tiempos_fases)) {
    cat(sprintf("  %-30s %s\n", fase_nombre,
                format(round(tiempos_fases[[fase_nombre]], 1))))
  }
  cat("\n")
}

cat(sprintf("Filtro temporal: año >= %d\n", CONFIG$datos$anio_min))
cat(sprintf("Tiempo total: %s\n", format(round(t_total, 1))))
cat(sprintf("Fecha: %s\n", Sys.time()))
cat(sprintf("Output: %s\n\n", CONFIG$output$base))

if (dir.exists(CONFIG$output$base)) {
  dirs_sp <- list.dirs(CONFIG$output$base, recursive = FALSE)
  if (length(dirs_sp) > 0) {
    n_completadas <- sum(vapply(dirs_sp, function(d) {
      file.exists(file.path(d, "mapas", "checkpoint_mapas.txt"))
    }, logical(1)))
    cat(sprintf("Especies con pipeline completo: %d\n", n_completadas))
  }
}

log_event("pipeline", "", "INFO",
          sprintf("Pipeline 2014+ completado en %s", format(round(t_total, 1))))
cat("\nLOG DE EJECUCION:\n")
log_summary()
cat("\n================================================================================\n")
