# ==============================================================================
# 04f_maquetacion_editorial.R - 6 opciones de maquetacion para comision editorial
# ==============================================================================
#
# Genera 6 layouts alternativos para una misma especie (Rhinolophus ferrumequinum
# por defecto) como plantillas para la revision editorial del atlas.
#
# OPCIONES:
#   A: F_final grande + U_final inset pequeño (2 mapas)
#   B: F_final grande + bivariado + presencias (3 mapas, recomendada en briefing)
#   C: F_final grande + panel 2x2 con F_amb/F_esp/bivariado/presencias (5 mapas)
#   D: F_final y bivariado lado a lado (2 mapas iguales)
#   E: Estilo MOMAT puro (multipanel: F_final arriba, F_amb/U/bivariado abajo)
#   F: Recomendacion editorial (F_final ancho completo + tira de 3 minis +
#      caja de metricas) - maximo impacto informativo por pagina
#   G: Como B pero con U_final como inset dentro de F_final (estilo MOMAT)
#   H: Como E pero con U_final como inset dentro de F_final; en el slot de
#      U_final va el mapa de presencias
#
# MAPA DE PRESENCIAS:
#   Categorizacion tripartita simple:
#     - No muestreado (gris muy claro): cuadriculas sin muestreo con ningun metodo
#     - Ausencia (gris medio): muestreadas pero sin deteccion de la especie
#     - Presencia (azul oscuro): muestreadas con deteccion >=1 metodo
#
# OUTPUTS:
#   output_maquetacion/opcion_{A-H}.png   - 25x18 cm a 300 dpi
#   output_maquetacion/comparativa_opciones.pdf - las 8 en paginas consecutivas
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

if (!exists("CONFIG")) source("R/00_setup/00_config.R")
source("R/utils/utils_mapas_momat.R")

suppressPackageStartupMessages({
  library(tidyverse)
  library(sf)
  library(patchwork)
  library(grid)
})

# --- Parametros ---
SP <- "Rhinolophus ferrumequinum"
DIR_OUT <- "output_maquetacion"
WIDTH_CM <- 25
HEIGHT_CM <- 18
DPI <- 300

dir.create(DIR_OUT, recursive = TRUE, showWarnings = FALSE)

cat("\n========================================\n")
cat("  MAQUETACION EDITORIAL - 6 OPCIONES\n")
cat("  Especie ejemplo:", SP, "\n")
cat("========================================\n\n")

# ==============================================================================
# 1. CARGAR DATOS
# ==============================================================================

# Malla con geometrias
malla <- readRDS(CONFIG$paths$malla_union)
if (is.na(st_crs(malla))) st_crs(malla) <- 25830

# Reproyectar al CRS admin
provincias_tmp <- st_read("data/shapefiles/admin/Provincias.shp", quiet = TRUE)
crs_admin <- st_crs(provincias_tmp)
rm(provincias_tmp)
malla_ll <- st_transform(malla, crs_admin)

# PAxENV wide (para CUADRICULAS + muestreado)
datos_pa <- readRDS(CONFIG$paths$pa_data)
cuadriculas <- datos_pa$CUADRICULA

# Columna sp (con espacio)
sp_col <- paste0("sp_", SP)
stopifnot(sp_col %in% names(datos_pa))

# PA largo por metodo (para mapa presencias coloreado por metodo)
pa_metodo <- readRDS(CONFIG$paths$pa_metodo)

# --- Predicciones de la especie ---
sp_file <- str_replace_all(SP, " ", "_")
dir_sp <- file.path(CONFIG$output$base, sp_file)

pred_amb <- read_csv(file.path(dir_sp, "ambiental/predicciones.csv"),
                    show_col_types = FALSE)
pred_esp <- read_csv(file.path(dir_sp, "espacial/predicciones.csv"),
                    show_col_types = FALSE)
pred_int <- read_csv(file.path(dir_sp, "interseccion/predicciones.csv"),
                    show_col_types = FALSE)
pred_unc <- read_csv(file.path(dir_sp, "incertidumbre/incertidumbre.csv"),
                    show_col_types = FALSE)

