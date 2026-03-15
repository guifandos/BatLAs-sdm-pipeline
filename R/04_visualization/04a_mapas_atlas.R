# ==============================================================================
# 04a_mapas_atlas.R - Generacion de mapas estilo SECEMU
# ==============================================================================
#
# Basado en atlas_murcielagos_pipeline_26112025/scripts/06_mapas_atlas.R
#
# OUTPUTS por especie:
#   1. Panel SECEMU (2x2): Ambiental + Final + Incertidumbre + PA
#   2. Panel Incertidumbre (2x2): MESS + W_bootstrap + U_final + Bivariado
#   3. Mapas individuales: F_amb, F_final, U_final, bivariado
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

if (!exists("CONFIG")) source("R/00_setup/00_config.R")
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

# ==============================================================================
# CARGAR DATOS BASE
# ==============================================================================

# Malla UTM con geometrias
if (file.exists(CONFIG$paths$malla_union)) {
  malla <- readRDS(CONFIG$paths$malla_union)
} else {
  grid_data <- readRDS(CONFIG$paths$grid_predictores)
  if (!is.null(grid_data$malla_union)) {
    malla <- grid_data$malla_union
  } else {
    stop("No se encontro malla_union")
  }
}

if (is.na(st_crs(malla))) st_crs(malla) <- 25830
malla_wgs84 <- st_transform(malla, 4326)
cat(sprintf("  Malla: %d cuadriculas (WGS84)\n", nrow(malla_wgs84)))

# Datos PA
datos_pa <- readRDS(CONFIG$paths$pa_data)
cuadriculas <- datos_pa$CUADRICULA
cat(sprintf("  PA: %d cuadriculas\n", nrow(datos_pa)))

# ==============================================================================
# ESPECIES
# ==============================================================================

especies_gremios <- read_csv(CONFIG$paths$especies_gremios, show_col_types = FALSE) %>%
  filter(modelar == TRUE)

if (!is.null(CONFIG$especies$piloto)) {
  especies <- CONFIG$especies$piloto
} else {
  especies <- especies_gremios$especie
}
especies <- setdiff(especies, CONFIG$especies$excluir)

# ==============================================================================
# PROCESAR CADA ESPECIE
# ==============================================================================

