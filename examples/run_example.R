# ==============================================================================
# run_example.R — Run the full SDM pipeline on simulated data
# ==============================================================================
#
# Demonstrates the complete pipeline workflow using synthetic data generated
# by simulate_data.R. Processes one species (Cavebat simulated) through all
# phases: variable selection, environmental model, spatial model, fuzzy
# intersection, cross-validation, uncertainty, and atlas maps.
#
# PREREQUISITES:
#   source("examples/simulate_data.R")  # generates data/simulated/
#
# USAGE:
#   source("examples/run_example.R")
#
# RUNTIME: ~5-10 minutes (reduced bootstrap: 50 iterations)
#
# ==============================================================================

cat("\n")
cat("================================================================================\n")
cat("  EXAMPLE RUN: SDM Pipeline with Simulated Data\n")
cat("================================================================================\n\n")

# ==============================================================================
# STEP 1: VERIFY SIMULATED DATA EXISTS
# ==============================================================================

if (!file.exists("examples/simulate_data.R")) {
  stop(paste0(
    "This script must be run from the project root directory.\n",
    "  Current directory: ", getwd(), "\n",
    "  Use setwd() or open the .Rproj to change to the correct directory."
  ))
}

simulated_files <- c(
  "data/simulated/PAxENV_simulated.rds",
  "data/simulated/grid_simulated.rds",
  "data/simulated/esfuerzo_simulated.rds",
  "data/simulated/especies_gremios_sim.csv"
)

missing <- simulated_files[!file.exists(simulated_files)]
if (length(missing) > 0) {
  cat("Simulated data not found. Generating now...\n\n")
  source("examples/simulate_data.R")
}

cat("[OK] Simulated data available\n\n")

# ==============================================================================
# STEP 2: LOAD PACKAGES AND CONFIGURATION
# ==============================================================================

cat("--- Loading packages and configuration ---\n")
source("R/00_setup/00_packages.R")
source("R/00_setup/00_config.R")
source("R/utils/utils_logging.R")

# ==============================================================================
# STEP 3: OVERRIDE CONFIG FOR SIMULATED DATA
# ==============================================================================
# Redirect all data paths to the simulated data, reduce bootstrap iterations
# for a fast demonstration run, and select one pilot species.

cat("--- Configuring pipeline for simulated data ---\n\n")

# --- Data paths: point to simulated files ---
CONFIG$paths$pa_data        <- "data/simulated/PAxENV_simulated.rds"
CONFIG$paths$grid_predictores <- "data/simulated/grid_simulated.rds"
CONFIG$paths$esfuerzo       <- "data/simulated/esfuerzo_simulated.rds"
CONFIG$paths$especies_gremios <- "data/simulated/especies_gremios_sim.csv"

# --- Output: separate folder to avoid mixing with real results ---
CONFIG$output$base      <- "output/example_simulated/modelos"
CONFIG$output$seleccion <- "output/example_simulated/seleccion_variables"
CONFIG$output$logs      <- "output/example_simulated/logs"
CONFIG$output$checks    <- "output/example_simulated/checks"
CONFIG$output$figs      <- "output/example_simulated/figs"
CONFIG$paths$variables_json <- "output/example_simulated/seleccion_variables/variables_json"

# --- Species: process one species as demonstration ---
CONFIG$especies$piloto <- c("Cavebat simulated")

# --- Reduce computation for fast execution ---
CONFIG$ambiental$n_bootstrap <- 50     # (production: 200)
CONFIG$espacial$n_bootstrap  <- 50     # (production: 200)
CONFIG$validacion$n_rep      <- 2      # (production: 10)
CONFIG$seleccion$n_boot_stability <- 30  # (production: 100)