# Asignar CUADRICULA posicionalmente (mismo orden que PAxENV)
stopifnot(nrow(pred_amb) == length(cuadriculas),
          nrow(pred_esp) == length(cuadriculas),
          nrow(pred_int) == length(cuadriculas),
          nrow(pred_unc) == length(cuadriculas))

pred_amb$CUADRICULA <- cuadriculas
pred_esp$CUADRICULA <- cuadriculas
pred_int$CUADRICULA <- cuadriculas
pred_unc$CUADRICULA <- cuadriculas

# --- Unir con malla ---
datos_mapa <- malla_ll %>%
  select(CUADRICULA, geometry) %>%
  left_join(pred_amb %>% select(CUADRICULA, F_amb = F_glm_mean), by = "CUADRICULA") %>%
  left_join(pred_esp %>% select(CUADRICULA, F_esp = F_esp_mean), by = "CUADRICULA") %>%
  left_join(pred_int %>% select(CUADRICULA, F_int = F_final_mean), by = "CUADRICULA") %>%
  left_join(pred_unc %>% select(CUADRICULA, U_final, MESS), by = "CUADRICULA")

# --- Terciles bivariado ---
datos_mapa <- datos_mapa %>%
  mutate(
    F_class = clasificar_terciles_momat(F_int),
    U_class = clasificar_terciles_momat(U_final),
    bivariado = map2_chr(F_class, U_class, ~{
      if (is.na(.x) || is.na(.y)) NA_character_
      else MATRIZ_BIVARIADO_MOMAT[.x, .y]
    })
  )

# --- Clasificacion tripartita para mapa de presencias simple ---
# No muestreado: muestreado == 0
# Ausencia:      muestreado == 1 y sp_<especie> == 0
# Presencia:     muestreado == 1 y sp_<especie> == 1
pa_status <- tibble(
  CUADRICULA = datos_pa$CUADRICULA,
  muestreado = datos_pa$muestreado,
  sp_val     = datos_pa[[sp_col]]
) %>%
  mutate(
    status = case_when(
      muestreado == 0 ~ "No muestreado",
      sp_val == 1     ~ "Presencia",
      TRUE            ~ "Ausencia"
    ),
    status = factor(status, levels = c("No muestreado", "Ausencia", "Presencia"))
  )

datos_mapa <- datos_mapa %>%
  left_join(pa_status %>% select(CUADRICULA, status), by = "CUADRICULA")

cat(sprintf("  Distribucion de status (%s):\n", SP))
print(table(datos_mapa$status, useNA = "ifany"))

# Conteos por metodo (solo para caja de metricas de F)
pa_sp <- pa_metodo %>% filter(especie_modelo == SP)
n_por_metodo <- pa_sp %>%
  count(cuadricula_utm_10x10, metodo, name = "n") %>%
  group_by(cuadricula_utm_10x10) %>%
  slice_max(n, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  pull(metodo) %>% table()
n_pres_total <- sum(datos_mapa$status == "Presencia", na.rm = TRUE)

# --- Metricas para el box de opcion F ---
metr_ho <- read_csv(file.path(dir_sp, "ambiental/metricas_holdout.csv"),
                    show_col_types = FALSE)
metr_cv <- read_csv(file.path(dir_sp, "validacion/resumen_cv.csv"),
                    show_col_types = FALSE)

# ==============================================================================
# 2. FUNCIONES AUXILIARES
# ==============================================================================

COLORES_STATUS <- c(
  "No muestreado" = "#F2F2F2",  # gris muy claro
  "Ausencia"      = "#BDBDBD",  # gris medio
  "Presencia"     = "#2D1B4E"   # deep aubergine / indigo oscuro.
                                # Hue distinto de F_final (calidos), U_final
                                # (azules) y bivariado (azules/verdes);
                                # saturacion moderada, tono editorial clasico.
)

# Mapa presencias: tres categorias (no muestreado / ausencia / presencia)
# Celdas UTM coloreadas (no puntos). Elegante y conciso.
crear_mapa_presencias_simple <- function(datos_sf, titulo,
                                         shp_dir = "data/shapefiles/admin",
                                         tam_leyenda = 3) {
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
      legend.key.size = unit(tam_leyenda, "mm"),
      legend.margin = margin(0, 0, 0, 0),
      plot.margin = margin(5, 5, 5, 5)
    ) +
    guides(fill = guide_legend(nrow = 1, byrow = TRUE,
                               override.aes = list(color = "grey70", linewidth = 0.1)))
}

