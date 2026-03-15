# ==============================================================================
# 04d_curvas_respuesta.R - Curvas de respuesta parcial (GLM)
# ==============================================================================
#
# Genera curvas de respuesta parcial para las 4 variables con mayor impacto
# en el modelo GLM de cada especie, con intervalos de confianza bootstrap (95%).
#
# CARACTERÍSTICAS:
#   - Selección automática de las 4 variables con mayor |coeficiente|
#   - IC 95% mediante bootstrap (200 iteraciones)
#   - Curvas de favorabilidad (Real et al. 2006)
#   - Color por tipo de variable (Climática, Topográfica, Geológica, Cobertura)
#   - Rug plots: presencias (arriba) y ausencias (abajo)
#   - Panel 2×2 por especie
#
# OUTPUT:
#   {CONFIG$output$base}/{Especie}/ambiental/response_curves.png
#
# AUTOR: Guillermo Fandos (UCM)
# ==============================================================================

if (!exists("CONFIG")) source("R/00_setup/00_config.R")

suppressPackageStartupMessages({
  library(tidyverse)
  library(patchwork)
})

cat("\n")
cat("================================================================\n")
cat("  CURVAS DE RESPUESTA GLM\n")
cat("================================================================\n\n")

# ==============================================================================
# CONFIGURACION DE CURVAS
# ==============================================================================

CURVAS_CONFIG <- list(
  n_vars = 4,
  n_boot = 200,
  n_puntos = 100,
  dpi = 300,
  ancho = 10,
  alto = 8
)

# ==============================================================================
# PALETA POR TIPO DE VARIABLE
# ==============================================================================

# Cargar diccionario de variables
dicc_file <- CONFIG$paths$diccionario_variables
if (file.exists(dicc_file)) {
  diccionario <- read_csv(dicc_file, show_col_types = FALSE)
} else {
  diccionario <- tibble(variable = character(), tipo = character())
}

# Paleta de colores por tipo
paleta_tipo <- c(
  "Climatica"   = "#2166ac",
  "Topografica" = "#8c510a",
  "Geologica"   = "#e66101",
  "Cobertura"   = "#1b7837",
  "Forestal"    = "#4dac26",
  "Otra"        = "#636363"
)

# Variables geométricas de la cuadrícula UTM (no ecológicas) - excluir del ranking
VARS_GEOMETRICAS <- c("PERIM_km", "Shape_Area", "Shape_Leng", "Shape_Le_1",
                       "AREA_km", "LaLo", "XCENTROIDE", "YCENTROIDE",
                       "OBJECTID", "FID", "Id")

# Función para obtener tipo de variable
get_tipo_variable <- function(var_name) {
  # Buscar en diccionario
  match <- diccionario |> filter(variable == var_name)
  if (nrow(match) > 0) return(match$tipo[1])

  # Heurísticas por nombre
  if (str_detect(var_name, "^Bio|^[PT]|^SIS|^PSum|^TSum|^SISSpr|^DP|^DTN|Rad|Prec|Temp"))
    return("Climatica")
  if (str_detect(var_name, regex("Alt|Slop|SRTM|Aspect|elev|pendiente", ignore_case = TRUE)))
    return("Topografica")
  if (str_detect(var_name, "Karst|Lito|lito|geo|karst"))
    return("Geologica")
  if (str_detect(var_name, regex("^C_|^CLC|Corine|Shannon|Comple|forest|bosque|NDVI|Olivar|Frutales|Vinedo|Herb|Mat_|Mosaico|Roquedos|Riberas|Masas_agua|Dens_pob|Area_deg|otros_hab|Cul_herb|Regadio|Secano|Dehesa|Pastizal", ignore_case = TRUE)))
    return("Cobertura")
  if (str_detect(var_name, "_ab$|Haya|Roble|Pino|Encina|Alcorno|Quercus|Pal$"))
    return("Forestal")

  return("Otra")
}

# ==============================================================================
# FUNCIONES
# ==============================================================================

