# ==============================================================================
# utils_mapas.R - Funciones de visualizacion para mapas del atlas
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(sf)
  library(scico)
  library(patchwork)
  library(rnaturalearth)
})

PALETAS <- list(
  favorabilidad = scico(100, palette = "batlow"),
  incertidumbre = scico(100, palette = "lajolla"),
  pa = c("grey90", "#2C7BB6"),
  mess = scico(100, palette = "vik")
)

get_limites_iberia <- function(crs = 25830) {
  spain <- ne_countries(country = "spain", scale = 50, returnclass = "sf")
  portugal <- ne_countries(country = "portugal", scale = 50, returnclass = "sf")
  bind_rows(spain, portugal) %>% st_transform(crs)
}

mapa_favorabilidad <- function(datos_malla, valores, titulo = "Favorabilidad") {
  datos_malla$valor <- valores
  limites <- tryCatch(get_limites_iberia(st_crs(datos_malla)$epsg), error = function(e) NULL)

  p <- ggplot() +
    geom_sf(data = datos_malla, aes(fill = valor), color = NA) +
    scale_fill_gradientn(colors = PALETAS$favorabilidad, limits = c(0, 1),
                         breaks = seq(0, 1, 0.2), name = "Favorabilidad", na.value = "grey95") +
    labs(title = titulo) + theme_void() +
    theme(plot.title = element_text(hjust = 0.5, face = "bold", size = 14),
          legend.position = "bottom", legend.key.width = unit(2, "cm"))

  if (!is.null(limites)) p <- p + geom_sf(data = limites, fill = NA, color = "grey30", linewidth = 0.3)
  p
}

mapa_incertidumbre <- function(datos_malla, valores, titulo = "Incertidumbre") {
  datos_malla$valor <- valores
  limites <- tryCatch(get_limites_iberia(st_crs(datos_malla)$epsg), error = function(e) NULL)

  p <- ggplot() +
    geom_sf(data = datos_malla, aes(fill = valor), color = NA) +
    scale_fill_gradientn(colors = PALETAS$incertidumbre, limits = c(0, 1),
                         name = "Incertidumbre", na.value = "grey95") +
    labs(title = titulo) + theme_void() +
    theme(plot.title = element_text(hjust = 0.5, face = "bold", size = 14),
          legend.position = "bottom", legend.key.width = unit(2, "cm"))

  if (!is.null(limites)) p <- p + geom_sf(data = limites, fill = NA, color = "grey30", linewidth = 0.3)
  p
}

mapa_pa <- function(datos_malla, pa, titulo = "Presencia observada") {
  datos_malla$PA <- factor(pa, levels = c(0, 1), labels = c("Ausencia", "Presencia"))
  limites <- tryCatch(get_limites_iberia(st_crs(datos_malla)$epsg), error = function(e) NULL)

  p <- ggplot() +
    geom_sf(data = datos_malla, aes(fill = PA), color = NA) +
    scale_fill_manual(values = PALETAS$pa, name = "", na.value = "white") +
    labs(title = titulo) + theme_void() +
    theme(plot.title = element_text(hjust = 0.5, face = "bold", size = 14), legend.position = "bottom")

  if (!is.null(limites)) p <- p + geom_sf(data = limites, fill = NA, color = "grey30", linewidth = 0.3)
  p
}

mapa_bivariado <- function(datos_malla, favorabilidad, incertidumbre,
                           titulo = "Favorabilidad e Incertidumbre") {
  datos_malla$F_cat <- cut(favorabilidad, breaks = c(0, 0.33, 0.67, 1.0),
                           labels = c("Bajo", "Medio", "Alto"), include.lowest = TRUE)
  datos_malla$U_cat <- cut(incertidumbre, breaks = c(0, 0.33, 0.67, 1.0),
                           labels = c("Baja", "Media", "Alta"), include.lowest = TRUE)
  datos_malla$bivar <- interaction(datos_malla$F_cat, datos_malla$U_cat, sep = "-")

  colores_bivar <- c("Bajo-Baja" = "#E8E8E8", "Bajo-Media" = "#DFBDBE", "Bajo-Alta" = "#D4919C",
                     "Medio-Baja" = "#9DC3C1", "Medio-Media" = "#909AB7", "Medio-Alta" = "#8370AB",
                     "Alto-Baja" = "#5AC8C8", "Alto-Media" = "#5698B9", "Alto-Alta" = "#4872B3")

  limites <- tryCatch(get_limites_iberia(st_crs(datos_malla)$epsg), error = function(e) NULL)

  p <- ggplot() +
    geom_sf(data = datos_malla, aes(fill = bivar), color = NA) +
    scale_fill_manual(values = colores_bivar, name = "F-U", na.value = "grey95") +
    labs(title = titulo) + theme_void() +
    theme(plot.title = element_text(hjust = 0.5, face = "bold", size = 14), legend.position = "right")

  if (!is.null(limites)) p <- p + geom_sf(data = limites, fill = NA, color = "grey30", linewidth = 0.3)
  p
}

guardar_mapa <- function(plot, filename, width = 20, height = 20, dpi = 300) {
  ggsave(filename = filename, plot = plot, width = width, height = height,
         units = "cm", dpi = dpi, bg = "white")
  message(sprintf("[OK] Guardado: %s", basename(filename)))
}

message("[OK] Funciones de mapas cargadas")