# Titulo de opcion en cabecera
anotacion_opcion <- function(letra, descripcion) {
  plot_annotation(
    title = sprintf("Opcion %s - %s", letra, descripcion),
    subtitle = sprintf("Ejemplo: %s", SP),
    theme = theme(
      plot.title = element_text(size = 14, face = "bold", hjust = 0),
      plot.subtitle = element_text(size = 10, face = "italic", hjust = 0,
                                   margin = margin(0, 0, 8, 0)),
      plot.background = element_rect(fill = "white", color = NA),
      plot.margin = margin(8, 8, 5, 8)
    )
  )
}

# Tema compacto para paneles pequenos
theme_compacto <- theme(
  plot.title = element_text(size = 9, face = "bold", hjust = 0.5,
                            margin = margin(2, 0, 2, 0)),
  legend.key.height = unit(5, "mm"),
  legend.key.width = unit(2.5, "mm"),
  legend.text = element_text(size = 6),
  legend.title = element_text(size = 7),
  plot.margin = margin(2, 2, 2, 2)
)

# ==============================================================================
# 3. OPCION A - F_final grande + U_final inset pequeno
# ==============================================================================

cat("\n>>> Opcion A: F_final grande + U_final inset\n")

p_A_main <- crear_mapa_momat(datos_mapa, "F_int",
                             "Favorabilidad final",
                             paleta = PALETA_FAV_MOMAT) +
  theme(
    plot.title = element_text(size = 13, face = "bold", hjust = 0.5),
    legend.key.height = unit(1.4, "cm"),
    legend.key.width = unit(0.35, "cm"),
    legend.text = element_text(size = 8)
  )

p_A_inset <- crear_mapa_momat(datos_mapa, "U_final",
                              "Incertidumbre",
                              paleta = PALETA_INCERT_MOMAT) +
  theme_compacto

opcion_A <- (p_A_main + p_A_inset) +
  plot_layout(widths = c(2, 1)) +
  anotacion_opcion("A", "F_final grande + U_final inset")

ggsave(file.path(DIR_OUT, "opcion_A.png"), opcion_A,
       width = WIDTH_CM, height = HEIGHT_CM, units = "cm", dpi = DPI, bg = "white")
cat("  [OK] opcion_A.png\n")

# ==============================================================================
# 4. OPCION B - F_final + bivariado + presencias  [RECOMENDADA]
# ==============================================================================

cat("\n>>> Opcion B: F_final + bivariado + presencias\n")

p_B_main <- crear_mapa_momat(datos_mapa, "F_int",
                             "Favorabilidad final") +
  theme(
    plot.title = element_text(size = 13, face = "bold", hjust = 0.5),
    legend.key.height = unit(1.4, "cm"),
    legend.key.width = unit(0.35, "cm"),
    legend.text = element_text(size = 8)
  )

p_B_biv <- crear_mapa_bivariado_momat(datos_mapa, "Bivariado F x U") +
  theme_compacto

p_B_pres <- crear_mapa_presencias_simple(datos_mapa,
                                         "Presencia / Ausencia") + theme_compacto

# Layout 2/3 izq, 1/3 der dividido en 2 filas
opcion_B <- p_B_main + (p_B_biv / p_B_pres) +
  plot_layout(widths = c(2, 1)) +
  anotacion_opcion("B", "F_final + bivariado + presencias (RECOMENDADA)")

ggsave(file.path(DIR_OUT, "opcion_B.png"), opcion_B,
       width = WIDTH_CM, height = HEIGHT_CM, units = "cm", dpi = DPI, bg = "white")
cat("  [OK] opcion_B.png\n")

# ==============================================================================
# 5. OPCION C - F_final + panel 2x2 (F_amb, F_esp, bivariado, presencias)
# ==============================================================================

cat("\n>>> Opcion C: F_final + panel 2x2\n")

