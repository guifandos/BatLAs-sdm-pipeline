# ==============================================================================
# 00_inicio_rapido.R - GUIA DE INICIO RAPIDO
# ==============================================================================
#
# Este script configura el entorno R y ejecuta un ejemplo piloto del pipeline
# con 2 especies. Diseñado para verificar que todo funciona antes de lanzar
# el pipeline completo (~25 especies, 3-6 horas).
#
# REQUISITOS:
#   - R >= 4.1
#   - Datos brutos en data/raw/ (presencias, shapefiles, variables Excel, geologia)
#   - Archivos de metadatos en data/metadata/ (incluidos en Git)
#
# USO:
#   1. Abrir el proyecto en RStudio (o setwd() a la raiz del proyecto)
#   2. Ejecutar este script: source("vignettes/00_inicio_rapido.R")
#
# TIEMPO ESTIMADO: ~10-15 minutos (2 especies, 50 bootstrap)
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

cat("\n")
cat("================================================================================\n")
cat("  INICIO RAPIDO - ATLAS DE MURCIELAGOS SECEMU\n")
cat("================================================================================\n\n")

# ==============================================================================
# PASO 1: VERIFICAR DIRECTORIO DE TRABAJO
# ==============================================================================
# El pipeline asume que se ejecuta desde la raiz del proyecto.

if (!file.exists("R/run_pipeline.R")) {
  stop(paste0(
    "Este script debe ejecutarse desde la raiz del proyecto.\n",
    "  Directorio actual: ", getwd(), "\n",
    "  Use setwd() o abra el .Rproj para cambiar al directorio correcto."
  ))
}
cat("[OK] Directorio de trabajo: ", getwd(), "\n\n")

# ==============================================================================
# PASO 2: INSTALAR Y CARGAR PAQUETES
# ==============================================================================

cat("--- Paso 2: Instalando y cargando paquetes ---\n")
source("R/00_setup/00_packages.R")
cat("\n")

# ==============================================================================
# PASO 3: CONFIGURAR ENTORNO renv (REPRODUCIBILIDAD)
# ==============================================================================
# renv captura las versiones exactas de todos los paquetes.
# Si renv.lock ya existe, restaura esas versiones.
# Si no existe, crea un snapshot del entorno actual.

cat("--- Paso 3: Configurando renv ---\n")

if (file.exists("renv.lock")) {
  cat("  renv.lock encontrado. Restaurando entorno...\n")
  tryCatch({
    renv::restore(prompt = FALSE)
    cat("  [OK] Entorno restaurado desde renv.lock\n")
  }, error = function(e) {
    cat("  [AVISO] renv::restore() fallo:", e$message, "\n")
    cat("  Continuando con paquetes actuales.\n")
  })
} else {
  cat("  renv.lock no encontrado. Creando snapshot...\n")
  tryCatch({
    renv::init(bare = TRUE)
    renv::snapshot(prompt = FALSE)
    cat("  [OK] renv.lock creado\n")
  }, error = function(e) {
    cat("  [AVISO] renv::snapshot() fallo:", e$message, "\n")
    cat("  Continuando sin lockfile. El entorno no sera 100% reproducible.\n")
  })
}
cat("\n")

# ==============================================================================
# PASO 4: VERIFICAR DATOS DE ENTRADA
# ==============================================================================

cat("--- Paso 4: Verificando datos de entrada ---\n")

archivos_criticos <- list(
  "Presencias (CSV)" = "data/raw/presencias/_final_coords_UTM_editada_20250929.csv",
  "Shapefile Peninsula" = "data/raw/shapefiles/Malla10x10_clip.shp",
  "Variables EC (Excel)" = "data/raw/variables/Variables_EC.xlsx",
  "Karst (CSV)" = "data/raw/variables/10x10_Karst_PIBAL.csv",
  "Litologia (CSV)" = "data/raw/variables/10x10_lito_COLOR_PIBAL.csv",
  "Metadata: gremios" = "data/metadata/especies_gremios.csv",
  "Metadata: complejos" = "data/metadata/complejos_taxonomicos.csv"
)

faltantes <- c()
for (nombre in names(archivos_criticos)) {
  ruta <- archivos_criticos[[nombre]]
  existe <- file.exists(ruta)
  cat(sprintf("  %s %s\n", if (existe) "[OK]" else "[!!]", nombre))
  if (!existe) faltantes <- c(faltantes, nombre)
}