favorabilidad <- function(prob, y) {
  n1 <- sum(y == 1, na.rm = TRUE)
  n0 <- sum(y == 0, na.rm = TRUE)
  odds_prob <- prob / (1 - prob)
  odds_prev <- n1 / n0
  odds_prob / (odds_prob + odds_prev)
}

generar_curvas_respuesta <- function(especie, dir_modelos,
                                     n_vars = CURVAS_CONFIG$n_vars,
                                     n_boot = CURVAS_CONFIG$n_boot,
                                     n_puntos = CURVAS_CONFIG$n_puntos) {

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

  # Extraer dataframe de datos
  if (is.list(datos_list) && "datos" %in% names(datos_list)) {
    datos <- datos_list$datos
  } else {
    datos <- datos_list
  }

  # Variables base del modelo

  vars_modelo <- all.vars(formula(modelo))
  vars_modelo <- vars_modelo[vars_modelo != "PA"]
  vars_modelo <- intersect(vars_modelo, names(datos))

  if (length(vars_modelo) == 0) {
    cat(sprintf("  [SKIP] Sin variables para %s\n", especie))
    return(NULL)
  }

  # Ranking completo por |z-value| (excluyendo geométricas)
  # Usar |statistic| (= estimate/std.error) premia variables con efecto real
  # y penaliza las infladas por multicolinealidad
  coefs_ranked <- coefs |>
    filter(Variable != "(Intercept)", !is.na(estimate), !is.na(statistic)) |>
    mutate(Variable_base = str_extract(Variable, "[A-Za-z_][A-Za-z0-9_]*")) |>
    filter(!is.na(Variable_base),
           Variable_base %in% vars_modelo,
           !(Variable_base %in% VARS_GEOMETRICAS)) |>
    group_by(Variable_base) |>
    summarise(Z_max = max(abs(statistic), na.rm = TRUE), .groups = "drop") |>
    arrange(desc(Z_max))

  # Top 4 para mostrar, top 15 para el modelo reducido del bootstrap
  top_vars <- head(coefs_ranked$Variable_base, n_vars)
  n_boot_vars <- min(15, nrow(coefs_ranked))
  vars_boot <- head(coefs_ranked$Variable_base, n_boot_vars)

  if (length(top_vars) == 0) return(NULL)

  # Reajustar modelo reducido con solo las top variables (estabilidad bootstrap)
  modelo_red <- suppressWarnings(tryCatch({
    glm(PA ~ ., data = datos |> select(PA, all_of(vars_boot)),
        family = binomial)
  }, error = function(e) modelo))  # fallback al modelo completo

  y <- as.numeric(datos$PA)
  plots_list <- list()

  for (i in seq_along(top_vars)) {
    var <- top_vars[i]
    tipo <- get_tipo_variable(var)
    col <- unname(paleta_tipo[tipo])
    if (is.na(col)) col <- paleta_tipo["Otra"]

    var_range <- range(datos[[var]], na.rm = TRUE)
    var_seq <- seq(var_range[1], var_range[2], length.out = n_puntos)

    # Base: medianas (solo variables del modelo reducido)
    base_data <- datos |>
      select(all_of(vars_boot)) |>
      summarise(across(everything(), \(x) median(x, na.rm = TRUE))) |>
      slice(rep(1, n_puntos))
    base_data[[var]] <- var_seq

    # Curva principal (modelo reducido)
    pred_main <- predict(modelo_red, newdata = base_data, type = "response")
    fav_main <- favorabilidad(pred_main, y)

    # Bootstrap IC 95% (modelo reducido — estable)
    boot_matrix <- matrix(NA, nrow = n_puntos, ncol = n_boot)
    set.seed(123)

    for (b in seq_len(n_boot)) {
      boot_idx <- sample(nrow(datos), replace = TRUE)
      datos_boot <- datos[boot_idx, ]
      y_boot <- as.numeric(datos_boot$PA)

      modelo_boot <- suppressWarnings(tryCatch({
        glm(PA ~ ., data = datos_boot |> select(PA, all_of(vars_boot)),
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

    # Etiqueta con tipo de variable
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
      labs(x = var_label, y = "Favorabilidad") +
      theme_minimal(base_size = 11) +
      theme(
        plot.background = element_rect(fill = "white", colour = NA),
        panel.background = element_rect(fill = "white", colour = NA),
        panel.grid.minor = element_blank(),
        panel.border = element_rect(colour = "grey80", fill = NA, linewidth = 0.5),
        axis.title.x = element_text(size = 10, face = "bold", colour = col),
        axis.title.y = element_text(size = 10),
        axis.text = element_text(size = 9)
      )

    plots_list[[var]] <- p
  }

  if (length(plots_list) == 0) return(NULL)

  # Obtener gremio de la especie
  gremios_sp <- ""
  gremios_file <- CONFIG$paths$especies_gremios
  if (file.exists(gremios_file)) {
    grem <- read_csv(gremios_file, show_col_types = FALSE)
    match_sp <- grem |> filter(especie == !!especie)
    if (nrow(match_sp) > 0) {
      gremios_sp <- sprintf("Refugio: %s | Alimentacion: %s",
                            match_sp$refugio[1], match_sp$alimentacion[1])
    }
  }

  p_combined <- wrap_plots(plots_list, ncol = 2) +
    plot_annotation(
      title = especie,
      subtitle = sprintf("%s\nIC 95%% bootstrap (n=%d) | Top %d variables por |z-value|",
                         gremios_sp, n_boot, length(top_vars)),
      caption = paste(
        "Linea = favorabilidad parcial | Banda = IC 95%",
        "| F=0.5 linea discontinua (neutralidad)",
        "\nRug superior (verde) = presencias | Rug inferior (rojo) = ausencias",
        "\nColores:", paste(names(paleta_tipo), "=",
                            unname(paleta_tipo), collapse = " | ")
      ),
      theme = theme(
        plot.title = element_text(size = 14, face = "bold.italic", hjust = 0.5),
        plot.subtitle = element_text(size = 9, colour = "grey30", hjust = 0.5),
        plot.caption = element_text(size = 7, colour = "grey50", hjust = 0),
        plot.background = element_rect(fill = "white", colour = NA)
      )
    )

  # Guardar
  output_file <- file.path(dir_sp, "response_curves.png")
  ggsave(output_file, p_combined,
         width = CURVAS_CONFIG$ancho, height = CURVAS_CONFIG$alto,
         dpi = CURVAS_CONFIG$dpi, bg = "white")

  return(output_file)
}

# ==============================================================================
# EJECUTAR PARA TODAS LAS ESPECIES
# ==============================================================================

dir_modelos <- CONFIG$output$base

dirs_sp <- list.dirs(dir_modelos, recursive = FALSE, full.names = FALSE)
especies <- str_replace_all(dirs_sp, "_", " ")

cat(sprintf("Directorio: %s\n", dir_modelos))
cat(sprintf("Especies: %d\n", length(especies)))
cat(sprintf("Config: %d variables, %d bootstrap, %d puntos/curva\n\n",
            CURVAS_CONFIG$n_vars, CURVAS_CONFIG$n_boot, CURVAS_CONFIG$n_puntos))

t_inicio <- Sys.time()
n_ok <- 0
n_skip <- 0

for (i in seq_along(especies)) {
  sp <- especies[i]
  cat(sprintf("[%d/%d] %s... ", i, length(especies), sp))

  resultado <- tryCatch(
    suppressWarnings(generar_curvas_respuesta(sp, dir_modelos)),
    error = function(e) {
      cat(sprintf("ERROR: %s\n", e$message))
      NULL
    }
  )

  if (!is.null(resultado)) {
    n_ok <- n_ok + 1
    cat("OK\n")
  } else {
    n_skip <- n_skip + 1
  }
}

t_total <- difftime(Sys.time(), t_inicio, units = "mins")

cat(sprintf("\n[OK] Curvas completadas: %d/%d en %.1f min\n",
            n_ok, length(especies), as.numeric(t_total)))
cat(sprintf("     Omitidas: %d\n", n_skip))
cat(sprintf("     Output: %s/*/ambiental/response_curves.png\n\n", dir_modelos))