p_C_main <- crear_mapa_momat(datos_mapa, "F_int",
                             "Favorabilidad final") +
  theme(
    plot.title = element_text(size = 12, face = "bold", hjust = 0.5),
    legend.key.height = unit(1.2, "cm"),
    legend.key.width = unit(0.35, "cm"),
    legend.text = element_text(size = 7)
  )

p_C_amb <- crear_mapa_momat(datos_mapa, "F_amb", "a) F_amb") + theme_compacto
p_C_esp <- crear_mapa_momat(datos_mapa, "F_esp", "b) F_esp") + theme_compacto
p_C_biv <- crear_mapa_bivariado_momat(datos_mapa, "c) Bivariado") + theme_compacto
p_C_pres <- crear_mapa_presencias_simple(datos_mapa,
                                         "d) Presencia / Ausencia") + theme_compacto

panel_C_der <- (p_C_amb + p_C_esp) / (p_C_biv + p_C_pres)

opcion_C <- p_C_main + panel_C_der +
  plot_layout(widths = c(1.3, 1)) +
  anotacion_opcion("C", "F_final + F_amb + F_esp + bivariado + presencias")

ggsave(file.path(DIR_OUT, "opcion_C.png"), opcion_C,
       width = WIDTH_CM, height = HEIGHT_CM, units = "cm", dpi = DPI, bg = "white")
cat("  [OK] opcion_C.png\n")

# ==============================================================================
# 6. OPCION D - F_final y bivariado lado a lado
# ==============================================================================

cat("\n>>> Opcion D: F_final y bivariado equitativos\n")

p_D_fav <- crear_mapa_momat(datos_mapa, "F_int", "Favorabilidad final") +
  theme(
    plot.title = element_text(size = 12, face = "bold", hjust = 0.5),
    legend.key.height = unit(1.5, "cm"),
    legend.key.width = unit(0.4, "cm"),
    legend.text = element_text(size = 8)
  )

p_D_biv <- crear_mapa_bivariado_momat(datos_mapa, "Bivariado F x U") +
  theme(plot.title = element_text(size = 12, face = "bold", hjust = 0.5))

opcion_D <- p_D_fav + p_D_biv +
  plot_layout(ncol = 2, widths = c(1, 1)) +
  anotacion_opcion("D", "F_final y bivariado lado a lado (mismo peso)")

ggsave(file.path(DIR_OUT, "opcion_D.png"), opcion_D,
       width = WIDTH_CM, height = HEIGHT_CM, units = "cm", dpi = DPI, bg = "white")
cat("  [OK] opcion_D.png\n")

# ==============================================================================
# 7. OPCION E - Estilo MOMAT puro (paleta + multipanel 04a)
# ==============================================================================

cat("\n>>> Opcion E: Estilo MOMAT puro (multipanel)\n")

opcion_E <- crear_multipanel_momat(datos_mapa, SP) +
  plot_annotation(
    title = "Opcion E - Estilo MOMAT (paleta y layout 04a_mapas_momat)",
    subtitle = sprintf("Ejemplo: %s", SP),
    theme = theme(
      plot.title = element_text(size = 14, face = "bold", hjust = 0),
      plot.subtitle = element_text(size = 10, face = "italic", hjust = 0,
                                   margin = margin(0, 0, 8, 0)),
      plot.background = element_rect(fill = "white", color = NA),
      plot.margin = margin(8, 8, 5, 8)
    )
  )

ggsave(file.path(DIR_OUT, "opcion_E.png"), opcion_E,
       width = WIDTH_CM, height = HEIGHT_CM, units = "cm", dpi = DPI, bg = "white")
cat("  [OK] opcion_E.png\n")

# ==============================================================================
# 8. OPCION F - Recomendacion editorial (F_final ancho + tira inferior + metricas)
# ==============================================================================
#
# Diseno: F_final ocupando la parte superior (2/3 de la altura) con inset
# bivariado pequeño sobre el mar. Tira inferior (1/3) con tres minis: bivariado,
# presencias, U_final, con caja de metricas a la derecha.

cat("\n>>> Opcion F: Recomendacion editorial (dashboard)\n")

