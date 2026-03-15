# ==============================================================================
# preprocesar_output_shiny.R - Genera datos pregenerados para Shiny app
# ==============================================================================
#
# Crea output_shiny/ con toda la informacion necesaria para la app Shiny
# del Atlas de Distribucion de Murcielagos Ibericos (SECEMU).
# La app NO recalcula nada — solo lee estos datos pregenerados.
#
# USO: source("preprocesar_output_shiny.R")
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

if (!exists("CONFIG")) source("R/00_setup/00_config.R")

suppressPackageStartupMessages({
  library(tidyverse)
  library(sf)
  library(jsonlite)
})

cat("\n")
cat("================================================================\n")
cat("  PREPROCESAMIENTO PARA SHINY APP\n")
cat("================================================================\n\n")

t_inicio <- Sys.time()

# ==============================================================================
# CONFIGURACION
# ==============================================================================

DIR_MODELOS  <- CONFIG$output$base           # output/modelos
DIR_JSON     <- CONFIG$paths$variables_json   # output/seleccion_variables/variables_json
DIR_OUT      <- "output_shiny"
N_PUNTOS_CURVA <- 100  # puntos por curva de respuesta

# Crear estructura de carpetas
for (d in c(DIR_OUT,
            file.path(DIR_OUT, "mapas_sf"),
            file.path(DIR_OUT, "variables_coefs"),
            file.path(DIR_OUT, "curvas_respuesta"),
            file.path(DIR_OUT, "metricas_validacion"),
            file.path(DIR_OUT, "mapas_png"))) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

# ==============================================================================
# FUNCIONES AUXILIARES
# ==============================================================================

norm_id <- function(x) {
  x <- trimws(as.character(x))
  x <- gsub("\\s+", "", x)
  toupper(x)
}

favorabilidad <- function(prob, y) {
  n1 <- sum(y == 1, na.rm = TRUE)
  n0 <- sum(y == 0, na.rm = TRUE)
  odds_prob <- prob / (1 - prob)
  odds_prev <- n1 / n0
  odds_prob / (odds_prob + odds_prev)
}

# ==============================================================================
# CARGAR DATOS BASE (una sola vez)
# ==============================================================================

cat("Cargando datos base...\n")

# Grid espacial con geometria
grid_sf <- readRDS(CONFIG$paths$predictores_seo_geo_sf)
grid_sf$CUAD_NORM <- norm_id(grid_sf$CUADRICULA)
cat(sprintf("  Grid sf: %d celdas, CRS: %s\n", nrow(grid_sf), st_crs(grid_sf)$input))

# PAxENV — para obtener CUADRICULA alineada con predicciones
paxenv <- readRDS(CONFIG$paths$pa_data)
paxenv$CUAD_NORM <- norm_id(paxenv$CUADRICULA)
cat(sprintf("  PAxENV: %d filas, %d columnas\n", nrow(paxenv), ncol(paxenv)))

# Gremios
gremios <- read_csv(CONFIG$paths$especies_gremios, show_col_types = FALSE)

# Especies con carpeta
dirs_sp <- list.dirs(DIR_MODELOS, recursive = FALSE, full.names = FALSE)
especies_all <- str_replace_all(dirs_sp, "_", " ")
cat(sprintf("  Especies con carpeta: %d\n", length(especies_all)))

# ==============================================================================
# LOG
# ==============================================================================

log_lines <- c(
  sprintf("=== Preprocesamiento Shiny — %s ===", Sys.time()),
  sprintf("Especies totales: %d", length(especies_all)),
  ""
)
log_ok <- character()
log_skip <- character()
log_warn <- character()

# ==============================================================================
# A) TABLA MAESTRA DE ESPECIES (metadatos_especies.rds)
# ==============================================================================

cat("\n--- A) Tabla maestra de especies ---\n")

