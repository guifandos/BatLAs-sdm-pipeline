# ==============================================================================
# 01d_agrupar_corine.R - Agrupar variables CORINE Land Cover
# ==============================================================================
#
# RAZON CIENTIFICA:
# CORINE Land Cover (CLC) clasifica el uso/cobertura del suelo en ~44 clases
# de nivel 3 (e.g., 311 = bosque caducifolio, 112 = tejido urbano discontinuo).
# Para murcielagos, muchas de esas clases son funcionalmente equivalentes.
# Agrupamos en 9 GRUPOS ECOLOGICOS que reflejan los tres ejes funcionales
# del habitat de quiropteros:
#
#   - REFUGIO (roosting): zonas urbanas (edificios = refugios antropicos),
#     roquedos/cuevas (refugios naturales), bosques densos (grietas en arboles).
#   - ALIMENTACION (foraging): masas de agua (emergencia de insectos acuaticos),
#     praderas/pastizales (insectos voladores), cultivos (polillas, escarabajos).
#   - DESPLAZAMIENTO (commuting): setos/bordes de bosque (corredores lineales),
#     mosaicos agroforestales (conectividad paisajistica).
#
# Al sumar las proporciones de las clases CLC originales dentro de cada grupo,
# reducimos de ~44 variables dispersas a 9 variables ecologicamente
# interpretables, eliminando colinealidad y mejorando la estabilidad de los
# modelos.
#
# NOTA SOBRE ELIMINACION DE CLC_HISTO ORIGINALES:
# Tras la agrupacion, las columnas CLC_HISTO_{codigo} originales se eliminan
# porque (a) son redundantes con los nuevos grupos, (b) muchas tienen valores
# casi cero en la mayoria de cuadriculas (esparsidad), y (c) introducen alta
# colinealidad que degrada la seleccion de variables en Fase 1. Dado que 01c
# ya no escala las proporciones, las columnas CLC_HISTO llegan en proporcion
# cruda (0-1), que es la unidad correcta para sumarlas en grupos.
#
# INPUT:  CONFIG$paths$predictores_seo (lista from 01c)
# OUTPUT: CONFIG$paths$predictores_seo (updated in-place)
#
# Crea 9 grupos ecologicos de CORINE si existen columnas CLC_HISTO_
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

# --- Cargar configuracion y utilidades (idempotente) ---
if (!exists("CONFIG")) source("R/00_setup/00_config.R")
if (!exists("agrupar_corine")) source("R/utils/utils_corine.R")
if (!exists("norm_id")) source("R/utils/utils_checkpoints.R")

suppressPackageStartupMessages(library(tidyverse))

cat("\n=== 01d: AGRUPAR CORINE ===\n\n")

# Cargar predictores
predictores <- readRDS(CONFIG$paths$predictores_seo)

# Funcion auxiliar: aplicar agrupacion CORINE si hay columnas HISTO presentes.
# Se buscan columnas con patron CLC_HISTO_[digitos], que corresponden a las
# proporciones de cada clase CLC nivel 3 dentro de cada cuadricula UTM 10x10.
aplicar_corine_si_disponible <- function(df, nombre) {
  if (is.null(df)) return(df)
  columnas_clc <- names(df)[str_detect(names(df), "^CLC_HISTO_[0-9]")]
  if (length(columnas_clc) > 0) {
    cat(sprintf("  %s: %d columnas CLC_HISTO encontradas, agrupando...\n", nombre, length(columnas_clc)))
    # agrupar_corine() suma las proporciones CLC en 9 grupos ecologicos
    df <- agrupar_corine(df)
    # Eliminar columnas HISTO originales (redundantes, colineales, dispersas)
    df <- df %>% select(-starts_with("CLC_HISTO_"))
    cat(sprintf("  %s: Variables tras agrupacion: %d\n", nombre, ncol(df)))
  } else {
    cat(sprintf("  %s: Sin columnas CLC_HISTO, omitiendo\n", nombre))
  }
  return(df)
}

# Aplicar a EC (Peninsula = Espana Continental) y BAL (Baleares)
predictores$ec <- aplicar_corine_si_disponible(predictores$ec, "EC")
predictores$bal <- aplicar_corine_si_disponible(predictores$bal, "BAL")

# Si tambien hay versiones raw (sin escalar), actualizarlas de la misma forma.
# Esto asegura consistencia entre las dos versiones del dataset.
if (!is.null(predictores$ec_raw)) {
  predictores$ec_raw <- aplicar_corine_si_disponible(predictores$ec_raw, "EC_raw")
}
if (!is.null(predictores$bal_raw)) {
  predictores$bal_raw <- aplicar_corine_si_disponible(predictores$bal_raw, "BAL_raw")
}

# Guardar actualizado
saveRDS(predictores, CONFIG$paths$predictores_seo)
cat("[OK] Predictores actualizados con CORINE agrupado\n")
