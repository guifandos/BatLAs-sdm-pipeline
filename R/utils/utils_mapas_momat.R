# ==============================================================================
# utils_mapas_momat.R - Funciones de visualizacion estilo MOMAT
# ==============================================================================
# Paletas y estilo basados en:
# Santoro et al. - terrestrial-nonflying-mammal-modeling (MOMAT)
# Shapefiles administrativos: Provincias, Comunidades, Paises limitrofes
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(sf)
  library(patchwork)
  library(grid)
  library(scales)
})

# ==============================================================================
# PALETAS Y COLORES (MOMAT)
# ==============================================================================

PALETA_FAV_MOMAT <- c("#FFFFFF", "#FFF0B3", "#FFD633", "#FFB300", "#A63C00", "#661A00")
PALETA_INCERT_MOMAT <- c("#FFFFFF", "#ABD9E9", "#74ADD1", "#4575B4", "#313695")
PALETA_INCERT_MINI <- c("#FFFFFF", "#FFF5B3", "#91B2E0", "#313695")
COLORES_PA_MOMAT <- c("0" = "grey90", "1" = "#2C7BB6")

# Matriz bivariado (misma del atlas original)
MATRIZ_BIVARIADO_MOMAT <- matrix(c(
  "#3182bd", "#9ecae1", "#deebf7",
  "#feb24c", "#fed976", "#ffffcc",
  "#006d2c", "#31a354", "#74c476"
), nrow = 3, byrow = TRUE)

# Extension geografica MOMAT
XLIM_MOMAT <- c(-10, 4.5)
YLIM_MOMAT <- c(35.2, 44.5)

# Dimensiones
DPI_MOMAT <- 300
WIDTH_MOMAT <- 8
HEIGHT_MOMAT <- 6

# ==============================================================================
# CAPAS ADMINISTRATIVAS (cache)
# ==============================================================================

.admin_cache <- new.env(parent = emptyenv())

cargar_admin <- function(shp_dir = "data/shapefiles/admin") {
  if (is.null(.admin_cache$loaded)) {
    .admin_cache$limitrofes <- st_read(
      file.path(shp_dir, "Paises_limitrofes_AtlasyLR.shp"), quiet = TRUE
    )
    .admin_cache$provincias <- st_read(
      file.path(shp_dir, "Provincias.shp"), quiet = TRUE
    )
    .admin_cache$comunidades <- st_read(
      file.path(shp_dir, "Comunidades.shp"), quiet = TRUE
    )

    # Asegurar CRS consistente (lon/lat)
    crs_ref <- st_crs(.admin_cache$provincias)
    .admin_cache$limitrofes <- st_transform(.admin_cache$limitrofes, crs_ref)
    .admin_cache$comunidades <- st_transform(.admin_cache$comunidades, crs_ref)

    .admin_cache$loaded <- TRUE
    message("[OK] Capas administrativas MOMAT cargadas")
  }
  list(
    limitrofes = .admin_cache$limitrofes,
    provincias = .admin_cache$provincias,
    comunidades = .admin_cache$comunidades
  )
}

# ==============================================================================
# FUNCION: CLASIFICAR TERCILES
# ==============================================================================

clasificar_terciles_momat <- function(x) {
  breaks <- quantile(x, probs = c(0, 1/3, 2/3, 1), na.rm = TRUE)
  cut(x, breaks = breaks, labels = FALSE, include.lowest = TRUE)
}

# ==============================================================================
# FUNCION: MAPA BASE ESTILO MOMAT
# ==============================================================================

