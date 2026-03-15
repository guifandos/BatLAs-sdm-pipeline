# ==============================================================================
# utils_mapas.R - Funciones de visualizacion para mapas del atlas
# ==============================================================================
# Basado en 06_mapas_atlas.R (pipeline v1, Nov 2025)
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(sf)
  library(scico)
  library(patchwork)
  library(rnaturalearth)
})

# ==============================================================================
# PALETAS Y COLORES
# ==============================================================================

PALETA_FAV <- scico(100, palette = "batlow")
PALETA_INCERT <- rev(scico(100, palette = "lajolla"))
PALETA_MESS <- scico(100, palette = "vik")
COLORES_PA <- c("0" = "grey90", "1" = "#2C7BB6")

# Matriz bivariado: filas = Favorabilidad (1=Baja,2=Media,3=Alta),
#                   cols  = Incertidumbre (1=Baja,2=Media,3=Alta)
MATRIZ_BIVARIADO <- matrix(c(
  "#3182bd", "#9ecae1", "#deebf7",   # F baja:  azules
  "#feb24c", "#fed976", "#ffffcc",   # F media: amarillos
  "#006d2c", "#31a354", "#74c476"    # F alta:  verdes
), nrow = 3, byrow = TRUE)

# Extension geografica: solo peninsula + Baleares (sin Canarias)
XLIM <- c(-10, 5)
YLIM <- c(35, 44.5)

# Dimensiones
DPI <- 300
WIDTH_PANEL <- 12
HEIGHT_PANEL <- 10
WIDTH_INDIVIDUAL <- 8
HEIGHT_INDIVIDUAL <- 6

# ==============================================================================
# PAISES LIMITROFES (cache)
# ==============================================================================

.paises_cache <- new.env(parent = emptyenv())

get_paises <- function() {
  if (is.null(.paises_cache$data)) {
    .paises_cache$data <- ne_countries(scale = "medium", returnclass = "sf") %>%
      filter(admin %in% c("Spain", "Portugal", "France", "Morocco", "Algeria", "Andorra")) %>%
      st_transform(4326)
  }
  .paises_cache$data
}

# ==============================================================================
# FUNCIONES AUXILIARES
# ==============================================================================

clasificar_terciles <- function(x) {
  breaks <- quantile(x, probs = c(0, 1/3, 2/3, 1), na.rm = TRUE)
  cut(x, breaks = breaks, labels = FALSE, include.lowest = TRUE)
}

# ==============================================================================
# FUNCION: CREAR MAPA BASE
# ==============================================================================

crear_mapa <- function(datos_sf, col_valor, titulo,
                       paleta = PALETA_FAV, limits = c(0, 1),
                       legend_title = "Valor", discreto = FALSE,
                       na_color = "grey90") {

  paises <- get_paises()

  p <- ggplot() +
    geom_sf(data = paises, fill = "grey95", color = "grey70", linewidth = 0.3) +
    geom_sf(data = datos_sf, aes(fill = .data[[col_valor]]), color = NA)

  if (discreto) {
    p <- p + scale_fill_manual(values = paleta, na.value = na_color, name = legend_title)
  } else {
    p <- p + scale_fill_gradientn(
      colours = paleta, limits = limits,
      na.value = na_color, name = legend_title,
      oob = scales::squish
    )
  }

  p + coord_sf(xlim = XLIM, ylim = YLIM, expand = FALSE) +
    labs(title = titulo) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 11, face = "bold", hjust = 0.5),
      legend.position = "right",
      legend.key.height = unit(1.5, "cm"),
      legend.key.width = unit(0.5, "cm"),
      panel.grid = element_line(color = "grey90", linewidth = 0.2),
      axis.text = element_text(size = 8),
      axis.title = element_blank(),
      plot.background = element_rect(fill = "white", color = NA),
      panel.background = element_rect(fill = "white", color = NA),
      plot.margin = margin(5, 5, 5, 5)
    )
}

# ==============================================================================
# LEYENDA BIVARIADO (inset 3x3)
# ==============================================================================

crear_leyenda_bivariado <- function() {
  df_ley <- expand.grid(F_class = 1:3, U_class = 1:3) %>%
    mutate(color = map2_chr(F_class, U_class, ~MATRIZ_BIVARIADO[.x, .y]))

  ggplot(df_ley, aes(x = U_class, y = F_class)) +
    geom_tile(aes(fill = color), color = "white", linewidth = 0.5) +
    scale_fill_identity() +
    scale_x_continuous(breaks = 1:3, labels = c("Baja", "Media", "Alta"), expand = c(0, 0)) +
    scale_y_continuous(breaks = 1:3, labels = c("Baja", "Media", "Alta"), expand = c(0, 0)) +
    labs(x = "Incertidumbre", y = "Favorabilidad") +
    theme_minimal() +
    theme(
      axis.text = element_text(size = 7),
      axis.title = element_text(size = 8),
      panel.grid = element_blank(),
      plot.background = element_rect(fill = "white", color = "grey50", linewidth = 0.5)
    )
}

# ==============================================================================
# FUNCION: MAPA BIVARIADO CON INSET
# ==============================================================================

crear_mapa_bivariado <- function(datos_sf, titulo = "D) Bivariado F x U") {
  paises <- get_paises()

  p_mapa <- ggplot() +
    geom_sf(data = paises, fill = "grey95", color = "grey70", linewidth = 0.3) +
    geom_sf(data = datos_sf %>% filter(!is.na(bivariado)),
            aes(fill = bivariado), color = NA) +
    scale_fill_identity() +
    coord_sf(xlim = XLIM, ylim = YLIM, expand = FALSE) +
    labs(title = titulo) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 11, face = "bold", hjust = 0.5),
      panel.grid = element_line(color = "grey90", linewidth = 0.2),
      axis.text = element_text(size = 8),
      axis.title = element_blank(),
      plot.background = element_rect(fill = "white", color = NA),
      panel.background = element_rect(fill = "white", color = NA),
      plot.margin = margin(5, 5, 5, 5)
    )

  leyenda <- crear_leyenda_bivariado()

  p_mapa +
    inset_element(leyenda,
                  left = 0.68, bottom = 0.02,
                  right = 0.99, top = 0.35)
}

guardar_mapa <- function(plot, filename, width, height, dpi = DPI) {
  ggsave(filename = filename, plot = plot, width = width, height = height,
         units = "in", dpi = dpi, bg = "white")
  cat(sprintf("    [OK] %s\n", basename(filename)))
}

message("[OK] Funciones de mapas cargadas")
