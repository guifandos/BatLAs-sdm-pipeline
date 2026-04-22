# ==============================================================================
# 04a_mapas_momat.R - Generacion de mapas individuales estilo MOMAT
# ==============================================================================
#
# Replica los mapas del pipeline del atlas de murcielagos con el estilo
# visual de MOMAT (Santoro et al.): paleta blanco-marron para favorabilidad,
# paleta blanco-azul para incertidumbre, bordes administrativos (provincias
# y CCAA), sin ejes ni grid.
#
# OUTPUTS por especie (en mapas_momat/):
#   1. mapa_F_amb.tiff        - Favorabilidad ambiental
#   2. mapa_F_final.tiff      - Favorabilidad final (interseccion difusa)
#   3. mapa_F_espacial.tiff   - Favorabilidad espacial
#   4. mapa_U_final.tiff      - Incertidumbre total
#   5. mapa_bivariado.tiff    - Bivariado F x U
#   6. mapa_F_final_ci.tiff   - Favorabilidad final + inset incertidumbre
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

if (!exists("CONFIG")) source("R/00_setup/00_config.R")
source("R/utils/utils_checkpoints.R")
source("R/utils/utils_mapas_momat.R")

suppressPackageStartupMessages({
  library(tidyverse)
  library(sf)
})

cat("\n========================================\n")
cat("  MAPAS ESTILO MOMAT\n")
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

# Reproyectar al CRS de los shapefiles administrativos
provincias_tmp <- st_read("data/shapefiles/admin/Provincias.shp", quiet = TRUE)
crs_admin <- st_crs(provincias_tmp)
rm(provincias_tmp)

malla_ll <- st_transform(malla, crs_admin)
cat(sprintf("  Malla: %d cuadriculas (CRS admin)\n", nrow(malla_ll)))

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

  sp_file <- str_replace_all(sp, " ", "_")
  dir_sp <- file.path(CONFIG$output$base, sp_file)
  dir_out <- file.path("output_mapas_estilo_momat", sp_file)
  dir.create(dir_out, recursive = TRUE, showWarnings = FALSE)

  # Check required files
  amb_file <- file.path(dir_sp, "ambiental", "predicciones.csv")
  int_file <- file.path(dir_sp, "interseccion", "predicciones.csv")
  unc_file <- file.path(dir_sp, "incertidumbre", "incertidumbre.csv")
  esp_file <- file.path(dir_sp, "espacial", "predicciones.csv")

  if (!file.exists(int_file) || !file.exists(unc_file)) {
    cat("  [SKIP] Faltan predicciones o incertidumbre\n")
    next
  }

  tryCatch({

    # --- Cargar predicciones ---
    pred_amb <- read_csv(amb_file, show_col_types = FALSE)
    pred_int <- read_csv(int_file, show_col_types = FALSE)
    pred_unc <- read_csv(unc_file, show_col_types = FALSE)

    pred_amb$CUADRICULA <- cuadriculas
    pred_int$CUADRICULA <- cuadriculas
    pred_unc$CUADRICULA <- cuadriculas

    # --- Espacial (opcional) ---
    tiene_espacial <- file.exists(esp_file)
    if (tiene_espacial) {
      pred_esp <- read_csv(esp_file, show_col_types = FALSE)
      pred_esp$CUADRICULA <- cuadriculas
    }

    # --- Unir con malla ---
    datos_mapa <- malla_ll %>%
      select(CUADRICULA, geometry) %>%
      left_join(pred_amb %>% select(CUADRICULA, F_amb = F_glm_mean),
                by = "CUADRICULA") %>%
      left_join(pred_int %>% select(CUADRICULA, F_int = F_final_mean),
                by = "CUADRICULA") %>%
      left_join(pred_unc %>% select(CUADRICULA, U_final, W = W_norm, MESS),
                by = "CUADRICULA")

    if (tiene_espacial) {
      # Detectar nombre de columna de favorabilidad espacial
      col_esp <- intersect(
        c("F_esp_mean", "F_espacial_mean", "favorabilidad_esp", "F_glm_mean"),
        names(pred_esp)
      )
      if (length(col_esp) > 0) {
        datos_mapa <- datos_mapa %>%
          left_join(
            pred_esp %>% select(CUADRICULA, F_esp = all_of(col_esp[1])),
            by = "CUADRICULA"
          )
      } else {
        tiene_espacial <- FALSE
        cat("  [WARN] Espacial encontrado pero sin columna de favorabilidad reconocida\n")
      }
    }

    # --- PA observada ---
    sp_col <- paste0("sp_", sp)
    if (!sp_col %in% names(datos_pa)) sp_col <- sp

    pa_especie <- datos_pa %>%
      filter(muestreado == 1) %>%
      select(CUADRICULA, PA = all_of(sp_col)) %>%
      drop_na()

    datos_mapa <- datos_mapa %>%
      left_join(pa_especie, by = "CUADRICULA")

    # --- Clasificar bivariado ---
    datos_mapa <- datos_mapa %>%
      mutate(
        F_class = clasificar_terciles_momat(F_int),
        U_class = clasificar_terciles_momat(U_final),
        bivariado = map2_chr(F_class, U_class, ~{
          if (is.na(.x) || is.na(.y)) NA_character_
          else MATRIZ_BIVARIADO_MOMAT[.x, .y]
        })
      )

    # =========================================================================
    # MAPAS INDIVIDUALES
    # =========================================================================

    # 1. Favorabilidad ambiental
    cat("  F_amb...\n")
    guardar_mapa_momat(
      crear_mapa_momat(datos_mapa, "F_amb",
                       sprintf("%s - Favorabilidad Ambiental", sp)),
      file.path(dir_out, "mapa_F_amb.tiff")
    )

    # 2. Favorabilidad final (interseccion difusa)
    cat("  F_final...\n")
    guardar_mapa_momat(
      crear_mapa_momat(datos_mapa, "F_int",
                       sprintf("%s - Favorabilidad Final", sp)),
      file.path(dir_out, "mapa_F_final.tiff")
    )

    # 3. Favorabilidad espacial
    if (tiene_espacial) {
      cat("  F_espacial...\n")
      guardar_mapa_momat(
        crear_mapa_momat(datos_mapa, "F_esp",
                         sprintf("%s - Favorabilidad Espacial", sp)),
        file.path(dir_out, "mapa_F_espacial.tiff")
      )
    }

    # 4. Incertidumbre total
    cat("  U_final...\n")
    guardar_mapa_momat(
      crear_mapa_momat(datos_mapa, "U_final",
                       sprintf("%s - Incertidumbre", sp),
                       paleta = PALETA_INCERT_MOMAT),
      file.path(dir_out, "mapa_U_final.tiff")
    )

    # 5. Bivariado F x U
    cat("  Bivariado...\n")
    guardar_mapa_momat(
      crear_mapa_bivariado_momat(datos_mapa,
                                  sprintf("%s - Bivariado F x U", sp)),
      file.path(dir_out, "mapa_bivariado.tiff")
    )

    # 6. Favorabilidad final + inset incertidumbre
    cat("  F_final + inset CI...\n")
    guardar_mapa_momat(
      crear_mapa_con_inset(datos_mapa, "F_int",
                           sprintf("%s - Favorabilidad Final", sp),
                           col_incert = "U_final"),
      file.path(dir_out, "mapa_F_final_ci.tiff")
    )

    cat("  [OK] Mapas MOMAT generados\n")

  }, error = function(e) {
    cat(sprintf("  [ERROR] %s\n", e$message))
  })
}

cat("\n[OK] Mapas MOMAT completados\n")
