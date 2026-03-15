# ==============================================================================
# 04e_curvas_respuesta_todas.R - Curvas de respuesta individuales (1 PNG/variable)
# ==============================================================================
#
# Genera un PNG independiente por cada variable del modelo GLM de cada especie.
# IC 95% bootstrap. Formato igual al panel de 4 variables pero individual.
#
# OUTPUT:
#   {dir_modelos}/{Especie}/ambiental/curvas/{variable}.png
#
# AUTOR: Guillermo Fandos (UCM)
# ==============================================================================

if (!exists("CONFIG")) source("R/00_setup/00_config.R")

suppressPackageStartupMessages({
  library(tidyverse)
})

cat("\n")
cat("================================================================\n")
cat("  CURVAS DE RESPUESTA GLM - PNGs INDIVIDUALES\n")
cat("================================================================\n\n")

CURVAS_ALL_CONFIG <- list(
  n_boot = 200,
  n_puntos = 100,
  dpi = 300,
  ancho = 6,
  alto = 5
)

VARS_GEOMETRICAS <- c("PERIM_km", "Shape_Area", "Shape_Leng", "Shape_Le_1",
                       "AREA_km", "Area_km2", "LaLo", "XCENTROIDE", "YCENTROIDE",
                       "OBJECTID", "FID", "Id")

dicc_file <- CONFIG$paths$diccionario_variables
if (file.exists(dicc_file)) {
  diccionario <- read_csv(dicc_file, show_col_types = FALSE)
} else {
  diccionario <- tibble(variable = character(), tipo = character())
}

paleta_tipo <- c(
  "Climatica"   = "#2166ac",
  "Topografica" = "#8c510a",
  "Geologica"   = "#e66101",
  "Cobertura"   = "#1b7837",
  "Forestal"    = "#4dac26",
  "Otra"        = "#636363"
)

get_tipo_variable <- function(var_name) {
  match <- diccionario |> filter(variable == var_name)
  if (nrow(match) > 0) return(match$tipo[1])
  if (str_detect(var_name, "^Bio|^[PT]|^SIS|^PSum|^TSum|^SISSpr|^DP|^DTN|Rad|Prec|Temp"))
    return("Climatica")
  if (str_detect(var_name, regex("Alt|Slop|SRTM|Aspect|elev|pendiente|CTI|ETR|WE_|SE_|DAut", ignore_case = TRUE)))
    return("Topografica")
  if (str_detect(var_name, "Karst|Lito|lito|geo|karst"))
    return("Geologica")
  if (str_detect(var_name, regex("^C_|^CLC|Corine|Shannon|Comple|forest|bosque|NDVI|Olivar|Frutales|Vid$|Herb|Mat_|Mosaico|Roquedos|Riberas|Masas_agua|Dens_pob|Area_deg|otros_hab|Cul_|Regadio|Secano|Dehesa|Pastizal|Ciudad|Pueblo|Urban|Otros_urba|Carreteras|Arenales|Cult_inund|Deforest", ignore_case = TRUE)))
    return("Cobertura")
  if (str_detect(var_name, "_ab$|_den$|_dens$|Haya|Roble|Pino|Encina|Alcorno|Quercus|Pal$|Euca|Cast_|Fres_|Enc_alq|Planif|Plani_con|Pina_abe|Ene_sab|Lauri|Chopo"))
    return("Forestal")
  return("Otra")
}

favorabilidad <- function(prob, y) {
  n1 <- sum(y == 1, na.rm = TRUE)
  n0 <- sum(y == 0, na.rm = TRUE)
  odds_prob <- prob / (1 - prob)
  odds_prev <- n1 / n0
  odds_prob / (odds_prob + odds_prev)
}

# ==============================================================================
# FUNCION PRINCIPAL
# ==============================================================================