if (length(faltantes) > 0) {
  cat(sprintf("\n  FALTAN %d archivos criticos:\n", length(faltantes)))
  for (f in faltantes) {
    cat(sprintf("    - %s: %s\n", f, archivos_criticos[[f]]))
  }
  cat("\n  Coloque los archivos en las rutas indicadas y vuelva a ejecutar.\n")
  cat("  Si solo tiene metadatos, puede ejecutar los tests: source('tests/test_pipeline.R')\n\n")
  stop("Datos de entrada incompletos.")
}
cat("\n  [OK] Todos los archivos de entrada encontrados\n\n")

# ==============================================================================
# PASO 5: CARGAR CONFIG Y AJUSTAR PARA MODO PILOTO
# ==============================================================================
# El modo piloto usa 2 especies representativas y reduce bootstrap a 50
# iteraciones para ejecutar rapido (~10 min).

cat("--- Paso 5: Configurando modo piloto ---\n")

source("R/00_setup/00_config.R")

# Sobreescribir CONFIG para modo piloto
CONFIG$especies$piloto <- c("Rhinolophus ferrumequinum", "Pipistrellus pipistrellus")

# Reducir bootstrap para ejecucion rapida
CONFIG$ambiental$n_bootstrap <- 50
CONFIG$espacial$n_bootstrap <- 50

# Activar TODAS las fases
CONFIG$control$ejecutar$preparacion_datos <- TRUE
CONFIG$control$ejecutar$seleccion_variables <- TRUE
CONFIG$control$ejecutar$modelo_ambiental <- TRUE
CONFIG$control$ejecutar$modelo_espacial <- TRUE
CONFIG$control$ejecutar$interseccion <- TRUE
CONFIG$control$ejecutar$validacion <- TRUE
CONFIG$control$ejecutar$incertidumbre <- TRUE
CONFIG$control$ejecutar$mapas <- TRUE

# Reducir repeticiones de CV
CONFIG$validacion$n_rep <- 2

# Forzar recalculo (sin checkpoints previos)
CONFIG$control$force_rerun <- TRUE

cat(sprintf("  Especies piloto: %s\n",
            paste(CONFIG$especies$piloto, collapse = ", ")))
cat(sprintf("  Bootstrap: %d iteraciones (produccion: 500)\n",
            CONFIG$ambiental$n_bootstrap))
cat(sprintf("  CV repeticiones: %d (produccion: 10)\n\n",
            CONFIG$validacion$n_rep))

# ==============================================================================
# PASO 6: VALIDAR CONFIGURACION
# ==============================================================================

cat("--- Paso 6: Validando configuracion ---\n")
validar_config()
cat("\n")

# ==============================================================================
# PASO 7: EJECUTAR PIPELINE PILOTO
# ==============================================================================

cat("--- Paso 7: Ejecutando pipeline piloto ---\n")
cat("  (Esto tomara ~10-15 minutos)\n\n")

t_inicio <- Sys.time()

# Inicializar logging
source("R/utils/utils_logging.R")
init_log()
log_event("piloto", "", "INFO", "Pipeline piloto iniciado")

# Crear directorios de salida
dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
dir.create("data/modelado_ready", recursive = TRUE, showWarnings = FALSE)
dir.create(CONFIG$output$base, recursive = TRUE, showWarnings = FALSE)
dir.create(CONFIG$output$logs, recursive = TRUE, showWarnings = FALSE)
dir.create(CONFIG$output$checks, recursive = TRUE, showWarnings = FALSE)
dir.create(CONFIG$output$figs, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(CONFIG$output$seleccion, "variables_json"),
           recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(CONFIG$output$seleccion, "diagnosticos"),
           recursive = TRUE, showWarnings = FALSE)

# --- Fase 0: Preparacion de datos ---
cat("\n>>> FASE 0: PREPARACION DE DATOS <<<\n")
source("R/01_data_preparation/01a_preparar_PA_metodo.R")
source("R/01_data_preparation/01b_cargar_malla.R")
source("R/01_data_preparation/01c_cargar_variables_excel.R")
source("R/01_data_preparation/01d_agrupar_corine.R")
source("R/01_data_preparation/01e_procesar_geologia.R")
source("R/01_data_preparation/01f_unir_predictores.R")
source("R/01_data_preparation/01g_crear_PAxENV_metodo.R")

