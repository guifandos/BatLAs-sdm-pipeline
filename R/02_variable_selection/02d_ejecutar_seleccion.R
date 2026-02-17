# ==============================================================================
# 02d_ejecutar_seleccion.R - Ejecutar seleccion para todas las especies
# ==============================================================================
#
# Script orquestador que:
#   1. Carga los datos PAxENV (presencia/ausencia + variables ambientales)
#   2. Carga la clasificacion de gremios desde CSVs
#   3. Determina las especies modelizables (filtradas, piloto, excluidas)
#   4. Para cada especie, ejecuta el pipeline de 7 fases (02b)
#   5. Genera un JSON por especie y un CSV resumen de diagnostico
#
# Este script se invoca desde run_pipeline.R (Fase 1) o de forma independiente.
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

# --- Carga condicional de dependencias ---
# Si ya fueron cargadas por run_pipeline.R, no se recargan.
if (!exists("CONFIG")) source("R/00_setup/00_config.R")
if (!exists("run_pipeline_especie")) source("R/02_variable_selection/02b_pipeline_seleccion.R")

suppressPackageStartupMessages({
  library(tidyverse)
  library(jsonlite)
})

cat("\n========================================\n")
cat("  FASE 1: SELECCION DE VARIABLES\n")
cat("========================================\n\n")

# --- Crear directorios de salida ---
dir.create(CONFIG$paths$variables_json, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(CONFIG$output$seleccion, "diagnosticos"), recursive = TRUE, showWarnings = FALSE)

# --- Cargar datos PAxENV (formato ancho compatible) ---
# El RDS contiene todas las cuadriculas con columnas:
#   - sp_<especie>: presencia/ausencia (1/0) por especie
#   - m_<metodo>: flag de muestreo por metodo
#   - variables ambientales: bio1, altitud, CLC_bosques, etc.
#   - CUADRICULA, ID_NORM, muestreado, n_metodos, factor_incert
datos_pa <- readRDS(CONFIG$paths$pa_data)
datos_pa <- normalizar_id_tabla(datos_pa)

# --- Cargar gremios desde CSV ---
# gremios es una lista con:
#   $especies:      tibble con columnas (especie, refugio, alimentacion, modelar)
#   $refugio:       tibble con categorias y variables_prioritarias por refugio
#   $alimentacion:  tibble con categorias y variables_prioritarias por alimentacion
#   $complejos:     tibble de complejos taxonomicos (opcional)
gremios <- cargar_gremios()

# --- Validar estructura de la tabla de gremios ---
# Verificar que la tabla de especies tiene las columnas requeridas
cols_requeridas <- c("especie", "refugio", "alimentacion", "modelar")
cols_faltantes <- setdiff(cols_requeridas, names(gremios$especies))
if (length(cols_faltantes) > 0) {
  stop(sprintf("La tabla de gremios (%s) no tiene las columnas requeridas: %s",
               CONFIG$paths$especies_gremios, paste(cols_faltantes, collapse = ", ")))
}

# --- Determinar especies a procesar ---
# Las columnas de especies en datos_pa tienen prefijo "sp_" (p.ej., "sp_Myotis myotis").
# Los nombres en especies_gremios.csv NO tienen prefijo.
# El str_remove("^sp_") los hace coincidir correctamente.
sp_cols <- names(datos_pa)[str_detect(names(datos_pa), "^sp_")]
especies_en_datos <- str_remove(sp_cols, "^sp_")

# Validar que las especies en datos tienen asignacion de gremio
# (especies sin gremio pasarian la seleccion con prioridad 1 por defecto,
# lo que puede producir modelos ecologicamente poco informativos)
sp_sin_gremio <- setdiff(especies_en_datos, gremios$especies$especie)
if (length(sp_sin_gremio) > 0) {
  warning(sprintf(
    "  %d especies en datos no tienen asignacion de gremio en '%s': %s",
    length(sp_sin_gremio),
    basename(CONFIG$paths$especies_gremios),
    paste(head(sp_sin_gremio, 10), collapse = ", ")
  ))
  if (length(sp_sin_gremio) > 10) {
    warning(sprintf("  ... y %d mas", length(sp_sin_gremio) - 10))
  }
}

# Validar que las categorias de refugio/alimentacion de las especies modelizables
# existen realmente en las tablas de gremios. Si no, assign_priorities_* fallaria
# en medio del bucle (fail-fast aqui para detectarlo antes).
sp_modelizables <- gremios$especies %>%
  filter(modelar == TRUE, especie %in% especies_en_datos)

cats_refugio_usadas <- unique(sp_modelizables$refugio[!is.na(sp_modelizables$refugio)])
cats_refugio_validas <- gremios$refugio$categoria
bad_ref <- setdiff(cats_refugio_usadas, cats_refugio_validas)
if (length(bad_ref) > 0) {
  sp_afectadas <- sp_modelizables$especie[sp_modelizables$refugio %in% bad_ref]
  stop(sprintf(
    "Categorias de refugio desconocidas: %s (especies: %s).\n  Validas: %s.\n  Corregir en '%s' o anadir en '%s'.",
    paste(bad_ref, collapse = ", "),
    paste(head(sp_afectadas, 5), collapse = ", "),
    paste(cats_refugio_validas, collapse = ", "),
    basename(CONFIG$paths$especies_gremios),
    basename(CONFIG$paths$gremios_refugio)
  ))
}

