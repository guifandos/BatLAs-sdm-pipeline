# ==============================================================================
# 01h_mapa_chequeo.R - Mapas QA de predictores (opcional)
# ==============================================================================
#
# RAZON CIENTIFICA — MAPAS DE CHEQUEO (QA):
# La validacion visual de las variables predictoras es un paso esencial antes
# del modelado. Los mapas QA permiten detectar:
#
#   1. ERRORES DE DATOS: valores anomalos (e.g., temperaturas negativas en
#      Andalucia, precipitacion cero en Galicia) que indican problemas en la
#      extraccion zonal o en la fuente original.
#   2. ARTEFACTOS ESPACIALES: discontinuidades artificiales en los bordes
#      de las capas (e.g., cambio brusco entre dos fuentes de datos
#      climaticos), patrones de cuadricula no explicables ecologicamente.
#   3. COHERENCIA BIOGEOGRAFICA: verificar que los gradientes espaciales
#      coinciden con el conocimiento experto (e.g., gradiente de aridez
#      SE-NW, karst concentrado en el arco calizo cantabro-mediterraneo,
#      bosques en la mitad norte).
#   4. COMPLETITUD: detectar cuadriculas con NA sistematicos que podrian
#      causar perdida de datos en los modelos.
#
# Se seleccionan automaticamente las variables mas representativas de cada
# grupo (clima, cobertura, geologia) para no generar excesivos mapas.
#
# INPUT:  CONFIG$paths$predictores_seo_geo_sf
# OUTPUT: Mapas PNG en CONFIG$output$figs
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

# --- Cargar configuracion (idempotente) ---
if (!exists("CONFIG")) source("R/00_setup/00_config.R")

suppressPackageStartupMessages({
  library(tidyverse)
  library(sf)
  library(rnaturalearth)
  library(scico)
})

cat("\n=== 01h: MAPAS DE CHEQUEO (QA) ===\n\n")

# Cargar datos espaciales (predictores unidos a la malla sf)
predictores_sf <- readRDS(CONFIG$paths$predictores_seo_geo_sf)
cat(sprintf("Predictores SF: %d cuadriculas\n", nrow(predictores_sf)))

# Mapa base: paises de Europa para contexto geografico
iberia <- ne_countries(scale = 50, continent = "Europe", returnclass = "sf") %>%
  st_transform(st_crs(predictores_sf))

# Directorio de salida
dir.create(CONFIG$output$figs, recursive = TRUE, showWarnings = FALSE)

# Seleccionar variables de interes para QA: se eligen automaticamente
# las mas representativas de cada grupo tematico (clima, cobertura, geologia)
# para ofrecer una vision general sin generar excesivos ficheros.
vars_qa <- c()
nombres_pred <- names(st_drop_geometry(predictores_sf))

# Variables climaticas (bioclimaticas, temperatura, precipitacion, aridez)
clima <- nombres_pred[str_detect(nombres_pred, "(?i)(bio|temp|prec|arid|pet|etp)")]
if (length(clima) > 0) vars_qa <- c(vars_qa, head(clima, 4))

# Variables de cobertura del suelo (CORINE agrupado, bosque, urbano)
cober <- nombres_pred[str_detect(nombres_pred, "(?i)(CLC_|bosque|forest|urban)")]
if (length(cober) > 0) vars_qa <- c(vars_qa, head(cober, 3))

# Variables geologicas (karst, litologia agrupada/PCA)
geo <- nombres_pred[str_detect(nombres_pred, "(?i)(Karst|Lito_)")]
if (length(geo) > 0) vars_qa <- c(vars_qa, head(geo, 3))

vars_qa <- unique(vars_qa)

if (length(vars_qa) == 0) {
  cat("  Sin variables numericas para mapear, omitiendo\n")
} else {
  cat(sprintf("Generando %d mapas de chequeo...\n", length(vars_qa)))

  for (var in vars_qa) {
    if (!is.numeric(predictores_sf[[var]])) next
    if (all(is.na(predictores_sf[[var]]))) next

    # Mapa coropletico: cada cuadricula UTM 10x10 coloreada por el valor
    # del predictor. Se usa la paleta 'batlow' (divergente, daltonico-segura)
    # del paquete scico, adecuada para gradientes continuos.
    p <- ggplot() +
      geom_sf(data = iberia, fill = "grey95", color = "grey60", linewidth = 0.3) +
      geom_sf(data = predictores_sf, aes(fill = .data[[var]]),
              color = NA, linewidth = 0) +
      scale_fill_scico(palette = "batlow", na.value = "grey80",
                       name = var) +
      coord_sf(xlim = st_bbox(predictores_sf)[c(1, 3)],
               ylim = st_bbox(predictores_sf)[c(2, 4)]) +
      labs(title = paste("QA:", var)) +
      theme_minimal(base_size = 10)

    fname <- file.path(CONFIG$output$figs,
                       paste0("qa_", str_replace_all(var, "[^A-Za-z0-9]", "_"), ".png"))
    ggsave(fname, p, width = 8, height = 6, dpi = 150)
  }

  cat(sprintf("[OK] %d mapas guardados en %s\n", length(vars_qa), CONFIG$output$figs))
}
