# ==============================================================================
# global.R - Cargado automaticamente por Shiny antes de ui.R y server.R
# ==============================================================================

options(shiny.maxRequestSize = 50 * 1024^2)

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(shinyWidgets)
  library(tidyverse)
  library(sf)
  library(leaflet)
  library(DT)
  library(tippy)
  library(scales)
  library(shinyjs)
})

# Cargar modulos
source("R/load_data.R")
source("R/helpers_ui.R")
source("R/helpers_mapa.R")
source("R/helpers_graficos.R")
source("R/diccionario_variables.R")

# Registrar directorio de PNGs como recurso servible por Shiny
addResourcePath("mapas_png", file.path(DATA_DIR, "mapas_png"))
