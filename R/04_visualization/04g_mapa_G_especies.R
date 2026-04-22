# ==============================================================================
# 04g_mapa_G_especies.R
# ==============================================================================
#
# Genera el "mapa G" (F_final grande con inset de incertidumbre + bivariado
# F x U + Presencia/Ausencia, estilo MOMAT) para las 29 especies del atlas.
#
# Produce DOS variantes por especie:
#   1. Con pie de figura explicativo (para lector no especialista)
#   2. Sin pie de figura (estilo MOMAT puro)
#
# Asume que CONFIG$output$base apunta al run deseado (por defecto pmin).
# Si no esta seteado, usa output_version_final_pmin_20260420/modelos.
#
# SALIDA:
#   output_png_final_pmin/_mapas_G_con_pie/{Especie}.png
#   output_png_final_pmin/_mapas_G_sin_pie/{Especie}.png
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es)
# ==============================================================================

set.seed(42)

if (!exists("CONFIG")) source("R/00_setup/00_config.R")
source("R/utils/utils_mapas_momat.R")

suppressPackageStartupMessages({
  library(tidyverse)
  library(sf)
  library(patchwork)
  library(grid)
})

# Permite override por variable de entorno o asume la pmin por defecto
if (identical(CONFIG$output$base, "output_version_final_20260417/modelos")) {
  CONFIG$output$base <- "output_version_final_pmin_20260420/modelos"
  cat("[info] CONFIG$output$base redirigido a:", CONFIG$output$base, "\n")
}

DIR_OUT_CON_PIE <- "output_png_final_pmin/_mapas_G_con_pie"
DIR_OUT_SIN_PIE <- "output_png_final_pmin/_mapas_G_sin_pie"
WIDTH_CM  <- 25
HEIGHT_CM <- 18
DPI       <- 300

dir.create(DIR_OUT_CON_PIE, recursive = TRUE, showWarnings = FALSE)
dir.create(DIR_OUT_SIN_PIE, recursive = TRUE, showWarnings = FALSE)

# ------------------------------------------------------------------------------
# Datos base
# ------------------------------------------------------------------------------

malla <- readRDS(CONFIG$paths$malla_union)
if (is.na(st_crs(malla))) st_crs(malla) <- 25830
provincias_tmp <- st_read("data/shapefiles/admin/Provincias.shp", quiet = TRUE)
crs_admin <- st_crs(provincias_tmp); rm(provincias_tmp)
malla_ll <- st_transform(malla, crs_admin)

datos_pa <- readRDS(CONFIG$paths$pa_data)
cuadriculas <- datos_pa$CUADRICULA

especies_gremios <- read_csv(CONFIG$paths$especies_gremios, show_col_types = FALSE) %>%
  filter(modelar == TRUE)
especies <- especies_gremios$especie
especies <- setdiff(especies, CONFIG$especies$excluir)

# ------------------------------------------------------------------------------
# Paleta + funciones locales (replicas minimas de 04f)
# ------------------------------------------------------------------------------

COLORES_STATUS <- c(
  "No muestreado" = "#F2F2F2",
  "Ausencia"      = "#BDBDBD",
  "Presencia"     = "#2D1B4E"
)

theme_compacto <- theme(
  plot.title = element_text(size = 9, face = "bold", hjust = 0.5,
                            margin = margin(2, 0, 2, 0)),
  legend.key.height = unit(5, "mm"),
  legend.key.width = unit(2.5, "mm"),
  legend.text = element_text(size = 6),
  legend.title = element_text(size = 7),
  plot.margin = margin(2, 2, 2, 2)
)

crear_mapa_presencias_simple <- function(datos_sf, titulo,
                                         shp_dir = "data/shapefiles/admin") {
  admin <- cargar_admin(shp_dir)
  ggplot() +
    geom_sf(data = admin$limitrofes, fill = "grey93", color = NA) +
    geom_sf(data = datos_sf, aes(fill = status), color = NA) +
    geom_sf(data = admin$provincias, fill = NA, color = "grey30", linewidth = 0.15) +
    geom_sf(data = admin$comunidades, fill = NA, color = "black", linewidth = 0.35) +
    scale_fill_manual(values = COLORES_STATUS, name = NULL, drop = FALSE,
                      na.value = "#F2F2F2") +
    coord_sf(xlim = XLIM_MOMAT, ylim = YLIM_MOMAT, expand = FALSE) +
    labs(title = titulo) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 11, face = "bold", hjust = 0.5),
      panel.grid = element_blank(),
      axis.text = element_blank(), axis.title = element_blank(),
      axis.ticks = element_blank(),
      plot.background = element_rect(fill = "white", color = NA),
      panel.background = element_rect(fill = "white", color = NA),
      legend.position = "bottom",
      legend.text = element_text(size = 7),
      legend.key.size = unit(3, "mm"),
      legend.margin = margin(0, 0, 0, 0),
      plot.margin = margin(5, 5, 5, 5)
    ) +
    guides(fill = guide_legend(nrow = 1, byrow = TRUE,
                               override.aes = list(color = "grey70", linewidth = 0.1)))
}

# ------------------------------------------------------------------------------
# Pie de figura (editar aqui para ajustar el texto en todas las laminas)
# ------------------------------------------------------------------------------

PIE_FIGURA <- paste0(
  "Mapa grande: favorabilidad integrada (0-1); el recuadro muestra la ",
  "incertidumbre. Arriba derecha, bivariado F x U: cada eje se divide en ",
  "terciles A (Alta), M (Media) y B (Baja); el horizontal representa la ",
  "favorabilidad y el vertical la incertidumbre. Abajo derecha, ",
  "Presencia/Ausencia: cuadriculas UTM 10 x 10 km con cita (Presencia), ",
  "muestreadas sin cita (Ausencia) y no muestreadas."
)