metadatos <- map_dfr(especies_all, function(sp) {
  sp_file <- str_replace_all(sp, " ", "_")
  dir_sp <- file.path(DIR_MODELOS, sp_file)
  json_file <- file.path(DIR_JSON, paste0(sp_file, ".json"))

  # Datos base
  row <- tibble(
    especie = sp,
    especie_file = sp_file,
    modelizable = file.exists(file.path(dir_sp, "ambiental", "modelo_glm.rds"))
  )

  # JSON
  if (file.exists(json_file)) {
    j <- tryCatch(fromJSON(json_file), error = function(e) NULL)
    if (!is.null(j)) {
      row$gremio_refugio <- j$gremio_refugio %||% NA_character_
      row$gremio_alimentacion <- j$gremio_alimentacion %||% NA_character_
      row$n_presencias <- j$n_presences %||% NA_integer_
      row$n_variables <- if (!is.null(j$variables_finales)) nrow(j$variables_finales) else NA_integer_
    }
  }

  # Gremios (fallback desde CSV)
  if (is.na(row$gremio_refugio %||% NA)) {
    match_g <- gremios |> filter(especie == sp)
    if (nrow(match_g) > 0) {
      row$gremio_refugio <- match_g$refugio[1]
      row$gremio_alimentacion <- match_g$alimentacion[1]
    }
  }

  # Metricas CV
  resumen_file <- file.path(dir_sp, "validacion", "resumen_cv.csv")
  if (file.exists(resumen_file)) {
    res <- tryCatch(read_csv(resumen_file, show_col_types = FALSE), error = function(e) NULL)
    if (!is.null(res) && nrow(res) > 0) {
      row$AUC_cv <- res$AUC_mean[1]
      row$AUC_cv_sd <- res$AUC_sd[1]
      row$TSS_cv <- res$TSS_mean[1]
      row$TSS_cv_sd <- res$TSS_sd[1]
    }
  }

  # Metricas holdout
  holdout_file <- file.path(dir_sp, "ambiental", "metricas_holdout.csv")
  if (file.exists(holdout_file)) {
    ho <- tryCatch(read_csv(holdout_file, show_col_types = FALSE), error = function(e) NULL)
    if (!is.null(ho) && nrow(ho) > 0) {
      row$AUC_holdout <- ho$AUC[1]
      row$TSS_holdout <- ho$TSS[1]
      row$Sens_holdout <- ho$Sens[1]
      row$Spec_holdout <- ho$Spec[1]
    }
  }

  # PNGs disponibles
  mapas_dir <- file.path(dir_sp, "mapas")
  if (dir.exists(mapas_dir)) {
    pngs <- list.files(mapas_dir, pattern = "\\.png$")
    row$pngs_disponibles <- paste(pngs, collapse = ";")
  }

  row
})

saveRDS(metadatos, file.path(DIR_OUT, "metadatos_especies.rds"))
cat(sprintf("  Tabla maestra: %d especies (%d modelizables)\n",
            nrow(metadatos), sum(metadatos$modelizable)))

# ==============================================================================
# PROCESAR CADA ESPECIE MODELIZABLE
# ==============================================================================

especies_modelo <- metadatos |> filter(modelizable == TRUE)