generar_curvas_individuales <- function(especie, dir_modelos,
                                        n_boot = CURVAS_ALL_CONFIG$n_boot,
                                        n_puntos = CURVAS_ALL_CONFIG$n_puntos) {

  sp_file <- str_replace_all(especie, " ", "_")
  dir_sp <- file.path(dir_modelos, sp_file, "ambiental")

  modelo_file <- file.path(dir_sp, "modelo_glm.rds")
  datos_file <- file.path(dir_sp, "datos_entrenamiento.rds")
  coef_file <- file.path(dir_sp, "coeficientes_glm.csv")

  if (!all(file.exists(c(modelo_file, datos_file, coef_file)))) {
    cat(sprintf("  [SKIP] Faltan archivos para %s\n", especie))
    return(NULL)
  }

  modelo <- readRDS(modelo_file)
  datos_list <- readRDS(datos_file)
  coefs <- read_csv(coef_file, show_col_types = FALSE)

  if (is.list(datos_list) && "datos" %in% names(datos_list)) {
    datos <- datos_list$datos
  } else {
    datos <- datos_list
  }

  # Todas las variables del modelo (incluyendo geometricas para prediccion)
  vars_modelo_all <- all.vars(formula(modelo))
  vars_modelo_all <- vars_modelo_all[vars_modelo_all != "PA"]
  vars_modelo_all <- intersect(vars_modelo_all, names(datos))

  # Variables ecologicas (sin geometricas) para generar curvas
  vars_ecol <- setdiff(vars_modelo_all, VARS_GEOMETRICAS)

  if (length(vars_ecol) == 0) {
    cat(sprintf("  [SKIP] Sin variables ecologicas para %s\n", especie))
    return(NULL)
  }

  # Ranking por |z-value| (solo ecologicas)
  coefs_ranked <- coefs |>
    filter(Variable != "(Intercept)", !is.na(estimate), !is.na(statistic)) |>
    mutate(Variable_base = str_extract(Variable, "[A-Za-z_][A-Za-z0-9_]*")) |>
    filter(!is.na(Variable_base),
           Variable_base %in% vars_ecol) |>
    group_by(Variable_base) |>
    summarise(Z_max = max(abs(statistic), na.rm = TRUE), .groups = "drop") |>
    arrange(desc(Z_max))

  all_vars <- coefs_ranked$Variable_base
  if (length(all_vars) == 0) return(NULL)

  # Modelo reducido (top 15 ecologicas) para bootstrap
  n_boot_vars <- min(15, length(all_vars))
  vars_boot <- head(all_vars, n_boot_vars)

  modelo_red <- suppressWarnings(tryCatch({
    glm(PA ~ ., data = datos |> select(PA, all_of(vars_boot)), family = binomial)
  }, error = function(e) modelo))

  y <- as.numeric(datos$PA)

  # Directorio de salida
  dir_curvas <- file.path(dir_sp, "curvas")
  dir.create(dir_curvas, recursive = TRUE, showWarnings = FALSE)

  n_saved <- 0

  for (i in seq_along(all_vars)) {
    var <- all_vars[i]
    tipo <- get_tipo_variable(var)
    col <- unname(paleta_tipo[tipo])
    if (is.na(col)) col <- paleta_tipo["Otra"]

    var_range <- range(datos[[var]], na.rm = TRUE)
    var_seq <- seq(var_range[1], var_range[2], length.out = n_puntos)

    # Elegir modelo para prediccion
    if (var %in% vars_boot) {
      mod_usar <- modelo_red
      vars_pred <- vars_boot
    } else {
      mod_usar <- modelo
      vars_pred <- vars_modelo_all  # incluye geometricas para prediccion correcta
    }

    base_data <- datos |>
      select(all_of(vars_pred)) |>
      summarise(across(everything(), \(x) median(x, na.rm = TRUE))) |>
      slice(rep(1, n_puntos))
    base_data[[var]] <- var_seq

    pred_main <- predict(mod_usar, newdata = base_data, type = "response")
    fav_main <- favorabilidad(pred_main, y)

    # Bootstrap IC 95%
    boot_matrix <- matrix(NA, nrow = n_puntos, ncol = n_boot)
    set.seed(123 + i)

    for (b in seq_len(n_boot)) {
      boot_idx <- sample(nrow(datos), replace = TRUE)
      datos_boot <- datos[boot_idx, ]
      y_boot <- as.numeric(datos_boot$PA)

      modelo_boot <- suppressWarnings(tryCatch({
        glm(PA ~ ., data = datos_boot |> select(PA, all_of(vars_pred)),
            family = binomial)
      }, error = function(e) NULL))

      if (!is.null(modelo_boot) && modelo_boot$converged) {
        pred_boot <- suppressWarnings(
          predict(modelo_boot, newdata = base_data, type = "response")
        )
        boot_matrix[, b] <- favorabilidad(pred_boot, y_boot)
      }
    }

    fav_lower <- apply(boot_matrix, 1, quantile, probs = 0.025, na.rm = TRUE)
    fav_upper <- apply(boot_matrix, 1, quantile, probs = 0.975, na.rm = TRUE)

    df_curve <- tibble(x = var_seq, fav = fav_main,
                       fav_lower = fav_lower, fav_upper = fav_upper)

    datos_pres <- datos |> filter(PA == 1)
    datos_aus <- datos |> filter(PA == 0)

    var_label <- sprintf("%s  [%s]", var, tipo)

    p <- ggplot(df_curve, aes(x = x)) +
      geom_ribbon(aes(ymin = fav_lower, ymax = fav_upper),
                  fill = col, alpha = 0.2) +
      geom_line(aes(y = fav), color = col, linewidth = 1.2) +
      geom_hline(yintercept = 0.5, lty = 2, colour = "grey50", linewidth = 0.4) +
      geom_rug(data = datos_pres, aes(x = .data[[var]]),
               sides = "t", alpha = 0.3, color = "#1a9641",
               length = unit(0.03, "npc")) +
      geom_rug(data = datos_aus, aes(x = .data[[var]]),
               sides = "b", alpha = 0.15, color = "#d7191c",
               length = unit(0.03, "npc")) +
      scale_y_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.25)) +
      labs(
        title = sprintf("%s — %s", especie, var),
        subtitle = sprintf("IC 95%% bootstrap (n=%d) | Tipo: %s | Rank z-value: %d/%d",
                           n_boot, tipo, i, length(all_vars)),
        x = var_label,
        y = "Favorabilidad",
        caption = "Linea = favorabilidad parcial | Banda = IC 95% | F=0.5 = neutralidad\nRug verde = presencias | Rug rojo = ausencias"
      ) +
      theme_minimal(base_size = 12) +
      theme(
        plot.title = element_text(size = 14, face = "bold.italic"),
        plot.subtitle = element_text(size = 9, colour = "grey40"),
        plot.caption = element_text(size = 7, colour = "grey50"),
        plot.background = element_rect(fill = "white", colour = NA),
        panel.background = element_rect(fill = "white", colour = NA),
        panel.grid.minor = element_blank(),
        panel.border = element_rect(colour = "grey80", fill = NA, linewidth = 0.5),
        axis.title.x = element_text(size = 11, face = "bold", colour = col),
        axis.title.y = element_text(size = 11),
        axis.text = element_text(size = 9)
      )

    output_file <- file.path(dir_curvas, paste0(var, ".png"))
    ggsave(output_file, p,
           width = CURVAS_ALL_CONFIG$ancho, height = CURVAS_ALL_CONFIG$alto,
           dpi = CURVAS_ALL_CONFIG$dpi, bg = "white")

    n_saved <- n_saved + 1
  }

  return(n_saved)
}