crear_mapa_momat <- function(datos_sf, col_valor, titulo,
                             paleta = PALETA_FAV_MOMAT,
                             limits = c(0, 1),
                             legend_title = NULL,
                             discreto = FALSE,
                             na_color = "grey90",
                             shp_dir = "data/shapefiles/admin") {

  admin <- cargar_admin(shp_dir)

  p <- ggplot() +
    geom_sf(data = admin$limitrofes, fill = "grey90", color = NA) +
    geom_sf(data = datos_sf, aes(fill = .data[[col_valor]]), color = NA) +
    geom_sf(data = admin$provincias, fill = NA, color = "black", linewidth = 0.2) +
    geom_sf(data = admin$comunidades, fill = NA, color = "black", linewidth = 0.4)

  if (discreto) {
    p <- p + scale_fill_manual(
      values = paleta, na.value = na_color, name = legend_title
    )
  } else {
    p <- p + scale_fill_gradientn(
      colours = paleta, limits = limits,
      na.value = na_color, name = legend_title,
      oob = scales::squish
    )
  }

  p + coord_sf(xlim = XLIM_MOMAT, ylim = YLIM_MOMAT, expand = FALSE) +
    labs(title = titulo) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 11, face = "bold", hjust = 0.5),
      panel.grid = element_blank(),
      legend.title = element_blank(),
      axis.text = element_blank(),
      axis.title = element_blank(),
      axis.ticks = element_blank(),
      plot.background = element_rect(fill = "white", color = NA),
      panel.background = element_rect(fill = "white", color = NA),
      plot.margin = margin(5, 5, 5, 5)
    )
}

# ==============================================================================
# FUNCION: MINI-MAPA INCERTIDUMBRE (para inset)
# ==============================================================================

crear_inset_incert <- function(datos_sf, col_valor = "U_final",
                               shp_dir = "data/shapefiles/admin") {

  admin <- cargar_admin(shp_dir)

  ggplot() +
    geom_sf(data = admin$limitrofes, fill = "grey90", color = NA) +
    geom_sf(data = datos_sf, aes(fill = .data[[col_valor]]), color = NA) +
    geom_sf(data = admin$provincias, fill = NA, color = "black", linewidth = 0.15) +
    geom_sf(data = admin$comunidades, fill = NA, color = "black", linewidth = 0.25) +
    scale_fill_gradientn(
      colours = PALETA_INCERT_MINI,
      limits = c(0, 1),
      oob = scales::squish,
      na.value = "grey90",
      name = "Incertidumbre (anchura 95% IC)",
      breaks = c(0, 0.25, 0.5, 0.75, 1),
      labels = c("0", "0.25", "0.5", "0.75", "1")
    ) +
    coord_sf(xlim = XLIM_MOMAT, ylim = YLIM_MOMAT, expand = FALSE) +
    theme_void() +
    theme(
      legend.position = "bottom",
      legend.title = element_text(size = 7),
      legend.text = element_text(size = 6),
      legend.key.height = unit(2, "mm"),
      legend.key.width = unit(9, "mm"),
      plot.background = element_rect(fill = "white", colour = NA)
    ) +
    guides(
      fill = guide_colorbar(
        direction = "horizontal",
        barwidth = unit(24, "mm"),
        barheight = unit(2.5, "mm"),
        ticks = TRUE,
        frame.colour = NA,
        label.position = "bottom",
        label.hjust = 0.5
      )
    )
}

# ==============================================================================
# FUNCION: MAPA CON INSET DE INCERTIDUMBRE
# ==============================================================================

crear_mapa_con_inset <- function(datos_sf, col_valor, titulo,
                                 col_incert = "U_final",
                                 paleta = PALETA_FAV_MOMAT,
                                 limits = c(0, 1),
                                 shp_dir = "data/shapefiles/admin") {

  mapa_main <- crear_mapa_momat(
    datos_sf, col_valor, titulo,
    paleta = paleta, limits = limits, shp_dir = shp_dir
  )

  mini_plot <- crear_inset_incert(datos_sf, col_incert, shp_dir = shp_dir)
  mini_grob <- ggplotGrob(mini_plot)

  mapa_main +
    annotation_custom(
      grob = mini_grob,
      xmin = 1.8, xmax = 6.0,
      ymin = 35.3, ymax = 38.6
    )
}

# ==============================================================================
# LEYENDA BIVARIADO (inset 3x3 - estilo MOMAT limpio)
# ==============================================================================

