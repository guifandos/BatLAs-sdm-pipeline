# ==============================================================================
# utils_logging.R - Sistema de logging centralizado
# ==============================================================================
# Registra eventos del pipeline en un archivo CSV estructurado.
# Cada linea contiene: timestamp, fase, especie, nivel, mensaje.
# Se inicializa al cargar y se usa en todas las fases.
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

if (!exists("CONFIG")) source("R/00_setup/00_config.R")

# --- Inicializar log ---
.pipeline_log_file <- NULL

init_log <- function(log_dir = NULL) {
  if (is.null(log_dir)) log_dir <- CONFIG$output$logs
  dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
  ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
  .pipeline_log_file <<- file.path(log_dir, paste0("pipeline_", ts, ".csv"))
  writeLines("timestamp,fase,especie,nivel,mensaje", .pipeline_log_file)
  invisible(.pipeline_log_file)
}

# --- Registrar entrada ---
log_event <- function(fase, especie = "", nivel = "INFO", mensaje = "") {
  if (is.null(.pipeline_log_file)) init_log()
  # Escapar comas en el mensaje
  mensaje_safe <- gsub(",", ";", as.character(mensaje))
  linea <- sprintf("%s,%s,%s,%s,%s",
                   format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                   fase, especie, nivel, mensaje_safe)
  cat(linea, "\n", file = .pipeline_log_file, append = TRUE)
  # Imprimir en consola si nivel >= CONFIG
  niveles <- c("DEBUG" = 0, "INFO" = 1, "WARN" = 2, "ERROR" = 3)
  nivel_config <- niveles[CONFIG$logging$nivel]
  if (is.na(nivel_config)) nivel_config <- 1
  if (niveles[nivel] >= nivel_config && isTRUE(CONFIG$logging$consola)) {
    prefix <- switch(nivel, WARN = "  [WARN] ", ERROR = "  [ERROR] ", "  ")
    cat(sprintf("%s%s\n", prefix, mensaje))
  }
}

# --- Leer log como tibble ---
read_log <- function(log_file = NULL) {
  if (is.null(log_file)) log_file <- .pipeline_log_file
  if (is.null(log_file) || !file.exists(log_file)) return(tibble())
  readr::read_csv(log_file, show_col_types = FALSE)
}

# --- Resumen de errores/warnings ---
log_summary <- function(log_file = NULL) {
  log_df <- read_log(log_file)
  if (nrow(log_df) == 0) {
    cat("Log vacio\n")
    return(invisible(NULL))
  }
  n_error <- sum(log_df$nivel == "ERROR", na.rm = TRUE)
  n_warn <- sum(log_df$nivel == "WARN", na.rm = TRUE)
  n_info <- sum(log_df$nivel == "INFO", na.rm = TRUE)
  cat(sprintf("Log: %d entradas (INFO=%d, WARN=%d, ERROR=%d)\n",
              nrow(log_df), n_info, n_warn, n_error))
  if (n_error > 0) {
    cat("\nERRORES:\n")
    errores <- log_df %>% dplyr::filter(nivel == "ERROR")
    for (i in seq_len(nrow(errores))) {
      cat(sprintf("  [%s] %s - %s: %s\n",
                  errores$timestamp[i], errores$fase[i],
                  errores$especie[i], errores$mensaje[i]))
    }
  }
  invisible(log_df)
}

message("[OK] Sistema de logging cargado")
