# ==============================================================================
# run_pipeline_pmin.R
# ==============================================================================
#
# Regenera interseccion, incertidumbre y mapas finales PNG con la
# interseccion fuzzy por minimo (pmin), escribiendo a
# output_version_final_pmin_20260420/modelos/{sp}/ sin tocar el run
# 20260417 (geometrica). Reutiliza ambiental/ y espacial/ via symlinks.
#
# USO: Rscript run_pipeline_pmin.R
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es)
# ==============================================================================

set.seed(42)

source("R/00_setup/00_config.R")

# Redirigir salidas a la nueva carpeta
CONFIG$output$base   <- "output_version_final_pmin_20260420/modelos"
CONFIG$output$logs   <- "output_version_final_pmin_20260420/logs"
CONFIG$output$checks <- "output_version_final_pmin_20260420/checks"
CONFIG$output$figs   <- "output_version_final_pmin_20260420/figs"

# Metodo de interseccion: minimo (pmin)
CONFIG$interseccion$metodo <- "pmin"

# Forzar re-ejecucion en la nueva carpeta (no hay checkpoints previos,
# pero lo ponemos explicito por claridad)
CONFIG$control$force_rerun <- TRUE

cat("\n================================================================\n")
cat("  PIPELINE PMIN — run final alternativo\n")
cat("  Base: ", CONFIG$output$base, "\n")
cat("  Metodo interseccion: ", CONFIG$interseccion$metodo, "\n")
cat("================================================================\n\n")

dir.create(CONFIG$output$base, recursive = TRUE, showWarnings = FALSE)
dir.create(CONFIG$output$logs, recursive = TRUE, showWarnings = FALSE)

# --- Fase 4: Interseccion fuzzy (pmin) ---------------------------------------
source("R/03_modeling/03c_interseccion_fuzzy.R")

# --- Fase 6: Incertidumbre ---------------------------------------------------
source("R/03_modeling/03e_incertidumbre.R")

# --- Fase 7: Mapas estilo SECEMU (PNG) --------------------------------------
source("R/04_visualization/04a_mapas_atlas.R")

cat("\n[OK] Pipeline pmin completado\n")
cat("sessionInfo ---\n")
print(sessionInfo())