# --- Phase control: skip raw data preparation (already done by simulate) ---
CONFIG$control$ejecutar$preparacion_datos  <- FALSE
CONFIG$control$ejecutar$seleccion_variables <- TRUE
CONFIG$control$ejecutar$modelo_ambiental   <- TRUE
CONFIG$control$ejecutar$modelo_espacial    <- TRUE
CONFIG$control$ejecutar$interseccion       <- TRUE
CONFIG$control$ejecutar$validacion         <- TRUE
CONFIG$control$ejecutar$incertidumbre      <- TRUE
CONFIG$control$ejecutar$mapas              <- TRUE

# --- Force rerun (no previous checkpoints) ---
CONFIG$control$force_rerun <- TRUE

# --- Minimum presences: lower threshold for simulated data ---
CONFIG$ambiental$min_presencias <- 20
CONFIG$ambiental$min_ausencias  <- 20

cat(sprintf("  Species:     %s\n", paste(CONFIG$especies$piloto, collapse = ", ")))
cat(sprintf("  Bootstrap:   %d iterations\n", CONFIG$ambiental$n_bootstrap))
cat(sprintf("  CV reps:     %d\n", CONFIG$validacion$n_rep))
cat(sprintf("  Output:      %s\n\n", CONFIG$output$base))

# ==============================================================================
# STEP 4: CREATE OUTPUT DIRECTORIES
# ==============================================================================

for (d in c(CONFIG$output$base, CONFIG$output$seleccion, CONFIG$output$logs,
            CONFIG$output$checks, CONFIG$output$figs,
            file.path(CONFIG$output$seleccion, "variables_json"),
            file.path(CONFIG$output$seleccion, "diagnosticos"))) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

# ==============================================================================
# STEP 5: INITIALIZE LOGGING
# ==============================================================================

init_log()
log_event("example", "", "INFO", "Example pipeline started (simulated data)")

t_inicio <- Sys.time()
tiempos_fases <- list()

# ==============================================================================
# PHASE 1: VARIABLE SELECTION
# ==============================================================================
# Runs the 7-phase selection pipeline. Because we use simulated data with
# known variable names, the guild system will identify relevant predictors
# based on the species' guild assignments.

cat("\n>>> PHASE 1: VARIABLE SELECTION <<<\n\n")
t1 <- Sys.time()
source("R/02_variable_selection/02d_ejecutar_seleccion.R")
t1_dur <- difftime(Sys.time(), t1, units = "mins")
tiempos_fases[["Phase 1: Selection"]] <- t1_dur
cat(sprintf("\n[OK] Phase 1 completed in %s\n", format(round(t1_dur, 1))))

# ==============================================================================
# PHASE 2: ENVIRONMENTAL MODEL (GLM + Favorability)
# ==============================================================================

cat("\n>>> PHASE 2: ENVIRONMENTAL MODEL <<<\n\n")
t2 <- Sys.time()
source("R/03_modeling/03a_modelo_ambiental.R")
t2_dur <- difftime(Sys.time(), t2, units = "mins")
tiempos_fases[["Phase 2: Environmental"]] <- t2_dur
cat(sprintf("\n[OK] Phase 2 completed in %s\n", format(round(t2_dur, 1))))

# ==============================================================================
# PHASE 3: SPATIAL MODEL (GAM selected by AICc)
# ==============================================================================

cat("\n>>> PHASE 3: SPATIAL MODEL <<<\n\n")
t3 <- Sys.time()
source("R/03_modeling/03b_modelo_espacial.R")
t3_dur <- difftime(Sys.time(), t3, units = "mins")
tiempos_fases[["Phase 3: Spatial"]] <- t3_dur
cat(sprintf("\n[OK] Phase 3 completed in %s\n", format(round(t3_dur, 1))))

# ==============================================================================
# PHASE 4: FUZZY INTERSECTION
# ==============================================================================

cat("\n>>> PHASE 4: FUZZY INTERSECTION <<<\n\n")
t4 <- Sys.time()
source("R/03_modeling/03c_interseccion_fuzzy.R")
t4_dur <- difftime(Sys.time(), t4, units = "mins")
tiempos_fases[["Phase 4: Fuzzy"]] <- t4_dur
cat(sprintf("\n[OK] Phase 4 completed in %s\n", format(round(t4_dur, 1))))