# Cabecera: F_final grande con paleta MOMAT + n presencias anotado
p_F_main <- crear_mapa_momat(datos_mapa, "F_int",
                             sprintf("Favorabilidad final de %s", SP)) +
  annotate("label", x = -9.5, y = 44.2,
           label = sprintf("N presencias UTM 10x10 = %d", n_pres_total),
           hjust = 0, vjust = 1, size = 2.8, fill = "white",
           alpha = 0.9) +
  theme(
    plot.title = element_text(size = 13, face = "bold", hjust = 0.5),
    legend.key.height = unit(1.2, "cm"),
    legend.key.width = unit(0.35, "cm"),
    legend.text = element_text(size = 8)
  )

p_F_biv <- crear_mapa_bivariado_momat(datos_mapa, "Bivariado F x U") + theme_compacto
p_F_pres <- crear_mapa_presencias_simple(datos_mapa,
                                         "Presencia / Ausencia") + theme_compacto
p_F_unc <- crear_mapa_momat(datos_mapa, "U_final", "Incertidumbre",
                            paleta = PALETA_INCERT_MOMAT) + theme_compacto

# Caja de metricas (texto) como grob - compacta, 2 columnas
n_acu <- ifelse("acustica" %in% names(n_por_metodo), n_por_metodo[["acustica"]], 0)
n_cap <- ifelse("captura"  %in% names(n_por_metodo), n_por_metodo[["captura"]],  0)
n_cue <- ifelse("cuevas"   %in% names(n_por_metodo), n_por_metodo[["cuevas"]],   0)
n_otr <- ifelse("otros"    %in% names(n_por_metodo), n_por_metodo[["otros"]],    0)

metr_txt <- sprintf(paste0(
  "METRICAS DEL MODELO          PRESENCIAS POR METODO\n",
  "--------------------         ---------------------\n",
  "AUC hold-out : %.2f          Acustica : %d\n",
  "TSS hold-out : %.2f          Captura  : %d\n",
  "AUC CV       : %.2f (%.2f)   Cuevas   : %d\n",
  "TSS CV       : %.2f (%.2f)   Otros    : %d"),
  metr_ho$AUC, n_acu,
  metr_ho$TSS, n_cap,
  metr_cv$AUC_mean, metr_cv$AUC_sd, n_cue,
  metr_cv$TSS_mean, metr_cv$TSS_sd, n_otr
)

p_F_metr <- ggplot() +
  annotate("text", x = 0.02, y = 0.5, label = metr_txt,
           hjust = 0, vjust = 0.5, size = 2.8, family = "mono") +
  xlim(0, 1) + ylim(0, 1) +
  theme_void() +
  theme(
    plot.background = element_rect(fill = "grey98", color = "grey70", linewidth = 0.3),
    plot.margin = margin(4, 6, 4, 6)
  )

# Layout: arriba F_main (3 filas); abajo banda con 3 mapas (B,C,D) y la caja de metricas (E)
# ocupando dos columnas para que entre el texto completo
design_F <- "AAAAAA\nAAAAAA\nAAAAAA\nBCDEEE"

opcion_F <- p_F_main + p_F_biv + p_F_pres + p_F_unc + p_F_metr +
  plot_layout(design = design_F, heights = c(1, 1, 1, 1.05)) +
  anotacion_opcion("F", "Recomendacion editorial - F_final dominante + diagnosticos + metricas")

ggsave(file.path(DIR_OUT, "opcion_F.png"), opcion_F,
       width = WIDTH_CM, height = HEIGHT_CM, units = "cm", dpi = DPI, bg = "white")
cat("  [OK] opcion_F.png\n")

# ==============================================================================
# 9. OPCION G - Como B pero con U_final como inset dentro de F_final
# ==============================================================================

cat("\n>>> Opcion G: F_final+inset_U + bivariado + presencias\n")

p_G_main <- crear_mapa_con_inset(datos_mapa, "F_int",
                                 "Favorabilidad final (inset: incertidumbre)",
                                 col_incert = "U_final") +
  theme(plot.title = element_text(size = 13, face = "bold", hjust = 0.5))

p_G_biv <- crear_mapa_bivariado_momat(datos_mapa, "Bivariado F x U") +
  theme_compacto
p_G_pres <- crear_mapa_presencias_simple(datos_mapa,
                                         "Presencia / Ausencia") + theme_compacto

