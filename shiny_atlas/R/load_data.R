# ==============================================================================
# load_data.R - Carga de datos al arrancar la app
# ==============================================================================

# Detectar si estamos dentro de shiny_atlas/ o en la raíz del proyecto
DATA_DIR <- if (file.exists("output_shiny")) {
  "output_shiny"
} else if (file.exists("../output_shiny")) {
  "../output_shiny"
} else {
  stop("No se encuentra output_shiny/. Ejecutar desde la raíz del proyecto o desde shiny_atlas/")
}

# Metadatos generales
META <- readRDS(file.path(DATA_DIR, "metadatos_especies.rds"))
INDICE_PNGS <- readRDS(file.path(DATA_DIR, "indice_pngs.rds"))

# Malla UTM compartida (geometría única para todas las especies)
MALLA_UTM <- readRDS(file.path(DATA_DIR, "mapas_sf", "_malla_utm.rds"))

# Especies modelizables
ESPECIES_MODELO <- META |>
  dplyr::filter(modelizable == TRUE) |>
  dplyr::arrange(especie)

# Choices para selector (especie_file como value, nombre científico como label)
ESPECIES_CHOICES <- setNames(
  ESPECIES_MODELO$especie_file,
  ESPECIES_MODELO$especie
)

# Cargar datos de una especie (reconstruye sf uniendo malla + atributos)
cargar_especie <- function(sp_file) {
  datos_mapa <- readRDS(file.path(DATA_DIR, "mapas_sf", paste0(sp_file, "_mapa.rds")))
  mapa_sf <- dplyr::left_join(MALLA_UTM, datos_mapa, by = "CUADRICULA")

  list(
    mapa   = mapa_sf,
    vars   = readRDS(file.path(DATA_DIR, "variables_coefs",    paste0(sp_file, "_vars.rds"))),
    curvas = readRDS(file.path(DATA_DIR, "curvas_respuesta",   paste0(sp_file, "_curvas.rds"))),
    metr   = readRDS(file.path(DATA_DIR, "metricas_validacion", paste0(sp_file, "_metricas.rds"))),
    meta   = META |> dplyr::filter(especie_file == sp_file)
  )
}
