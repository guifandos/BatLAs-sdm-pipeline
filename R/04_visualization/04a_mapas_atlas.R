# ==============================================================================
# 04a_mapas_atlas.R - Generacion de mapas estilo SECEMU
# ==============================================================================
#
# INPUT:  output/modelos/{especie}/
#         data/processed/predictores_all.rds
# OUTPUT: output/modelos/{especie}/mapas/
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

source("R/00_setup/00_config.R")
source("R/utils/utils_checkpoints.R")
source("R/utils/utils_mapas.R")

suppressPackageStartupMessages({
  library(tidyverse)
  library(sf)
  library(scico)
  library(patchwork)
  library(jsonlite)
})

cat("\n========================================\n")
cat("  FASE 7: MAPAS ATLAS\n")
cat("========================================\n\n")

grid_data <- readRDS(CONFIG$paths$grid_predictores)

if (!is.null(grid_data$malla_union)) {
  malla <- grid_data$malla_union
} else {
  cat("[ERROR] No se encontro malla_union en predictores_all.rds\n")
  stop("Sin geometrias")
}

datos_pa <- readRDS(CONFIG$paths$pa_data)

especies_gremios <- read_csv(CONFIG$paths$especies_gremios, show_col_types = FALSE) %>%
  filter(modelar == TRUE)

if (!is.null(CONFIG$especies$piloto)) {
  especies <- CONFIG$especies$piloto
} else {
  especies <- especies_gremios$especie
}
especies <- setdiff(especies, CONFIG$especies$excluir)

for (sp in especies) {
  cat(sprintf("\n--- %s ---\n", sp))

  if (!CONFIG$control$force_rerun &&
      checkpoint_exists(sp, CONFIG$output$base, "mapas")) {
    cat("  Ya completado\n")
    next
  }

  sp_file <- str_replace_all(sp, " ", "_")
  dir_amb <- file.path(CONFIG$output$base, sp_file, "ambiental")
  dir_int <- file.path(CONFIG$output$base, sp_file, "interseccion")
  dir_unc <- file.path(CONFIG$output$base, sp_file, "incertidumbre")
  dir_out <- file.path(CONFIG$output$base, sp_file, "mapas")
  dir.create(dir_out, recursive = TRUE, showWarnings = FALSE)

  # Check required files
  amb_file <- file.path(dir_amb, "predicciones.csv")
  int_file <- file.path(dir_int, "predicciones.csv")
  unc_file <- file.path(dir_unc, "incertidumbre.csv")

  if (!file.exists(int_file) || !file.exists(unc_file)) {
    cat("  [SKIP] Faltan predicciones\n")
    next
  }

  pred_amb <- read_csv(amb_file, show_col_types = FALSE)
  pred_int <- read_csv(int_file, show_col_types = FALSE)
  pred_unc <- read_csv(unc_file, show_col_types = FALSE)

  # PA observada
  pa_obs <- datos_pa[[sp]]

  # Panel SECEMU (2x2)
  tryCatch({
    p1 <- mapa_favorabilidad(malla, pred_amb$F_glm_mean, "Modelo Ambiental")
    p2 <- mapa_favorabilidad(malla, pred_int$F_final_mean, "Modelo Final")
    p3 <- mapa_incertidumbre(malla, pred_unc$U_final, "Incertidumbre")
    p4 <- mapa_pa(malla, pa_obs, "Presencia Observada")

    panel <- (p1 | p2) / (p3 | p4) +
      plot_annotation(title = sp, subtitle = "Atlas de Murcielagos - SECEMU",
                      theme = theme(plot.title = element_text(hjust = 0.5, face = "bold.italic", size = 16)))

    guardar_mapa(panel, file.path(dir_out, "panel_SECEMU.png"),
                 width = 24, height = 20)
  }, error = function(e) cat(sprintf("  Error en panel SECEMU: %s\n", e$message)))

  # Mapa bivariado
  tryCatch({
    p_biv <- mapa_bivariado(malla, pred_int$F_final_mean, pred_unc$U_final)
    guardar_mapa(p_biv, file.path(dir_out, "mapa_bivariado.png"),
                 width = 16, height = 12)
  }, error = function(e) cat(sprintf("  Error en bivariado: %s\n", e$message)))

  create_checkpoint(sp, CONFIG$output$base, "mapas")
  cat("  [OK] Mapas generados\n")
}

cat("\n[OK] Fase 7 completada\n")