opcion_G <- p_G_main + (p_G_biv / p_G_pres) +
  plot_layout(widths = c(2, 1)) +
  anotacion_opcion("G", "F_final con U inset + bivariado + presencias (estilo MOMAT)")

ggsave(file.path(DIR_OUT, "opcion_G.png"), opcion_G,
       width = WIDTH_CM, height = HEIGHT_CM, units = "cm", dpi = DPI, bg = "white")
cat("  [OK] opcion_G.png\n")

# ==============================================================================
# 10. OPCION H - Como E pero con U_final como inset; el slot de U lo ocupa
#                el mapa de presencias simple
# ==============================================================================

cat("\n>>> Opcion H: Multipanel MOMAT con U inset + presencias en slot de U\n")

# Panel superior: F_final con inset de U (sustituye al F_final solo de E)
p_H_top <- crear_mapa_con_inset(datos_mapa, "F_int",
                                "Favorabilidad Integrada (inset: incertidumbre)",
                                col_incert = "U_final") +
  theme(
    plot.title = element_text(size = 13, face = "bold", hjust = 0.5,
                              margin = margin(8, 0, 2, 0)),
    legend.key.height = unit(1.8, "cm"),
    legend.key.width = unit(0.4, "cm"),
    legend.text = element_text(size = 9),
    plot.margin = margin(0, 5, 5, 5)
  )

# Paneles inferiores
theme_bottom_H <- theme(
  plot.title = element_text(size = 9, face = "bold", hjust = 0.5,
                            margin = margin(2, 0, 2, 0)),
  legend.key.height = unit(0.8, "cm"),
  legend.key.width = unit(0.3, "cm"),
  legend.text = element_text(size = 7),
  plot.margin = margin(2, 2, 2, 2)
)

p_H_amb <- crear_mapa_momat(datos_mapa, "F_amb", "a) Fav. Ambiental",
                            paleta = PALETA_FAV_MOMAT) + theme_bottom_H
p_H_pres <- crear_mapa_presencias_simple(datos_mapa,
                                         "b) Presencia / Ausencia") + theme_bottom_H
p_H_biv <- crear_mapa_bivariado_momat(datos_mapa, "c) Bivariado F x U") +
  theme(
    plot.title = element_text(size = 9, face = "bold", hjust = 0.5,
                              margin = margin(2, 0, 2, 0)),
    plot.margin = margin(2, 8, 2, 2)
  )

design_H <- "AAA\nAAA\nAAA\nAAA\nAAA\nBCD\nBCD\nBCD"

opcion_H <- p_H_top + p_H_amb + p_H_pres + p_H_biv +
  plot_layout(design = design_H) +
  plot_annotation(
    title = sprintf("Opcion H - Estilo MOMAT con U inset + presencias (%s)",
                    "fav. integrada arriba; F_amb, presencias y bivariado abajo"),
    subtitle = sprintf("Ejemplo: %s", SP),
    theme = theme(
      plot.title = element_text(size = 13, face = "bold", hjust = 0),
      plot.subtitle = element_text(size = 10, face = "italic", hjust = 0,
                                   margin = margin(0, 0, 8, 0)),
      plot.background = element_rect(fill = "white", color = NA),
      plot.margin = margin(8, 8, 5, 8)
    )
  )

ggsave(file.path(DIR_OUT, "opcion_H.png"), opcion_H,
       width = WIDTH_CM, height = HEIGHT_CM, units = "cm", dpi = DPI, bg = "white")
cat("  [OK] opcion_H.png\n")

# ==============================================================================
# 11. PDF COMPARATIVO (8 paginas)
# ==============================================================================

cat("\n>>> PDF comparativo (8 paginas)\n")

pdf_path <- file.path(DIR_OUT, "comparativa_opciones.pdf")
pdf(pdf_path,
    width = WIDTH_CM / 2.54, height = HEIGHT_CM / 2.54, onefile = TRUE)
print(opcion_A)
print(opcion_B)
print(opcion_C)
print(opcion_D)
print(opcion_E)
print(opcion_F)
print(opcion_G)
print(opcion_H)
dev.off()

cat(sprintf("  [OK] %s\n", pdf_path))
cat("\n[OK] Maquetacion completada\n")