# ------------------------------------------------------------------------------
# Bucle especies
# ------------------------------------------------------------------------------

n_ok <- 0; n_err <- 0
for (sp in especies) {
  cat(sprintf("\n--- %s ---\n", sp))
  sp_file <- str_replace_all(sp, " ", "_")
  dir_sp <- file.path(CONFIG$output$base, sp_file)

  files_req <- c(
    file.path(dir_sp, "ambiental/predicciones.csv"),
    file.path(dir_sp, "interseccion/predicciones.csv"),
    file.path(dir_sp, "incertidumbre/incertidumbre.csv")
  )
  if (!all(file.exists(files_req))) {
    cat("  [SKIP] faltan inputs\n"); next
  }

  tryCatch({
    pred_amb <- read_csv(files_req[1], show_col_types = FALSE)
    pred_int <- read_csv(files_req[2], show_col_types = FALSE)
    pred_unc <- read_csv(files_req[3], show_col_types = FALSE)
    stopifnot(nrow(pred_amb) == length(cuadriculas),
              nrow(pred_int) == length(cuadriculas),
              nrow(pred_unc) == length(cuadriculas))
    pred_amb$CUADRICULA <- cuadriculas
    pred_int$CUADRICULA <- cuadriculas
    pred_unc$CUADRICULA <- cuadriculas

    datos_mapa <- malla_ll %>%
      select(CUADRICULA, geometry) %>%
      left_join(pred_amb %>% select(CUADRICULA, F_amb = F_glm_mean), by = "CUADRICULA") %>%
      left_join(pred_int %>% select(CUADRICULA, F_int = F_final_mean), by = "CUADRICULA") %>%
      left_join(pred_unc %>% select(CUADRICULA, U_final, MESS), by = "CUADRICULA") %>%
      mutate(
        F_class = clasificar_terciles_momat(F_int),
        U_class = clasificar_terciles_momat(U_final),
        bivariado = map2_chr(F_class, U_class, ~{
          if (is.na(.x) || is.na(.y)) NA_character_
          else MATRIZ_BIVARIADO_MOMAT[.x, .y]
        })
      )

    sp_col <- paste0("sp_", sp)
    if (!sp_col %in% names(datos_pa)) sp_col <- sp
    pa_status <- tibble(
      CUADRICULA = datos_pa$CUADRICULA,
      muestreado = datos_pa$muestreado,
      sp_val     = datos_pa[[sp_col]]
    ) %>%
      mutate(status = case_when(
        muestreado == 0 ~ "No muestreado",
        sp_val == 1     ~ "Presencia",
        TRUE            ~ "Ausencia"
      ),
      status = factor(status, levels = c("No muestreado", "Ausencia", "Presencia")))

    datos_mapa <- datos_mapa %>%
      left_join(pa_status %>% select(CUADRICULA, status), by = "CUADRICULA")

    # --- Componentes del panel G (sin subtitulos de panel) -------------------
    p_main <- crear_mapa_con_inset(
      datos_mapa, "F_int", "",
      col_incert = "U_final"
    ) + theme(plot.title = element_blank())

    p_biv  <- crear_mapa_bivariado_momat(datos_mapa, "") +
      theme_compacto + theme(plot.title = element_blank())
    p_pres <- crear_mapa_presencias_simple(datos_mapa, "") +
      theme_compacto + theme(plot.title = element_blank())

    # --- Variante SIN pie (estilo MOMAT puro) -------------------------------
    panel_sin <- p_main + (p_biv / p_pres) +
      plot_layout(widths = c(2, 1)) +
      plot_annotation(
        title = sp,
        theme = theme(
          plot.title = element_text(size = 14, face = "bold.italic", hjust = 0),
          plot.background = element_rect(fill = "white", color = NA),
          plot.margin = margin(8, 8, 5, 8)
        )
      )
    ggsave(file.path(DIR_OUT_SIN_PIE, paste0(sp_file, ".png")),
           panel_sin, width = WIDTH_CM, height = HEIGHT_CM, units = "cm",
           dpi = DPI, bg = "white")

    # --- Variante CON pie explicativo ---------------------------------------
    panel_con <- p_main + (p_biv / p_pres) +
      plot_layout(widths = c(2, 1)) +
      plot_annotation(
        title = sp,
        caption = str_wrap(PIE_FIGURA, width = 150),
        theme = theme(
          plot.title = element_text(size = 14, face = "bold.italic", hjust = 0),
          plot.caption = element_text(size = 8, hjust = 0, lineheight = 1.15,
                                      margin = margin(6, 0, 0, 0)),
          plot.background = element_rect(fill = "white", color = NA),
          plot.margin = margin(8, 8, 5, 8)
        )
      )
    ggsave(file.path(DIR_OUT_CON_PIE, paste0(sp_file, ".png")),
           panel_con, width = WIDTH_CM, height = HEIGHT_CM + 2, units = "cm",
           dpi = DPI, bg = "white")

    cat("  [OK]\n")
    n_ok <- n_ok + 1
  }, error = function(e) {
    cat(sprintf("  [ERROR] %s\n", e$message))
    n_err <<- n_err + 1
  })
}

cat(sprintf("\n[OK] Mapa G generado: %d ok | %d error\n", n_ok, n_err))
cat("Pie de figura guardado como borrador en el script (variable PIE_FIGURA).\n")