for (sp in especies) {
  cat(sprintf("\n--- %s ---\n", sp))

  if (!CONFIG$control$force_rerun &&
      checkpoint_exists(sp, CONFIG$output$base, "mapas")) {
    cat("  Ya completado\n")
    next
  }

  sp_file <- str_replace_all(sp, " ", "_")
  dir_sp <- file.path(CONFIG$output$base, sp_file)
  dir_out <- file.path(dir_sp, "mapas")
  dir.create(dir_out, recursive = TRUE, showWarnings = FALSE)

  # Check required files
  amb_file <- file.path(dir_sp, "ambiental", "predicciones.csv")
  int_file <- file.path(dir_sp, "interseccion", "predicciones.csv")
  unc_file <- file.path(dir_sp, "incertidumbre", "incertidumbre.csv")

  if (!file.exists(int_file) || !file.exists(unc_file)) {
    cat("  [SKIP] Faltan predicciones o incertidumbre\n")
    next
  }

  tryCatch({

    # --- Cargar predicciones ---
    pred_amb <- read_csv(amb_file, show_col_types = FALSE)
    pred_int <- read_csv(int_file, show_col_types = FALSE)
    pred_unc <- read_csv(unc_file, show_col_types = FALSE)

    # Anadir CUADRICULA desde datos_pa (mismo orden de filas)
    pred_amb$CUADRICULA <- cuadriculas
    pred_int$CUADRICULA <- cuadriculas
    pred_unc$CUADRICULA <- cuadriculas

    # --- Unir con malla por CUADRICULA ---
    datos_mapa <- malla_wgs84 %>%
      select(CUADRICULA, geometry) %>%
      left_join(pred_amb %>% select(CUADRICULA, F_amb = F_glm_mean), by = "CUADRICULA") %>%
      left_join(pred_int %>% select(CUADRICULA, F_int = F_final_mean), by = "CUADRICULA") %>%
      left_join(pred_unc %>% select(CUADRICULA, U_final, W = W_norm, MESS), by = "CUADRICULA")

    # --- PA observada ---
    sp_col <- paste0("sp_", sp)
    if (!sp_col %in% names(datos_pa)) sp_col <- sp

    pa_especie <- datos_pa %>%
      filter(muestreado == 1) %>%
      select(CUADRICULA, PA = all_of(sp_col)) %>%
      drop_na()

    datos_mapa <- datos_mapa %>%
      left_join(pa_especie, by = "CUADRICULA")

    # --- Clasificar para bivariado ---
    datos_mapa <- datos_mapa %>%
      mutate(
        F_class = clasificar_terciles(F_int),
        U_class = clasificar_terciles(U_final),
        bivariado = map2_chr(F_class, U_class, ~{
          if (is.na(.x) || is.na(.y)) NA_character_
          else MATRIZ_BIVARIADO[.x, .y]
        })
      )

    # =========================================================================
    # PANEL SECEMU (2x2)
    # =========================================================================
    cat("  Panel SECEMU...\n")

    p1 <- crear_mapa(datos_mapa, "F_amb", "A) Favorabilidad Ambiental",
                     paleta = PALETA_FAV, limits = c(0, 1), legend_title = "F")
    p2 <- crear_mapa(datos_mapa, "F_int", "B) Favorabilidad Final",
                     paleta = PALETA_FAV, limits = c(0, 1), legend_title = "F")
    p3 <- crear_mapa(datos_mapa, "U_final", "C) Incertidumbre Total",
                     paleta = PALETA_INCERT, limits = c(0, 1), legend_title = "U")

    datos_pa_plot <- datos_mapa %>% filter(!is.na(PA)) %>% mutate(PA = factor(PA))
    p4 <- crear_mapa(datos_pa_plot, "PA", "D) Presencia/Ausencia",
                     paleta = COLORES_PA, discreto = TRUE, legend_title = "PA")

    panel_secemu <- (p1 | p2) / (p3 | p4) +
      plot_annotation(
        title = sp,
        subtitle = "Panel SECEMU - Atlas de Murcielagos | 10x10 km UTM",
        theme = theme(
          plot.title = element_text(size = 16, face = "bold.italic", hjust = 0.5),
          plot.subtitle = element_text(size = 12, hjust = 0.5),
          plot.background = element_rect(fill = "white", color = NA)
        )
      )

    guardar_mapa(panel_secemu, file.path(dir_out, "panel_SECEMU.png"),
                 width = WIDTH_PANEL, height = HEIGHT_PANEL)

    # =========================================================================
    # PANEL INCERTIDUMBRE (2x2 con bivariado)
    # =========================================================================
    cat("  Panel incertidumbre...\n")

    datos_mess <- datos_mapa %>%
      mutate(MESS_neg = ifelse(MESS < 0, MESS, NA))

    p_mess <- crear_mapa(datos_mess, "MESS_neg", "A) MESS (extrapolacion)",
                         paleta = rev(PALETA_MESS), limits = c(-100, 0),
                         legend_title = "MESS", na_color = "white")
    p_w <- crear_mapa(datos_mapa, "W", "B) W_bootstrap (IC 95%)",
                      paleta = PALETA_INCERT, limits = c(0, 1), legend_title = "W")
    p_u <- crear_mapa(datos_mapa, "U_final", "C) U_final",
                      paleta = PALETA_INCERT, limits = c(0, 1), legend_title = "U")
    p_biv <- crear_mapa_bivariado(datos_mapa)

    panel_incert <- (p_mess | p_w) / (p_u | p_biv) +
      plot_annotation(
        title = sp,
        subtitle = "Panel Incertidumbre - Atlas de Murcielagos | 10x10 km UTM",
        theme = theme(
          plot.title = element_text(size = 16, face = "bold.italic", hjust = 0.5),
          plot.subtitle = element_text(size = 12, hjust = 0.5),
          plot.background = element_rect(fill = "white", color = NA)
        )
      )

    guardar_mapa(panel_incert, file.path(dir_out, "panel_incertidumbre.png"),
                 width = WIDTH_PANEL, height = HEIGHT_PANEL)

    # =========================================================================
    # MAPAS INDIVIDUALES
    # =========================================================================
    cat("  Mapas individuales...\n")

    guardar_mapa(
      crear_mapa(datos_mapa, "F_amb", sprintf("%s - Favorabilidad Ambiental", sp),
                 paleta = PALETA_FAV, limits = c(0, 1), legend_title = "F"),
      file.path(dir_out, "mapa_F_amb.png"),
      width = WIDTH_INDIVIDUAL, height = HEIGHT_INDIVIDUAL)

    guardar_mapa(
      crear_mapa(datos_mapa, "F_int", sprintf("%s - Favorabilidad Final", sp),
                 paleta = PALETA_FAV, limits = c(0, 1), legend_title = "F"),
      file.path(dir_out, "mapa_F_final.png"),
      width = WIDTH_INDIVIDUAL, height = HEIGHT_INDIVIDUAL)

    guardar_mapa(
      crear_mapa(datos_mapa, "U_final", sprintf("%s - Incertidumbre", sp),
                 paleta = PALETA_INCERT, limits = c(0, 1), legend_title = "U"),
      file.path(dir_out, "mapa_U_final.png"),
      width = WIDTH_INDIVIDUAL, height = HEIGHT_INDIVIDUAL)

    guardar_mapa(
      crear_mapa_bivariado(datos_mapa, sprintf("%s - Bivariado F x U", sp)),
      file.path(dir_out, "mapa_bivariado.png"),
      width = WIDTH_INDIVIDUAL, height = HEIGHT_INDIVIDUAL)

    create_checkpoint(sp, CONFIG$output$base, "mapas")
    cat("  [OK] Mapas generados\n")

  }, error = function(e) {
    cat(sprintf("  [ERROR] %s\n", e$message))
  })
}

cat("\n[OK] Fase 7 completada\n")