# ==============================================================================
# EJECUTAR PARA TODAS LAS ESPECIES EN AMBOS OUTPUTS
# ==============================================================================

dirs_output <- c("output/modelos", "output_2014/modelos")

for (dir_modelos in dirs_output) {
  if (!dir.exists(dir_modelos)) {
    cat(sprintf("  [SKIP] Directorio no existe: %s\n", dir_modelos))
    next
  }

  dirs_sp <- list.dirs(dir_modelos, recursive = FALSE, full.names = FALSE)
  especies <- str_replace_all(dirs_sp, "_", " ")

  cat(sprintf("\n--- Directorio: %s ---\n", dir_modelos))
  cat(sprintf("Especies: %d\n", length(especies)))
  cat(sprintf("Config: TODAS las variables, %d bootstrap, %d puntos/curva, PNGs individuales\n\n",
              CURVAS_ALL_CONFIG$n_boot, CURVAS_ALL_CONFIG$n_puntos))

  t_inicio <- Sys.time()
  n_ok <- 0
  n_skip <- 0
  n_total_pngs <- 0

  for (i in seq_along(especies)) {
    sp <- especies[i]
    cat(sprintf("[%d/%d] %s... ", i, length(especies), sp))

    resultado <- tryCatch(
      suppressWarnings(generar_curvas_individuales(sp, dir_modelos)),
      error = function(e) {
        cat(sprintf("ERROR: %s\n", e$message))
        NULL
      }
    )

    if (!is.null(resultado) && resultado > 0) {
      n_ok <- n_ok + 1
      n_total_pngs <- n_total_pngs + resultado
      cat(sprintf("OK (%d PNGs)\n", resultado))
    } else {
      n_skip <- n_skip + 1
    }
  }

  t_total <- difftime(Sys.time(), t_inicio, units = "mins")
  cat(sprintf("\n[OK] Curvas individuales: %d especies, %d PNGs en %.1f min\n",
              n_ok, n_total_pngs, as.numeric(t_total)))
  cat(sprintf("     Output: %s/*/ambiental/curvas/*.png\n\n", dir_modelos))
}
