# ==============================================================================
# utils_checkpoints.R - Sistema de checkpoints para el pipeline
# ==============================================================================

suppressPackageStartupMessages(library(tidyverse))

norm_id <- function(x) {
  if (is.null(x) || length(x) == 0) return(character(0))
  x %>%
    as.character() %>%
    str_trim() %>%
    str_squish() %>%
    toupper() %>%
    str_replace_all("\\s+", "")
}

normalizar_id_tabla <- function(df) {
  if (inherits(df, "sf")) {
    require(sf)
    df <- st_drop_geometry(df)
  }
  candidatos <- c("CUADRICULA", "cuadricula", "UTM_10x10KM", "ID")
  col_id <- NULL
  for (cand in candidatos) {
    if (cand %in% names(df)) {
      col_id <- cand
      break
    }
  }
  if (is.null(col_id)) {
    stop("No se encontro columna de ID. Debe llamarse: CUADRICULA, cuadricula, UTM_10x10KM o ID")
  }
  df$ID_NORM <- norm_id(df[[col_id]])
  attr(df, "col_id_original") <- col_id
  return(df)
}

#' Standardize IDs in a character vector (for sf objects)
std_ids <- function(x) {
  x %>%
    as.character() %>%
    str_trim() %>%
    str_squish() %>%
    toupper() %>%
    str_replace_all("\\s+", "")
}

#' Standardize the ID column of a table/sf to uppercase no-spaces
#' Detects the first matching column among candidatos, normalizes values,
#' and RENAMES the column to the canonical name (default: CUADRICULA).
#' This ensures all tables use the same column name for joins.
#'
#' @param tbl Data frame or sf object
#' @param col Optional: explicit column name to normalize. If NULL, auto-detects.
#' @param canonical Target column name after rename (default "CUADRICULA")
#' @return Table with normalized and renamed ID column
std_ids_tbl <- function(tbl, col = NULL, canonical = "CUADRICULA") {
  if (is.null(col)) {
    candidatos <- c("CUADRICULA", "cuadricula", "cuadricula_utm_10x10",
                     "UTM_10x10KM", "ID", "UTMCODE", "UTM_CODE", "utm_code",
                     "QUADRICULA", "CELLCODE", "CODE", "UTM10X10", "UTM10", "id")
    col <- NULL
    for (cand in candidatos) {
      if (cand %in% names(tbl)) { col <- cand; break }
    }
    if (is.null(col)) {
      stop(paste0("No ID column found.\n",
                   "  Candidates: ", paste(candidatos, collapse = ", "), "\n",
                   "  Available: ", paste(names(tbl), collapse = ", ")))
    }
  } else {
    # Verify explicitly provided column exists
    if (!col %in% names(tbl)) {
      # Try auto-detection as fallback
      candidatos <- c("CUADRICULA", "cuadricula", "cuadricula_utm_10x10",
                       "UTM_10x10KM", "ID", "UTMCODE", "UTM_CODE", "utm_code",
                       "QUADRICULA", "CELLCODE", "CODE", "UTM10X10", "UTM10", "id")
      col_found <- NULL
      for (cand in candidatos) {
        if (cand %in% names(tbl)) { col_found <- cand; break }
      }
      if (!is.null(col_found)) {
        warning(sprintf("Columna '%s' no encontrada, usando '%s' detectada automaticamente.",
                        col, col_found))
        col <- col_found
      } else {
        stop(sprintf("Columna '%s' no encontrada en tabla.\n  Disponibles: %s",
                     col, paste(names(tbl), collapse = ", ")))
      }
    }
  }
  # Normalize values: uppercase, trim, remove whitespace
  tbl[[col]] <- std_ids(tbl[[col]])
  # Rename to canonical name if different
  if (col != canonical) {
    tbl[[canonical]] <- tbl[[col]]
    tbl[[col]] <- NULL
  }
  return(tbl)
}