for (idx in seq_len(nrow(especies_modelo))) {
  sp <- especies_modelo$especie[idx]
  sp_file <- especies_modelo$especie_file[idx]
  dir_sp <- file.path(DIR_MODELOS, sp_file)

  cat(sprintf("\n[%d/%d] %s\n", idx, nrow(especies_modelo), sp))

  tryCatch({

    # ========================================================================
    # B) MAPA SF (mapas_sf/{Especie}_mapa.rds)
    # ========================================================================

    # Predicciones: estan en orden de fila alineado con PAxENV
    pred_inter <- tryCatch(
      read_csv(file.path(dir_sp, "interseccion", "predicciones.csv"), show_col_types = FALSE),
      error = function(e) NULL
    )
    pred_amb <- tryCatch(
      read_csv(file.path(dir_sp, "ambiental", "predicciones.csv"), show_col_types = FALSE),
      error = function(e) NULL
    )
    pred_esp <- tryCatch(
      read_csv(file.path(dir_sp, "espacial", "predicciones.csv"), show_col_types = FALSE),
      error = function(e) NULL
    )
    incert <- tryCatch(
      read_csv(file.path(dir_sp, "incertidumbre", "incertidumbre.csv"), show_col_types = FALSE),
      error = function(e) NULL
    )

    if (!is.null(pred_inter) && nrow(pred_inter) == nrow(paxenv)) {
      # Construir tabla con CUADRICULA
      mapa_data <- tibble(CUAD_NORM = paxenv$CUAD_NORM)

      if (!is.null(pred_inter)) {
        mapa_data$F_final <- pred_inter$F_final_mean
        mapa_data$F_final_sd <- pred_inter$F_final_sd
        mapa_data$W_fuzzy <- pred_inter$W_fuzzy
      }
      if (!is.null(pred_amb)) {
        mapa_data$F_amb <- pred_amb$F_glm_mean
        mapa_data$F_amb_sd <- pred_amb$F_glm_sd
      }
      if (!is.null(pred_esp)) {
        mapa_data$F_esp <- pred_esp$F_esp_mean
        mapa_data$F_esp_sd <- pred_esp$F_esp_sd
      }
      if (!is.null(incert)) {
        mapa_data$U_final <- incert$U_final
        mapa_data$MESS <- incert$MESS
        mapa_data$W_bootstrap <- incert$W_bootstrap
      }

      # Join con grid sf
      mapa_sf <- grid_sf |>
        select(CUAD_NORM, CUADRICULA, geometry) |>
        inner_join(mapa_data, by = "CUAD_NORM")

      # Transformar a WGS84 para leaflet
      mapa_sf <- st_transform(mapa_sf, 4326)

      saveRDS(mapa_sf, file.path(DIR_OUT, "mapas_sf", paste0(sp_file, "_mapa.rds")))
      cat(sprintf("  [B] Mapa sf: %d celdas\n", nrow(mapa_sf)))

      if (nrow(mapa_sf) < nrow(mapa_data) * 0.95) {
        warn_msg <- sprintf("  [WARN] %s: join perdio %d celdas (%d -> %d)",
                            sp, nrow(mapa_data) - nrow(mapa_sf), nrow(mapa_data), nrow(mapa_sf))
        log_warn <- c(log_warn, warn_msg)
        cat(warn_msg, "\n")
      }
    } else {
      cat("  [B] SKIP mapa sf — predicciones no alineadas con PAxENV\n")
      log_warn <- c(log_warn, sprintf("%s: predicciones no alineadas con PAxENV", sp))
    }

    # ========================================================================
    # C) VARIABLES Y COEFICIENTES (variables_coefs/{Especie}_vars.rds)
    # ========================================================================

    json_file <- file.path(DIR_JSON, paste0(sp_file, ".json"))
    coef_file <- file.path(dir_sp, "ambiental", "coeficientes_glm.csv")

    if (file.exists(json_file) && file.exists(coef_file)) {
      j <- fromJSON(json_file)
      coefs <- read_csv(coef_file, show_col_types = FALSE)

      vars_df <- j$variables_finales
      if (!is.null(vars_df) && is.data.frame(vars_df)) {
        # Join con coeficientes
        coefs_clean <- coefs |>
          filter(Variable != "(Intercept)") |>
          rename(name = Variable)

        vars_coefs <- vars_df |>
          left_join(coefs_clean, by = "name") |>
          mutate(
            significativo = !is.na(p) & p < 0.05,
            direccion = case_when(
              is.na(estimate) ~ NA_character_,
              estimate > 0 ~ "positivo",
              estimate < 0 ~ "negativo",
              TRUE ~ "neutro"
            )
          )

        saveRDS(vars_coefs, file.path(DIR_OUT, "variables_coefs", paste0(sp_file, "_vars.rds")))
        cat(sprintf("  [C] Variables: %d (%d significativas)\n",
                    nrow(vars_coefs), sum(vars_coefs$significativo, na.rm = TRUE)))
      }
    }

    # ========================================================================
    # D) CURVAS DE RESPUESTA (curvas_respuesta/{Especie}_curvas.rds)
    # ========================================================================

    modelo_file <- file.path(dir_sp, "ambiental", "modelo_glm.rds")
    datos_file <- file.path(dir_sp, "ambiental", "datos_entrenamiento.rds")

    if (file.exists(modelo_file) && file.exists(datos_file)) {
      modelo <- readRDS(modelo_file)
      datos_list <- readRDS(datos_file)

      if (is.list(datos_list) && "datos" %in% names(datos_list)) {
        datos <- datos_list$datos
      } else {
        datos <- datos_list
      }

      # Variables del modelo
      vars_mod <- all.vars(formula(modelo))
      vars_mod <- vars_mod[vars_mod != "PA"]
      vars_mod <- intersect(vars_mod, names(datos))

      y <- as.numeric(datos$PA)

      curvas_all <- map_dfr(vars_mod, function(var) {
        tryCatch({
          var_vals <- datos[[var]]
          # Percentiles 5-95 para evitar extremos
          q05 <- quantile(var_vals, 0.05, na.rm = TRUE)
          q95 <- quantile(var_vals, 0.95, na.rm = TRUE)
          if (q05 == q95) return(NULL)

          var_seq <- seq(q05, q95, length.out = N_PUNTOS_CURVA)

          # Medianas para todas las variables
          base_data <- datos |>
            select(all_of(vars_mod)) |>
            summarise(across(everything(), \(x) median(x, na.rm = TRUE))) |>
            slice(rep(1, N_PUNTOS_CURVA))
          base_data[[var]] <- var_seq

          # Predecir
          prob <- predict(modelo, newdata = base_data, type = "response")
          fav <- favorabilidad(prob, y)

          tibble(
            variable = var,
            x = var_seq,
            probabilidad = prob,
            favorabilidad = fav
          )
        }, error = function(e) NULL)
      })

      if (nrow(curvas_all) > 0) {
        saveRDS(curvas_all, file.path(DIR_OUT, "curvas_respuesta", paste0(sp_file, "_curvas.rds")))
        n_vars_curva <- n_distinct(curvas_all$variable)
        cat(sprintf("  [D] Curvas respuesta: %d variables\n", n_vars_curva))
      }
    }

    # ========================================================================
    # E) METRICAS DE VALIDACION (metricas_validacion/{Especie}_metricas.rds)
    # ========================================================================

    metricas_out <- list()

    # CV
    cv_file <- file.path(dir_sp, "validacion", "metricas_cv.csv")
    if (file.exists(cv_file)) {
      metricas_out$cv <- read_csv(cv_file, show_col_types = FALSE)
    }
    resumen_file <- file.path(dir_sp, "validacion", "resumen_cv.csv")
    if (file.exists(resumen_file)) {
      metricas_out$resumen_cv <- read_csv(resumen_file, show_col_types = FALSE)
    }

    # Holdout
    holdout_file <- file.path(dir_sp, "ambiental", "metricas_holdout.csv")
    if (file.exists(holdout_file)) {
      metricas_out$holdout <- read_csv(holdout_file, show_col_types = FALSE)
    }

    if (length(metricas_out) > 0) {
      saveRDS(metricas_out, file.path(DIR_OUT, "metricas_validacion", paste0(sp_file, "_metricas.rds")))
      cat("  [E] Metricas validacion: OK\n")
    }

    # ========================================================================
    # F) COPIAR PNGs (mapas_png/{Especie}/)
    # ========================================================================

    mapas_src <- file.path(dir_sp, "mapas")
    if (dir.exists(mapas_src)) {
      pngs <- list.files(mapas_src, pattern = "\\.png$", full.names = TRUE)
      if (length(pngs) > 0) {
        mapas_dst <- file.path(DIR_OUT, "mapas_png", sp_file)
        dir.create(mapas_dst, recursive = TRUE, showWarnings = FALSE)

        # Nombres estandarizados
        nombre_map <- c(
          "mapa_F_final.png"        = "favorabilidad.png",
          "mapa_F_amb.png"          = "favorabilidad_ambiental.png",
          "mapa_bivariado.png"      = "bivariado.png",
          "mapa_U_final.png"        = "incertidumbre.png",
          "panel_incertidumbre.png" = "panel_incertidumbre.png",
          "panel_SECEMU.png"        = "panel_SECEMU.png"
        )

        n_copied <- 0
        for (png in pngs) {
          bn <- basename(png)
          dst_name <- nombre_map[bn]
          if (is.na(dst_name)) dst_name <- bn  # mantener nombre original si no esta mapeado
          file.copy(png, file.path(mapas_dst, dst_name), overwrite = TRUE)
          n_copied <- n_copied + 1
        }
        cat(sprintf("  [F] PNGs copiados: %d\n", n_copied))
      }
    }

    # Copiar tambien response_curves.png
    rc_file <- file.path(dir_sp, "ambiental", "response_curves.png")
    if (file.exists(rc_file)) {
      mapas_dst <- file.path(DIR_OUT, "mapas_png", sp_file)
      dir.create(mapas_dst, recursive = TRUE, showWarnings = FALSE)
      file.copy(rc_file, file.path(mapas_dst, "curvas_respuesta.png"), overwrite = TRUE)
    }

    log_ok <- c(log_ok, sp)

  }, error = function(e) {
    msg <- sprintf("  [ERROR] %s: %s", sp, e$message)
    cat(msg, "\n")
    log_skip <<- c(log_skip, sprintf("%s: %s", sp, e$message))
  })
}