crear_leyenda_bivariado_momat <- function() {
  df_ley <- expand.grid(F_class = 1:3, U_class = 1:3) %>%
    mutate(color = map2_chr(F_class, U_class, ~MATRIZ_BIVARIADO_MOMAT[.x, .y]))

  ggplot(df_ley, aes(x = U_class, y = F_class)) +
    geom_tile(aes(fill = color), color = "white", linewidth = 0.8) +
    scale_fill_identity() +
    scale_x_continuous(breaks = 1:3, labels = c("B", "M", "A"),
                       expand = c(0, 0)) +
    scale_y_continuous(breaks = 1:3, labels = c("B", "M", "A"),
                       expand = c(0, 0)) +
    labs(x = "Incert.", y = "Fav.") +
    theme_void() +
    theme(
      axis.text.x = element_text(size = 6, margin = margin(1, 0, 0, 0)),
      axis.text.y = element_text(size = 6, margin = margin(0, 1, 0, 0)),
      axis.title.x = element_text(size = 7, margin = margin(2, 0, 2, 0)),
      axis.title.y = element_text(size = 7, angle = 90, margin = margin(0, 2, 0, 2)),
      plot.background = element_rect(fill = "white", color = "grey40", linewidth = 0.4),
      plot.margin = margin(3, 3, 3, 3)
    )
}

# ==============================================================================
# FUNCION: MAPA BIVARIADO ESTILO MOMAT
# ==============================================================================

crear_mapa_bivariado_momat <- function(datos_sf,
                                       titulo = "Bivariado F x U",
                                       shp_dir = "data/shapefiles/admin") {

  admin <- cargar_admin(shp_dir)

  p_mapa <- ggplot() +
    geom_sf(data = admin$limitrofes, fill = "grey90", color = NA) +
    geom_sf(data = datos_sf %>% filter(!is.na(bivariado)),
            aes(fill = bivariado), color = NA) +
    geom_sf(data = admin$provincias, fill = NA, color = "black", linewidth = 0.2) +
    geom_sf(data = admin$comunidades, fill = NA, color = "black", linewidth = 0.4) +
    scale_fill_identity() +
    coord_sf(xlim = XLIM_MOMAT, ylim = YLIM_MOMAT, expand = FALSE) +
    labs(title = titulo) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 11, face = "bold", hjust = 0.5),
      panel.grid = element_blank(),
      axis.text = element_blank(),
      axis.title = element_blank(),
      axis.ticks = element_blank(),
      plot.background = element_rect(fill = "white", color = NA),
      panel.background = element_rect(fill = "white", color = NA),
      plot.margin = margin(5, 5, 5, 5)
    )

  leyenda <- crear_leyenda_bivariado_momat()

  p_mapa +
    inset_element(leyenda,
                  left = 0.68, bottom = 0.02,
                  right = 0.99, top = 0.35)
}

# ==============================================================================
# FUNCION: GUARDAR MAPA (TIFF, estilo MOMAT)
# ==============================================================================

guardar_mapa_momat <- function(plot, filename,
                               width = WIDTH_MOMAT, height = HEIGHT_MOMAT,
                               dpi = DPI_MOMAT) {
  ggsave(
    filename = filename, plot = plot,
    width = width, height = height,
    units = "in", dpi = dpi,
    device = "tiff", bg = "white"
  )
  cat(sprintf("    [OK] %s\n", basename(filename)))
}

# ==============================================================================
# FUNCION: MULTIPANEL (F_int arriba, F_amb + U + bivariado abajo)
# ==============================================================================