#' Validate that a table has the expected minimum number of rows (cuadriculas).
#' Meant for the Iberian Peninsula + Baleares malla (~5500+ cells).
#' Use after every join/filter that could lose rows.
#'
#' @param tbl Data frame or sf object
#' @param min_rows Minimum expected rows (default 5000)
#' @param context Description for error message (e.g. "after EC+GEO join")
validar_n_cuadriculas <- function(tbl, min_rows = 5000, context = "") {
  nr <- nrow(tbl)
  if (nr < min_rows) {
    stop(sprintf(
      "VALIDACION FALLIDA %s: %d filas (minimo esperado: %d). Posible perdida de datos en join o filtrado.",
      context, nr, min_rows
    ))
  }
  invisible(tbl)
}

checkpoint_exists <- function(especie, dir_base, fase) {
  sp_file <- str_replace_all(especie, " ", "_")
  checkpoint_path <- file.path(dir_base, sp_file, fase,
                                sprintf("checkpoint_%s.txt", fase))
  return(file.exists(checkpoint_path))
}

create_checkpoint <- function(especie, dir_base, fase, metadata = NULL) {
  sp_file <- str_replace_all(especie, " ", "_")
  dir_fase <- file.path(dir_base, sp_file, fase)
  dir.create(dir_fase, recursive = TRUE, showWarnings = FALSE)
  checkpoint_path <- file.path(dir_fase, sprintf("checkpoint_%s.txt", fase))
  contenido <- c(
    sprintf("Especie: %s", especie),
    sprintf("Fase: %s", fase),
    sprintf("Fecha: %s", Sys.time()),
    ""
  )
  if (!is.null(metadata)) {
    contenido <- c(contenido, "Metadata:")
    for (key in names(metadata)) {
      contenido <- c(contenido, sprintf("  %s: %s", key, metadata[[key]]))
    }
  }
  writeLines(contenido, checkpoint_path)
  invisible(checkpoint_path)
}

remove_checkpoint <- function(especie, dir_base, fase) {
  sp_file <- str_replace_all(especie, " ", "_")
  checkpoint_path <- file.path(dir_base, sp_file, fase,
                                sprintf("checkpoint_%s.txt", fase))
  if (file.exists(checkpoint_path)) file.remove(checkpoint_path)
}

get_especies_pendientes <- function(especies_todas, dir_base, fase) {
  pendientes <- c()
  for (sp in especies_todas) {
    if (!checkpoint_exists(sp, dir_base, fase)) {
      pendientes <- c(pendientes, sp)
    }
  }
  return(pendientes)
}

crear_estructura_especie <- function(especie, dir_base,
                                      fases = c("ambiental", "espacial",
                                                "interseccion", "validacion",
                                                "incertidumbre", "mapas")) {
  sp_file <- str_replace_all(especie, " ", "_")
  for (fase in fases) {
    dir_fase <- file.path(dir_base, sp_file, fase)
    dir.create(dir_fase, recursive = TRUE, showWarnings = FALSE)
  }
  invisible(file.path(dir_base, sp_file))
}

print_progress <- function(i, n, msg = "") {
  pct <- round(100 * i / n)
  bar_len <- 40
  filled <- round(bar_len * i / n)
  bar <- paste0(rep("#", filled), rep(".", bar_len - filled), collapse = "")
  cat(sprintf("\r[%s] %d%% (%d/%d) %s", bar, pct, i, n, msg))
  if (i == n) cat("\n")
}

format_tiempo <- function(segundos) {
  h <- floor(segundos / 3600)
  m <- floor((segundos %% 3600) / 60)
  s <- round(segundos %% 60)
  if (h > 0) return(sprintf("%dh %dm %ds", h, m, s))
  if (m > 0) return(sprintf("%dm %ds", m, s))
  return(sprintf("%ds", s))
}

message("[OK] Funciones checkpoint cargadas")
