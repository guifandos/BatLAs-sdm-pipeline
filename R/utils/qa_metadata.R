# ==============================================================================
# qa_metadata.R - Chequeo de calidad de metadatos ecologicos
# ==============================================================================
#
# Script ejecutable de forma independiente que genera un informe de QA
# de los CSVs de metadatos (especies_gremios, gremios_refugio,
# gremios_alimentacion, complejos_taxonomicos, diccionario_variables).
#
# USO:
#   source("R/utils/qa_metadata.R")
#   # Genera informe en output/checks/qa_metadata.txt
#
# Comprueba:
#   1. Cobertura de categorias (todas usadas, ninguna huerfana)
#   2. Variables de gremio presentes en diccionario
#   3. Variables de gremio presentes en datos reales (si PAxENV existe)
#   4. Especies modelizables con gremios completos
#   5. Complejos taxonomicos coherentes
#   6. Estadisticas descriptivas (n especies por gremio, etc.)
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

if (!exists("CONFIG")) source("R/00_setup/00_config.R")

suppressPackageStartupMessages(library(tidyverse))

qa_metadata <- function(save_report = TRUE) {

  cat("\n========================================\n")
  cat("  QA METADATOS ECOLOGICOS\n")
  cat("========================================\n\n")

  report <- c()
  n_errores <- 0
  n_avisos  <- 0

  add <- function(msg, tipo = "INFO") {
    tag <- switch(tipo, ERROR = "[ERROR]", WARN = "[AVISO]", OK = "[OK]", "[ ]")
    line <- sprintf("  %s %s", tag, msg)
    report <<- c(report, line)
    cat(line, "\n")
    if (tipo == "ERROR") n_errores <<- n_errores + 1
    if (tipo == "WARN") n_avisos <<- n_avisos + 1
  }

  # --- Cargar CSVs ---
  esp  <- read_csv(CONFIG$paths$especies_gremios, show_col_types = FALSE)
  ref  <- read_csv(CONFIG$paths$gremios_refugio, show_col_types = FALSE) %>%
    mutate(vars = str_split(variables_prioritarias, ",\\s*"))
  alim <- read_csv(CONFIG$paths$gremios_alimentacion, show_col_types = FALSE) %>%
    mutate(vars = str_split(variables_prioritarias, ",\\s*"))
  dict <- read_csv(CONFIG$paths$diccionario_variables, show_col_types = FALSE)

  # ============================================================================
  # 1. ESTADISTICAS DESCRIPTIVAS
  # ============================================================================
  add(sprintf("Total especies: %d", nrow(esp)))
  add(sprintf("Modelizables (modelar=TRUE): %d", sum(esp$modelar == TRUE)))
  add(sprintf("Excluidas (modelar=FALSE): %d", sum(esp$modelar == FALSE)))

  report <- c(report, "")
  add("--- Distribucion por refugio ---")
  tab_ref <- table(esp$refugio[esp$modelar == TRUE])
  for (nm in names(tab_ref)) {
    add(sprintf("  %-15s %d especies", nm, tab_ref[nm]))
  }

  report <- c(report, "")
  add("--- Distribucion por alimentacion ---")
  tab_alim <- table(esp$alimentacion[esp$modelar == TRUE])
  for (nm in names(tab_alim)) {
    add(sprintf("  %-15s %d especies", nm, tab_alim[nm]))
  }

  # ============================================================================
  # 2. CATEGORIAS HUERFANAS
  # ============================================================================
  report <- c(report, "", "--- Categorias huerfanas ---")

  cats_ref_def <- ref$categoria
  cats_ref_usadas <- unique(esp$refugio[!is.na(esp$refugio)])
  huerfanas_ref <- setdiff(cats_ref_def, cats_ref_usadas)
  if (length(huerfanas_ref) > 0) {
    add(sprintf("Categorias de refugio definidas pero NO usadas por ninguna especie: %s",
                paste(huerfanas_ref, collapse = ", ")), "WARN")
  } else {
    add("Todas las categorias de refugio estan en uso", "OK")
  }

  cats_alim_def <- alim$categoria
  cats_alim_usadas <- unique(esp$alimentacion[!is.na(esp$alimentacion)])
  huerfanas_alim <- setdiff(cats_alim_def, cats_alim_usadas)
  if (length(huerfanas_alim) > 0) {
    add(sprintf("Categorias de alimentacion definidas pero NO usadas: %s",
                paste(huerfanas_alim, collapse = ", ")), "WARN")
  } else {
    add("Todas las categorias de alimentacion estan en uso", "OK")
  }

  # ============================================================================
  # 3. VARIABLES DE GREMIO vs DICCIONARIO
  # ============================================================================
  report <- c(report, "", "--- Variables de gremio vs diccionario ---")

  vars_gremio <- unique(c(unlist(ref$vars), unlist(alim$vars)))
  vars_dict   <- dict$variable

  no_en_dict <- setdiff(vars_gremio, vars_dict)
  if (length(no_en_dict) > 0) {
    add(sprintf("Variables en gremios NO en diccionario_variables.csv: %s",
                paste(no_en_dict, collapse = ", ")), "WARN")
  } else {
    add("Todas las variables de gremio figuran en el diccionario", "OK")
  }

  # ============================================================================
  # 4. VARIABLES DE GREMIO vs DATOS REALES (si PAxENV existe)
  # ============================================================================
  report <- c(report, "", "--- Variables de gremio vs datos reales ---")

  if (file.exists(CONFIG$paths$pa_data)) {
    datos_pa <- readRDS(CONFIG$paths$pa_data)
    vars_en_datos <- names(datos_pa)
    no_en_datos <- setdiff(vars_gremio, vars_en_datos)
    if (length(no_en_datos) > 0) {
      add(sprintf("Variables en gremios que NO existen en PAxENV: %s",
                  paste(no_en_datos, collapse = ", ")), "WARN")
    } else {
      add("Todas las variables de gremio existen en PAxENV", "OK")
    }
  } else {
    add("PAxENV no encontrado, no se comprueba existencia de variables en datos", "INFO")
  }

  # ============================================================================
  # 5. COMPLEJOS TAXONOMICOS
  # ============================================================================
  report <- c(report, "", "--- Complejos taxonomicos ---")

  if (file.exists(CONFIG$paths$complejos_taxonomicos)) {
    comp <- read_csv(CONFIG$paths$complejos_taxonomicos, show_col_types = FALSE)
    add(sprintf("Complejos definidos: %d", nrow(comp)))

    for (i in seq_len(nrow(comp))) {
      spp <- trimws(str_split(comp$especies_incluidas[i], ",\\s*")[[1]])
      missing <- setdiff(spp, esp$especie)
      if (length(missing) > 0) {
        add(sprintf("Complejo '%s': especies no en lista principal: %s",
                    comp$complejo[i], paste(missing, collapse = ", ")), "ERROR")
      }
      # Verificar n_especies
      if ("n_especies" %in% names(comp) && !is.na(comp$n_especies[i])) {
        if (length(spp) != comp$n_especies[i]) {
          add(sprintf("Complejo '%s': n_especies=%d pero %d listadas",
                      comp$complejo[i], comp$n_especies[i], length(spp)), "WARN")
        }
      }
    }
  } else {
    add("No se encontro complejos_taxonomicos.csv", "INFO")
  }

  # ============================================================================
  # 6. ESPECIES MODELIZABLES SIN GREMIO COMPLETO
  # ============================================================================
  report <- c(report, "", "--- Especies modelizables sin gremio completo ---")

  modelables <- esp %>% filter(modelar == TRUE)
  sin_ref  <- modelables$especie[is.na(modelables$refugio) | modelables$refugio == ""]
  sin_alim <- modelables$especie[is.na(modelables$alimentacion) | modelables$alimentacion == ""]

  if (length(sin_ref) > 0) {
    add(sprintf("Sin refugio: %s", paste(sin_ref, collapse = ", ")), "ERROR")
  }
  if (length(sin_alim) > 0) {
    add(sprintf("Sin alimentacion: %s", paste(sin_alim, collapse = ", ")), "ERROR")
  }
  if (length(sin_ref) == 0 && length(sin_alim) == 0) {
    add("Todas las especies modelizables tienen refugio y alimentacion asignados", "OK")
  }

  # ============================================================================
  # RESUMEN
  # ============================================================================
  report <- c(report, "")
  resumen <- sprintf("RESUMEN QA: %d errores, %d avisos", n_errores, n_avisos)
  report <- c(report, resumen)
  cat("\n", resumen, "\n")

  # --- Guardar informe ---
  if (save_report) {
    dir.create(CONFIG$output$checks, recursive = TRUE, showWarnings = FALSE)
    out_file <- file.path(CONFIG$output$checks, "qa_metadata.txt")
    writeLines(report, out_file)
    cat(sprintf("[OK] Informe guardado en %s\n", out_file))
  }

  invisible(list(errores = n_errores, avisos = n_avisos, report = report))
}

# Si se ejecuta directamente (no source'd desde otro script),
# lanzar el QA automaticamente
if (sys.nframe() == 0 || identical(environment(), globalenv())) {
  qa_metadata()
}