crear_multipanel_momat <- function(datos_sf, sp_name,
                                   shp_dir = "data/shapefiles/admin") {

  # Tema compacto para paneles inferiores
  theme_bottom <- theme(
    plot.title = element_text(size = 9, face = "bold", hjust = 0.5,
                              margin = margin(2, 0, 2, 0)),
    legend.key.height = unit(0.8, "cm"),
    legend.key.width = unit(0.3, "cm"),
    legend.text = element_text(size = 7),
    plot.margin = margin(2, 2, 2, 2)
  )

  # Panel superior: Favorabilidad integrada (protagonista)
  p_top <- crear_mapa_momat(
    datos_sf, "F_int", "Favorabilidad Integrada",
    paleta = PALETA_FAV_MOMAT, shp_dir = shp_dir
  ) +
    theme(
      plot.title = element_text(size = 13, face = "bold", hjust = 0.5,
                                margin = margin(8, 0, 2, 0)),
      legend.key.height = unit(1.8, "cm"),
      legend.key.width = unit(0.4, "cm"),
      legend.text = element_text(size = 9),
      plot.margin = margin(0, 5, 5, 5)
    )

  # Panel inferior: 3 mapas compactos
  p_amb <- crear_mapa_momat(
    datos_sf, "F_amb", "a) Fav. Ambiental",
    paleta = PALETA_FAV_MOMAT, shp_dir = shp_dir
  ) + theme_bottom

  p_unc <- crear_mapa_momat(
    datos_sf, "U_final", "b) Incertidumbre",
    paleta = PALETA_INCERT_MOMAT, shp_dir = shp_dir
  ) + theme_bottom

  # Bivariado: leyenda mas espaciada
  p_biv <- crear_mapa_bivariado_momat(
    datos_sf, "c) Bivariado F x U", shp_dir = shp_dir
  ) + theme(
    plot.title = element_text(size = 9, face = "bold", hjust = 0.5,
                              margin = margin(2, 0, 2, 0)),
    plot.margin = margin(2, 8, 2, 2)
  )

  # Layout: superior 5 filas, inferior 3 filas
  design <- "AAA\nAAA\nAAA\nAAA\nAAA\nBCD\nBCD\nBCD"

  p_top + p_amb + p_unc + p_biv +
    plot_layout(design = design) +
    plot_annotation(
      title = sp_name,
      theme = theme(
        plot.title = element_text(size = 16, face = "bold.italic", hjust = 0.5,
                                  margin = margin(5, 0, 10, 0)),
        plot.background = element_rect(fill = "white", color = NA),
        plot.margin = margin(5, 5, 5, 5)
      )
    )
}

# ==============================================================================
# FUNCION: PANEL DOBLE (F_int con inset incertidumbre + Bivariado)
# ==============================================================================

crear_panel_doble_momat <- function(datos_sf, sp_name,
                                    col_fav = "F_int",
                                    col_incert = "U_final",
                                    shp_dir = "data/shapefiles/admin") {

  # Izquierda: favorabilidad integrada (sin inset)
  p_fav <- crear_mapa_momat(
    datos_sf, col_fav, "Favorabilidad Integrada",
    paleta = PALETA_FAV_MOMAT, shp_dir = shp_dir
  ) +
    theme(
      plot.title = element_text(size = 12, face = "bold", hjust = 0.5,
                                margin = margin(8, 0, 2, 0)),
      legend.key.height = unit(1.5, "cm"),
      legend.key.width = unit(0.4, "cm"),
      legend.text = element_text(size = 9)
    )

  # Derecha: bivariado
  p_biv <- crear_mapa_bivariado_momat(
    datos_sf, "Bivariado F x U", shp_dir = shp_dir
  ) +
    theme(
      plot.title = element_text(size = 12, face = "bold", hjust = 0.5,
                                margin = margin(8, 0, 2, 0))
    )

  p_fav + p_biv +
    plot_layout(ncol = 2, widths = c(1, 1)) +
    plot_annotation(
      title = sp_name,
      theme = theme(
        plot.title = element_text(size = 16, face = "bold.italic", hjust = 0.5,
                                  margin = margin(5, 0, 10, 0)),
        plot.background = element_rect(fill = "white", color = NA),
        plot.margin = margin(5, 5, 5, 5)
      )
    )
}

message("[OK] Funciones de mapas MOMAT cargadas")