cats_alim_usadas <- unique(sp_modelizables$alimentacion[!is.na(sp_modelizables$alimentacion)])
cats_alim_validas <- gremios$alimentacion$categoria
bad_alim <- setdiff(cats_alim_usadas, cats_alim_validas)
if (length(bad_alim) > 0) {
  sp_afectadas <- sp_modelizables$especie[sp_modelizables$alimentacion %in% bad_alim]
  stop(sprintf(
    "Categorias de alimentacion desconocidas: %s (especies: %s).\n  Validas: %s.\n  Corregir en '%s' o anadir en '%s'.",
    paste(bad_alim, collapse = ", "),
    paste(head(sp_afectadas, 5), collapse = ", "),
    paste(cats_alim_validas, collapse = ", "),
    basename(CONFIG$paths$especies_gremios),
    basename(CONFIG$paths$gremios_alimentacion)
  ))
}

# Intersectar especies modelizables (modelar==TRUE en CSV) con las presentes en datos
especies <- intersect(obtener_especies_modelizables(gremios), especies_en_datos)
# Filtrar por lista piloto si se definio en CONFIG
if (!is.null(CONFIG$especies$piloto)) {
  especies <- intersect(especies, CONFIG$especies$piloto)
}
# Excluir especies explicitamente excluidas
especies <- setdiff(especies, CONFIG$especies$excluir)

cat(sprintf("Especies a procesar: %d\n\n", length(especies)))

# --- Identificar columnas de variables predictoras ---
# Excluimos columnas de respuesta (sp_), muestreo (m_), e identificadores
vars_excluir_pattern <- "^(sp_|m_|n_metodos|muestreado|factor_incert|CUADRICULA|ID_NORM)"
vars_pred <- names(datos_pa)[!str_detect(names(datos_pa), vars_excluir_pattern)]

# --- Ejecutar pipeline para cada especie ---
diagnostico <- tibble()

for (sp in especies) {
  sp_file <- str_replace_all(sp, " ", "_")
  json_file <- file.path(CONFIG$paths$variables_json, paste0(sp_file, ".json"))

  # Saltar si ya fue procesada (salvo force_rerun)
  if (file.exists(json_file) && !CONFIG$control$force_rerun) {
    cat(sprintf("\n=== %s === Ya procesado\n", sp))
    next
  }

  # Verificar que la columna de presencia/ausencia existe
  sp_col <- paste0("sp_", sp)
  if (!sp_col %in% names(datos_pa)) {
    cat(sprintf("\n=== %s === Columna no encontrada\n", sp))
    diagnostico <- bind_rows(diagnostico, tibble(
      Especie = sp, N_presencias = NA, N_variables = NA, Status = "NO_DATA"))
    next
  }

  # Preparar datos para esta especie: solo cuadriculas muestreadas,
  # con la columna de presencia/ausencia y todas las variables predictoras
  datos_sp <- datos_pa %>%
    filter(muestreado == 1) %>%
    select(presencia = all_of(sp_col), all_of(vars_pred)) %>%
    drop_na(presencia)

  # Ejecutar el pipeline de 7 fases
  resultado <- tryCatch(
    run_pipeline_especie(datos_sp, sp, gremios$especies, response_col = "presencia"),
    error = function(e) { cat(sprintf("  ERROR: %s\n", e$message)); NULL }
  )

  # Registrar resultado en tabla de diagnostico
  if (!is.null(resultado)) {
    diagnostico <- bind_rows(diagnostico, tibble(
      Especie = sp, N_presencias = resultado$metadata$n_presences,
      N_variables = length(resultado$metadata$variables_finales),
      AUC = ifelse(is.null(resultado$validation$AUC_mean), NA, resultado$validation$AUC_mean),
      Status = resultado$metadata$model_status))
  } else {
    diagnostico <- bind_rows(diagnostico, tibble(
      Especie = sp, N_presencias = NA, N_variables = NA, AUC = NA, Status = "ERROR"))
  }
}

# --- Guardar resumen de diagnostico ---
write_csv(diagnostico, file.path(CONFIG$output$seleccion, "diagnosticos", "resumen_seleccion.csv"))

# --- Imprimir resumen ---
cat("\n\n========================================\n")
cat("  RESUMEN SELECCION\n")
cat("========================================\n")
cat(sprintf("OK: %d  |  Error: %d  |  NoData: %d\n",
            sum(diagnostico$Status %in% c("modelo_completo", "modelo_simple")),
            sum(diagnostico$Status == "ERROR"),
            sum(diagnostico$Status == "NO_DATA")))
if (any(!is.na(diagnostico$AUC))) {
  cat(sprintf("AUC medio: %.3f\n", mean(diagnostico$AUC, na.rm = TRUE)))
}
cat("[OK] Fase 1 completada\n")