# --- Fase 1: Seleccion de variables ---
cat("\n>>> FASE 1: SELECCION DE VARIABLES <<<\n")
source("R/02_variable_selection/02d_ejecutar_seleccion.R")

# --- Fase 2: Modelo ambiental ---
cat("\n>>> FASE 2: MODELO AMBIENTAL <<<\n")
source("R/03_modeling/03a_modelo_ambiental.R")

# --- Fase 3: Modelo espacial ---
cat("\n>>> FASE 3: MODELO ESPACIAL <<<\n")
source("R/03_modeling/03b_modelo_espacial.R")

# --- Fase 4: Interseccion fuzzy ---
cat("\n>>> FASE 4: INTERSECCION FUZZY <<<\n")
source("R/03_modeling/03c_interseccion_fuzzy.R")

# --- Fase 5: Validacion cruzada ---
cat("\n>>> FASE 5: VALIDACION CRUZADA <<<\n")
source("R/03_modeling/03d_validacion_cv.R")

# --- Fase 6: Incertidumbre ---
cat("\n>>> FASE 6: INCERTIDUMBRE <<<\n")
source("R/03_modeling/03e_incertidumbre.R")

# --- Fase 7: Mapas ---
cat("\n>>> FASE 7: MAPAS ATLAS <<<\n")
source("R/04_visualization/04a_mapas_atlas.R")

t_total <- difftime(Sys.time(), t_inicio, units = "mins")

# ==============================================================================
# PASO 8: VERIFICAR RESULTADOS
# ==============================================================================

cat("\n")
cat("================================================================================\n")
cat("  VERIFICACION DE RESULTADOS\n")
cat("================================================================================\n\n")

for (sp in CONFIG$especies$piloto) {
  sp_file <- gsub(" ", "_", sp)
  dir_sp <- file.path(CONFIG$output$base, sp_file)

  cat(sprintf("--- %s ---\n", sp))

  fases_check <- c(
    "ambiental" = file.path(dir_sp, "ambiental", "predicciones.csv"),
    "espacial" = file.path(dir_sp, "espacial", "predicciones.csv"),
    "interseccion" = file.path(dir_sp, "interseccion", "predicciones.csv"),
    "validacion" = file.path(dir_sp, "validacion", "metricas_cv.csv"),
    "incertidumbre" = file.path(dir_sp, "incertidumbre", "incertidumbre.csv"),
    "mapas" = file.path(dir_sp, "mapas", "checkpoint_mapas.txt")
  )

  for (fase in names(fases_check)) {
    existe <- file.exists(fases_check[[fase]])
    cat(sprintf("  %s %s\n", if (existe) "[OK]" else "[!!]", fase))
  }

  # Mostrar metricas si existen
  metricas_file <- file.path(dir_sp, "ambiental", "metricas_holdout.csv")
  if (file.exists(metricas_file)) {
    met <- read.csv(metricas_file)
    cat(sprintf("  AUC=%.3f TSS=%.3f\n", met$AUC[1], met$TSS[1]))
  }
  cat("\n")
}

# ==============================================================================
# RESUMEN FINAL
# ==============================================================================

cat("================================================================================\n")
cat("  PIPELINE PILOTO COMPLETADO\n")
cat("================================================================================\n\n")

cat(sprintf("Tiempo total: %.1f minutos\n", as.numeric(t_total)))
cat(sprintf("Especies procesadas: %d\n", length(CONFIG$especies$piloto)))
cat(sprintf("Output en: %s\n\n", CONFIG$output$base))

log_event("piloto", "", "INFO", sprintf("Pipeline piloto completado en %.1f min", as.numeric(t_total)))
log_summary()

cat("\n")
cat("SIGUIENTE PASO:\n")
cat("  Para ejecutar el pipeline completo con todas las especies:\n")
cat("    1. Editar R/00_setup/00_config.R:\n")
cat("       - Poner especies$piloto = NULL  (procesa todas)\n")
cat("       - Poner ambiental$n_bootstrap = 500\n")
cat("       - Poner validacion$n_rep = 10\n")
cat("    2. source('R/run_pipeline.R')\n")
cat("\n")
cat("  Para ejecutar solo fases especificas:\n")
cat("    - Desactivar fases ya completadas en CONFIG$control$ejecutar\n")
cat("    - Los checkpoints evitan recalculos innecesarios\n")
cat("\n")
cat("================================================================================\n")
