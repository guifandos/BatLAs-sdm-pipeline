# ==============================================================================
# run_pipeline_2014.R - Pipeline con datos desde 2014
# ==============================================================================
# Copia del flujo de run_pipeline.R pero con output_2014/ y anio_min=2014

cat("\n")
cat("================================================================================\n")
cat("  PIPELINE 2014+ - ATLAS DE MURCIELAGOS\n")
cat("================================================================================\n\n")

t_inicio <- Sys.time()

source("R/00_setup/00_packages.R")
source("R/00_setup/00_config.R")
source("R/utils/utils_logging.R")

# --- Sobreescribir CONFIG para output_2014 ---
CONFIG$output$base <- "output_2014/modelos"
CONFIG$output$seleccion <- "output_2014/seleccion_variables"
CONFIG$output$logs <- "output_2014/logs"
CONFIG$output$checks <- "output_2014/checks"
CONFIG$output$figs <- "output_2014/figs"
CONFIG$paths$variables_json <- "output_2014/seleccion_variables/variables_json"
CONFIG$datos$anio_min <- 2014
CONFIG$control$force_rerun <- TRUE
CONFIG$control$ejecutar$preparacion_datos <- FALSE

cat(sprintf("  anio_min: %d\n", CONFIG$datos$anio_min))
cat(sprintf("  output base: %s\n", CONFIG$output$base))

validar_config()
init_log()
log_event("pipeline", "", "INFO", "Pipeline 2014 iniciado")
print_config()

dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
dir.create("data/modelado_ready", recursive = TRUE, showWarnings = FALSE)
dir.create(CONFIG$output$base, recursive = TRUE, showWarnings = FALSE)
dir.create(CONFIG$output$logs, recursive = TRUE, showWarnings = FALSE)
dir.create(CONFIG$output$checks, recursive = TRUE, showWarnings = FALSE)
dir.create(CONFIG$output$figs, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(CONFIG$output$seleccion, "variables_json"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(CONFIG$output$seleccion, "diagnosticos"), recursive = TRUE, showWarnings = FALSE)

tiempos_fases <- list()

# Fase 0: OMITIDA (datos ya preparados)
cat(">>> FASE 0: Preparacion de datos [OMITIDA]\n")

# Fase 1
cat("\n>>> FASE 1: SELECCION DE VARIABLES <<<\n\n")
t1 <- Sys.time()
source("R/02_variable_selection/02d_ejecutar_seleccion.R")
t1_dur <- difftime(Sys.time(), t1, units = "mins")
tiempos_fases[["Fase 1: Seleccion"]] <- t1_dur
cat(sprintf("\n[OK] Fase 1 en %s\n", format(round(t1_dur, 1))))

# Fase 2
cat("\n>>> FASE 2: MODELO AMBIENTAL <<<\n\n")
t2 <- Sys.time()
source("R/03_modeling/03a_modelo_ambiental.R")
t2_dur <- difftime(Sys.time(), t2, units = "mins")
tiempos_fases[["Fase 2: Modelo ambiental"]] <- t2_dur
cat(sprintf("\n[OK] Fase 2 en %s\n", format(round(t2_dur, 1))))

# Fase 3
cat("\n>>> FASE 3: MODELO ESPACIAL <<<\n\n")
t3 <- Sys.time()
source("R/03_modeling/03b_modelo_espacial.R")
t3_dur <- difftime(Sys.time(), t3, units = "mins")
tiempos_fases[["Fase 3: Modelo espacial"]] <- t3_dur
cat(sprintf("\n[OK] Fase 3 en %s\n", format(round(t3_dur, 1))))

# Fase 4
cat("\n>>> FASE 4: INTERSECCION FUZZY <<<\n\n")
t4 <- Sys.time()
source("R/03_modeling/03c_interseccion_fuzzy.R")
t4_dur <- difftime(Sys.time(), t4, units = "mins")
tiempos_fases[["Fase 4: Interseccion"]] <- t4_dur
cat(sprintf("\n[OK] Fase 4 en %s\n", format(round(t4_dur, 1))))

# Fase 5
cat("\n>>> FASE 5: VALIDACION CRUZADA <<<\n\n")
t5 <- Sys.time()
source("R/03_modeling/03d_validacion_cv.R")
t5_dur <- difftime(Sys.time(), t5, units = "mins")
tiempos_fases[["Fase 5: Validacion"]] <- t5_dur
cat(sprintf("\n[OK] Fase 5 en %s\n", format(round(t5_dur, 1))))

# Fase 6
cat("\n>>> FASE 6: INCERTIDUMBRE <<<\n\n")
t6 <- Sys.time()
source("R/03_modeling/03e_incertidumbre.R")
t6_dur <- difftime(Sys.time(), t6, units = "mins")
tiempos_fases[["Fase 6: Incertidumbre"]] <- t6_dur
cat(sprintf("\n[OK] Fase 6 en %s\n", format(round(t6_dur, 1))))

# Fase 7
cat("\n>>> FASE 7: MAPAS ATLAS <<<\n\n")
t7 <- Sys.time()
source("R/04_visualization/04a_mapas_atlas.R")
t7_dur <- difftime(Sys.time(), t7, units = "mins")
tiempos_fases[["Fase 7: Mapas"]] <- t7_dur
cat(sprintf("\n[OK] Fase 7 en %s\n", format(round(t7_dur, 1))))

# Resumen
t_total <- difftime(Sys.time(), t_inicio, units = "mins")
cat("\n================================================================================\n")
cat("  PIPELINE 2014 COMPLETADO\n")
cat("================================================================================\n\n")
cat("TIEMPOS POR FASE:\n")
for (fase_nombre in names(tiempos_fases)) {
  cat(sprintf("  %-30s %s\n", fase_nombre, format(round(tiempos_fases[[fase_nombre]], 1))))
}
cat(sprintf("\nTiempo total: %s\n", format(round(t_total, 1))))
cat(sprintf("Output: %s\n\n", CONFIG$output$base))
