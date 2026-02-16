# ==============================================================================
# 00_packages.R - INSTALACION Y CARGA DE PAQUETES
# ==============================================================================
#
# Gestiona las dependencias del pipeline.
# Si usas renv, ejecuta primero: renv::restore()
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

# Lista de paquetes requeridos
paquetes_requeridos <- c(
  # --- Manipulacion de datos ---
  "tidyverse",     # dplyr, tidyr, ggplot2, readr, stringr, purrr, tibble, forcats
  "jsonlite",      # Lectura/escritura JSON

  # --- Datos espaciales ---
  "sf",            # Simple features (geometrias)
  "terra",         # Raster processing

  # --- Modelizacion ---
  "mgcv",          # GAM (modelos aditivos generalizados)
  "car",           # VIF (factor de inflacion de varianza)
  "MuMIn",         # AICc (criterio de informacion corregido)
  "pROC",          # AUC, ROC curves

  # --- Litologia (PCA) ---
  "FactoMineR",    # PCA
  "factoextra",    # Visualizacion PCA

  # --- Lectura de datos ---
  "readxl",        # Lectura de archivos Excel (.xlsx)
  "broom",         # Extraccion de coeficientes de modelos (tidy, glance)

  # --- Visualizacion ---
  "scico",         # Paletas colorblind-friendly (batlow, lajolla, vik)
  "patchwork",     # Composicion de paneles de graficos
  "rnaturalearth", # Limites politicos (mapa base)
  "rnaturalearthdata", # Datos para mapas base

  # --- Paralelizacion ---
  "future",        # Backend de paralelizacion
  "future.apply",  # future_lapply para loops paralelos

  # --- Reproducibilidad ---
  "renv"           # Gestion de versiones de paquetes
)

# Instalar los que faltan
paquetes_faltantes <- paquetes_requeridos[!paquetes_requeridos %in% installed.packages()[, "Package"]]

if (length(paquetes_faltantes) > 0) {
  cat("Instalando paquetes faltantes:\n")
  cat(paste(" -", paquetes_faltantes, collapse = "\n"), "\n\n")
  install.packages(paquetes_faltantes, repos = "https://cran.r-project.org")
} else {
  cat("[OK] Todos los paquetes requeridos estan instalados\n")
}

# Cargar paquetes principales (suprimiendo mensajes de startup)
suppressPackageStartupMessages({
  library(tidyverse)
  library(sf)
  library(jsonlite)
  library(mgcv)
  library(pROC)
  library(scico)
  library(patchwork)
})

message("[OK] Paquetes cargados")
