# ==============================================================================
# 04b_panel_incertidumbre.R - Paneles bivariados Favorabilidad x Incertidumbre
# ==============================================================================
#
# Genera panel 2x2: MESS, Bootstrap W, U final, Bivariado
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

if (!exists("CONFIG")) source("R/00_setup/00_config.R")
source("R/utils/utils_mapas.R")

suppressPackageStartupMessages({
  library(tidyverse)
  library(sf)
  library(scico)
  library(patchwork)
})

cat("\n=== PANELES DE INCERTIDUMBRE ===\n\n")

grid_data <- readRDS(CONFIG$paths$grid_predictores)
malla <- grid_data$malla_union

especies_gremios <- read_csv(CONFIG$paths$especies_gremios, show_col_types = FALSE) %>%
  filter(modelar == TRUE)

if (!is.null(CONFIG$especies$piloto)) {
  especies <- CONFIG$especies$piloto
} else {
  especies <- especies_gremios$especie
}

for (sp in especies) {
  sp_file <- str_replace_all(sp, " ", "_")
  dir_int <- file.path(CONFIG$output$base, sp_file, "interseccion")
  dir_unc <- file.path(CONFIG$output$base, sp_file, "incertidumbre")
  dir_out <- file.path(CONFIG$output$base, sp_file, "mapas")

  unc_file <- file.path(dir_unc, "incertidumbre.csv")
  int_file <- file.path(dir_int, "predicciones.csv")
  if (!file.exists(unc_file) || !file.exists(int_file)) next

  cat(sprintf("  %s...\n", sp))

  pred_unc <- read_csv(unc_file, show_col_types = FALSE)
  pred_int <- read_csv(int_file, show_col_types = FALSE)

  tryCatch({
    # MESS map
    datos_malla_mess <- malla
    datos_malla_mess$valor <- pred_unc$MESS
    limites <- tryCatch(get_limites_iberia(st_crs(malla)$epsg), error = function(e) NULL)

    p1 <- ggplot() +
      geom_sf(data = datos_malla_mess, aes(fill = valor), color = NA) +
      scale_fill_gradientn(colors = PALETAS$mess, name = "MESS", na.value = "grey95") +
      labs(title = "MESS (Extrapolacion)") + theme_void() +
      theme(plot.title = element_text(hjust = 0.5, face = "bold"), legend.position = "bottom")
    if (!is.null(limites)) p1 <- p1 + geom_sf(data = limites, fill = NA, color = "grey30", linewidth = 0.3)

    p2 <- mapa_incertidumbre(malla, pred_unc$W_bootstrap, "IC 95% (Bootstrap)")
    p3 <- mapa_incertidumbre(malla, pred_unc$U_final, "Incertidumbre Final")
    p4 <- mapa_bivariado(malla, pred_int$F_final_mean, pred_unc$U_final)

    panel <- (p1 | p2) / (p3 | p4) +
      plot_annotation(title = sprintf("Componentes de Incertidumbre - %s", sp),
                      theme = theme(plot.title = element_text(hjust = 0.5, face = "bold.italic", size = 16)))

    guardar_mapa(panel, file.path(dir_out, "panel_incertidumbre.png"), width = 24, height = 20)
  }, error = function(e) cat(sprintf("    Error: %s\n", e$message)))
}

cat("\n[OK] Paneles de incertidumbre completados\n")