# ==============================================================================
# G) INDICE DE PNGs POR ESPECIE
# ==============================================================================

cat("\n--- Generando indice de PNGs ---\n")

indice_pngs <- map_dfr(especies_modelo$especie_file, function(sp_file) {
  png_dir <- file.path(DIR_OUT, "mapas_png", sp_file)
  if (!dir.exists(png_dir)) return(NULL)
  pngs <- list.files(png_dir, pattern = "\\.png$")
  if (length(pngs) == 0) return(NULL)
  tibble(especie_file = sp_file, png = pngs)
})

saveRDS(indice_pngs, file.path(DIR_OUT, "indice_pngs.rds"))
cat(sprintf("  Indice: %d PNGs para %d especies\n",
            nrow(indice_pngs), n_distinct(indice_pngs$especie_file)))

# ==============================================================================
# H) LOG DE EJECUCION
# ==============================================================================

t_total <- difftime(Sys.time(), t_inicio, units = "mins")

log_lines <- c(log_lines,
  sprintf("Especies procesadas con exito: %d", length(log_ok)),
  paste("  ", log_ok),
  "",
  sprintf("Especies con error: %d", length(log_skip)),
  if (length(log_skip) > 0) paste("  ", log_skip) else "  (ninguna)",
  "",
  sprintf("Advertencias: %d", length(log_warn)),
  if (length(log_warn) > 0) paste("  ", log_warn) else "  (ninguna)",
  "",
  sprintf("Tiempo total: %.1f min", as.numeric(t_total)),
  sprintf("Fecha: %s", Sys.time()),
  "",
  "=== Archivos generados ===",
  sprintf("  metadatos_especies.rds: %d especies", nrow(metadatos)),
  sprintf("  mapas_sf/: %d archivos", length(list.files(file.path(DIR_OUT, "mapas_sf")))),
  sprintf("  variables_coefs/: %d archivos", length(list.files(file.path(DIR_OUT, "variables_coefs")))),
  sprintf("  curvas_respuesta/: %d archivos", length(list.files(file.path(DIR_OUT, "curvas_respuesta")))),
  sprintf("  metricas_validacion/: %d archivos", length(list.files(file.path(DIR_OUT, "metricas_validacion")))),
  sprintf("  mapas_png/: %d carpetas", length(list.dirs(file.path(DIR_OUT, "mapas_png"), recursive = FALSE))),
  sprintf("  indice_pngs.rds: %d entradas", nrow(indice_pngs))
)

writeLines(log_lines, file.path(DIR_OUT, "log_preprocesamiento.txt"))

cat("\n")
cat("================================================================\n")
cat("  PREPROCESAMIENTO COMPLETADO\n")
cat("================================================================\n")
cat(sprintf("  Especies OK: %d / %d\n", length(log_ok), nrow(especies_modelo)))
cat(sprintf("  Errores: %d\n", length(log_skip)))
cat(sprintf("  Advertencias: %d\n", length(log_warn)))
cat(sprintf("  Tiempo: %.1f min\n", as.numeric(t_total)))
cat(sprintf("  Output: %s/\n", DIR_OUT))
cat("================================================================\n\n")