# ==============================================================================
# PHASE 5: SPATIAL CROSS-VALIDATION
# ==============================================================================

cat("\n>>> PHASE 5: CROSS-VALIDATION <<<\n\n")
t5 <- Sys.time()
source("R/03_modeling/03d_validacion_cv.R")
t5_dur <- difftime(Sys.time(), t5, units = "mins")
tiempos_fases[["Phase 5: Validation"]] <- t5_dur
cat(sprintf("\n[OK] Phase 5 completed in %s\n", format(round(t5_dur, 1))))

# ==============================================================================
# PHASE 6: UNCERTAINTY
# ==============================================================================

cat("\n>>> PHASE 6: UNCERTAINTY <<<\n\n")
t6 <- Sys.time()
source("R/03_modeling/03e_incertidumbre.R")
t6_dur <- difftime(Sys.time(), t6, units = "mins")
tiempos_fases[["Phase 6: Uncertainty"]] <- t6_dur
cat(sprintf("\n[OK] Phase 6 completed in %s\n", format(round(t6_dur, 1))))

# ==============================================================================
# PHASE 7: ATLAS MAPS
# ==============================================================================

cat("\n>>> PHASE 7: ATLAS MAPS <<<\n\n")
t7 <- Sys.time()
source("R/04_visualization/04a_mapas_atlas.R")
t7_dur <- difftime(Sys.time(), t7, units = "mins")
tiempos_fases[["Phase 7: Maps"]] <- t7_dur
cat(sprintf("\n[OK] Phase 7 completed in %s\n", format(round(t7_dur, 1))))

# ==============================================================================
# SUMMARY
# ==============================================================================

t_total <- difftime(Sys.time(), t_inicio, units = "mins")

cat("\n")
cat("================================================================================\n")
cat("  EXAMPLE PIPELINE COMPLETED\n")
cat("================================================================================\n\n")

cat("Phase timings:\n")
for (fname in names(tiempos_fases)) {
  cat(sprintf("  %-30s %s\n", fname, format(round(tiempos_fases[[fname]], 1))))
}

cat(sprintf("\nTotal time: %s\n", format(round(t_total, 1))))
cat(sprintf("Output:     %s\n\n", CONFIG$output$base))

# Check results
sp_file <- "Cavebat_simulated"
dir_sp <- file.path(CONFIG$output$base, sp_file)
phases_check <- c(
  "environmental" = file.path(dir_sp, "ambiental", "predicciones.csv"),
  "spatial"       = file.path(dir_sp, "espacial", "predicciones.csv"),
  "intersection"  = file.path(dir_sp, "interseccion", "predicciones.csv"),
  "validation"    = file.path(dir_sp, "validacion", "metricas_cv.csv"),
  "uncertainty"   = file.path(dir_sp, "incertidumbre", "incertidumbre.csv"),
  "maps"          = file.path(dir_sp, "mapas", "checkpoint_mapas.txt")
)

cat("Results check:\n")
for (phase in names(phases_check)) {
  ok <- file.exists(phases_check[[phase]])
  cat(sprintf("  %s %s\n", if (ok) "[OK]" else "[!!]", phase))
}

# Show holdout metrics if available
met_file <- file.path(dir_sp, "ambiental", "metricas_holdout.csv")
if (file.exists(met_file)) {
  met <- read.csv(met_file)
  cat(sprintf("\nHoldout metrics: AUC = %.3f, TSS = %.3f\n", met$AUC[1], met$TSS[1]))
}

log_event("example", "", "INFO",
          sprintf("Example pipeline completed in %s", format(round(t_total, 1))))

cat("\n================================================================================\n")
cat("  Inspect results in: ", CONFIG$output$base, "/Cavebat_simulated/\n")
cat("================================================================================\n\n")
