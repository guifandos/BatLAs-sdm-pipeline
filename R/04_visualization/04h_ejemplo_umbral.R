# ==============================================================================
# 04h_ejemplo_umbral.R - Ejemplo visual de umbral de representacion F_final
# ==============================================================================
# Genera mapas comparativos (sin umbral vs F_final < 0.25 -> blanco) para
# dos especies con favorabilidad residual en Baleares. Los datos numericos
# subyacentes no se modifican: es puramente un cambio de representacion
# para evaluar si conviene aplicar un umbral visual en la edicion final.
# ==============================================================================

set.seed(42)
if (!exists("CONFIG")) source("R/00_setup/00_config.R")
source("R/utils/utils_mapas_momat.R")

suppressPackageStartupMessages({
  library(tidyverse)
  library(sf)
  library(patchwork)
})

CONFIG$output$base <- "output_version_final_pmin_20260420/modelos"

DIR_OUT <- "output_png_final_pmin/_ejemplo_umbral_025"
dir.create(DIR_OUT, recursive = TRUE, showWarnings = FALSE)

ESPECIES <- c("Rhinolophus euryale", "Nyctalus noctula")
UMBRAL <- 0.25

# Datos base
malla <- readRDS(CONFIG$paths$malla_union)
if (is.na(st_crs(malla))) st_crs(malla) <- 25830
provincias_tmp <- st_read("data/shapefiles/admin/Provincias.shp", quiet = TRUE)
crs_admin <- st_crs(provincias_tmp); rm(provincias_tmp)
malla_ll <- st_transform(malla, crs_admin)
datos_pa <- readRDS(CONFIG$paths$pa_data)
cuadriculas <- datos_pa$CUADRICULA

for (sp in ESPECIES) {
  sp_file <- str_replace_all(sp, " ", "_")
  dir_sp <- file.path(CONFIG$output$base, sp_file)

  pred_int <- read_csv(file.path(dir_sp, "interseccion/predicciones.csv"),
                       show_col_types = FALSE)
  pred_int$CUADRICULA <- cuadriculas

  datos_mapa <- malla_ll %>%
    select(CUADRICULA, geometry) %>%
    left_join(pred_int %>% select(CUADRICULA, F_int = F_final_mean),
              by = "CUADRICULA") %>%
    mutate(F_int_umbral = ifelse(F_int < UMBRAL, NA_real_, F_int))

  p1 <- crear_mapa_momat(datos_mapa, "F_int",
                         sprintf("%s — Sin umbral (actual)", sp)) +
    theme(plot.title = element_text(size = 11, face = "italic"))

  p2 <- crear_mapa_momat(datos_mapa, "F_int_umbral",
                         sprintf("%s — Umbral F ≥ %.2f", sp, UMBRAL)) +
    theme(plot.title = element_text(size = 11, face = "italic"))

  panel <- p1 + p2 +
    plot_layout(guides = "collect") +
    plot_annotation(
      title = sp,
      subtitle = sprintf(
        "Izquierda: mapa actual (pmin, sin umbral). Derecha: cuadriculas con F < %.2f en blanco.",
        UMBRAL),
      theme = theme(
        plot.title = element_text(size = 13, face = "bold.italic", hjust = 0),
        plot.subtitle = element_text(size = 9, hjust = 0,
                                     margin = margin(0, 0, 6, 0)),
        plot.background = element_rect(fill = "white", color = NA)
      )
    )

  ggsave(file.path(DIR_OUT, paste0(sp_file, ".png")),
         panel, width = 24, height = 10, units = "cm", dpi = 150, bg = "white")
  cat("[OK]", sp_file, "\n")
}

cat(sprintf("\nEjemplos guardados en %s/\n", DIR_OUT))
