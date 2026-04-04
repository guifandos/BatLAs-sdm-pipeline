# ==============================================================================
# run_residuos_2014.R - Re-run phases 4-7 using spatial residuals (2014+ data)
# ==============================================================================
# Uses existing ambiental + espacial_residuos outputs from output_2014_v2
# Only re-runs: interseccion, validacion, incertidumbre, mapas
# Output: output_residuos_2014/
# ==============================================================================

cat("\n")
cat("================================================================================\n")
cat("  PIPELINE RESIDUOS (2014+): Re-run fases 4-7 con modelo espacial de residuos\n")
cat("================================================================================\n\n")

# --- 1. Load config ---
source("R/00_setup/00_packages.R")
source("R/00_setup/00_config.R")

# --- 2. Override CONFIG for 2014 paths ---
CONFIG$datos$anio_min <- 2014

# Data paths (same as run_pipeline_2014.R)
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

# --- 3. Copy existing 2014 models to new output folder ---
SRC_DIR <- "output_2014/modelos"
DST_DIR <- "output_residuos_2014/modelos"

if (!dir.exists(DST_DIR)) {
  cat("Copiando modelos existentes a output_residuos_2014/...\n")
  dir.create("output_residuos_2014", recursive = TRUE, showWarnings = FALSE)
  system2("cp", c("-r", SRC_DIR, DST_DIR))
  cat("  [OK] Copiado\n\n")
} else {
  cat("output_residuos_2014/modelos/ ya existe, usando existente\n\n")
}

# --- 4. Remove old checkpoints for phases 4-7 ---
cat("Limpiando checkpoints de fases 4-7...\n")
dirs_sp <- list.dirs(DST_DIR, recursive = FALSE)
for (d in dirs_sp) {
  for (subdir in c("interseccion", "validacion", "incertidumbre", "mapas")) {
    cp <- file.path(d, subdir, paste0("checkpoint_", subdir, ".txt"))
    if (file.exists(cp)) file.remove(cp)
  }
}
cat("  [OK]\n\n")

# --- 5. Override output paths ---
CONFIG$output$base      <- DST_DIR
CONFIG$output$seleccion <- "output_residuos_2014/seleccion_variables"
CONFIG$output$logs      <- "output_residuos_2014/logs"
CONFIG$output$checks    <- "output_residuos_2014/checks"
CONFIG$output$figs      <- "output_residuos_2014/figs"
CONFIG$paths$variables_json <- "output_2014_v2/seleccion_variables/variables_json"

# Only run phases 4-7
CONFIG$control$ejecutar$preparacion_datos   <- FALSE
CONFIG$control$ejecutar$seleccion_variables <- FALSE
CONFIG$control$ejecutar$modelo_ambiental    <- FALSE
CONFIG$control$ejecutar$modelo_espacial     <- FALSE
CONFIG$control$ejecutar$interseccion        <- TRUE
CONFIG$control$ejecutar$validacion          <- TRUE
CONFIG$control$ejecutar$incertidumbre       <- TRUE
CONFIG$control$ejecutar$mapas               <- TRUE
CONFIG$control$force_rerun                  <- TRUE

CONFIG$espacial$usar_residuos <- TRUE

# --- 6. Init logging ---
for (d in c(CONFIG$output$logs, CONFIG$output$checks, CONFIG$output$figs)) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}
source("R/utils/utils_logging.R")
init_log()
log_event("pipeline", "", "INFO", "Pipeline residuos (2014+) iniciado")

t_inicio <- Sys.time()
tiempos_fases <- list()

# === FASE 4: INTERSECCION FUZZY (residuos) ===
cat("\n>>> FASE 4: INTERSECCION FUZZY (residuos) <<<\n\n")
t4 <- Sys.time()
source("R/03_modeling/03c_interseccion_fuzzy.R")
t4_dur <- difftime(Sys.time(), t4, units = "mins")
tiempos_fases[["Fase 4: Interseccion"]] <- t4_dur
cat(sprintf("\n[OK] Fase 4 completada en %s\n", format(round(t4_dur, 1))))

# === FASE 5: VALIDACION CRUZADA ===
cat("\n>>> FASE 5: VALIDACION CRUZADA <<<\n\n")
t5 <- Sys.time()
source("R/03_modeling/03d_validacion_cv.R")
t5_dur <- difftime(Sys.time(), t5, units = "mins")
tiempos_fases[["Fase 5: Validacion"]] <- t5_dur
cat(sprintf("\n[OK] Fase 5 completada en %s\n", format(round(t5_dur, 1))))

# === FASE 6: INCERTIDUMBRE ===
cat("\n>>> FASE 6: INCERTIDUMBRE <<<\n\n")
t6 <- Sys.time()
source("R/03_modeling/03e_incertidumbre.R")
t6_dur <- difftime(Sys.time(), t6, units = "mins")
tiempos_fases[["Fase 6: Incertidumbre"]] <- t6_dur
cat(sprintf("\n[OK] Fase 6 completada en %s\n", format(round(t6_dur, 1))))

# === FASE 7: MAPAS ===
cat("\n>>> FASE 7: MAPAS ATLAS <<<\n\n")
t7 <- Sys.time()
source("R/04_visualization/04a_mapas_atlas.R")
t7_dur <- difftime(Sys.time(), t7, units = "mins")
tiempos_fases[["Fase 7: Mapas"]] <- t7_dur
cat(sprintf("\n[OK] Fase 7 completada en %s\n", format(round(t7_dur, 1))))

# === RESUMEN ===
t_total <- difftime(Sys.time(), t_inicio, units = "mins")
cat("\n================================================================================\n")
cat("  PIPELINE RESIDUOS (2014+) COMPLETADO\n")
cat("================================================================================\n\n")
for (fase in names(tiempos_fases)) {
  cat(sprintf("  %-30s %s\n", fase, format(round(tiempos_fases[[fase]], 1))))
}
cat(sprintf("\nTiempo total: %s\n", format(round(t_total, 1))))
cat(sprintf("Output: %s\n\n", DST_DIR))
