# ==============================================================================
# helpers_graficos.R - Funciones ggplot2
# ==============================================================================

# Variables geometricas de la malla UTM — no ecologicas, excluir de visualizacion
VARS_GEOMETRICAS <- c("PERIM_km", "Shape_Area", "Shape_Leng", "Shape_Le_1",
                       "AREA_km", "Area_km2", "LaLo", "XCENTROIDE", "YCENTROIDE",
                       "OBJECTID", "FID", "Id")

filtrar_geometricas <- function(df, col = "name") {
  df |> filter(!(!!sym(col) %in% VARS_GEOMETRICAS))
}

tema_atlas <- function(base_size = 13) {
  theme_minimal(base_size = base_size, base_family = "sans") +
    theme(
      plot.title       = element_text(face = "bold", size = rel(1.1), color = "#1B2A4A"),
      plot.subtitle    = element_text(color = "#8D99AE", size = rel(0.85), margin = margin(b = 10)),
      plot.background  = element_rect(fill = "white", color = NA),
      panel.background = element_rect(fill = "#FAFBFD", color = NA),
      panel.grid.major = element_line(color = "#EDF2F7", linewidth = 0.4),
      panel.grid.minor = element_blank(),
      panel.border     = element_rect(color = "#E2E8F0", fill = NA, linewidth = 0.5),
      axis.text        = element_text(color = "#4A5568"),
      axis.title       = element_text(color = "#2D3748", face = "bold", size = rel(0.9)),
      legend.position  = "bottom",
      legend.title     = element_text(face = "bold", size = rel(0.85)),
      legend.text      = element_text(size = rel(0.8)),
      plot.margin      = margin(10, 15, 10, 10)
    )
}

# --- Forest plot de coeficientes ---
grafico_forest <- function(vars_data) {
  dat <- vars_data |>
    filtrar_geometricas() |>
    filter(!is.na(estimate)) |>
    distinct(name, .keep_all = TRUE) |>
    arrange(abs(estimate)) |>
    mutate(
      name = factor(name, levels = unique(name)),
      sig_label = ifelse(significativo, "p < 0.05", "n.s.")
    )

  if (nrow(dat) > 25) dat <- tail(dat, 25)

  ggplot(dat, aes(x = estimate, y = name, color = direccion, alpha = sig_label)) +
    geom_vline(xintercept = 0, linetype = "solid", color = "#CBD5E0", linewidth = 0.6) +
    geom_errorbar(aes(xmin = IC_low, xmax = IC_high),
                  width = 0.25, linewidth = 0.6, orientation = "y") +
    geom_point(aes(shape = sig_label), size = 3.5, stroke = 0.8) +
    scale_color_manual(
      values = c("positivo" = "#06D6A0", "negativo" = "#EF476F", "neutro" = "#8D99AE"),
      name = "Efecto"
    ) +
    scale_alpha_manual(
      values = c("p < 0.05" = 1, "n.s." = 0.35),
      name = "Significancia"
    ) +
    scale_shape_manual(
      values = c("p < 0.05" = 19, "n.s." = 1),
      name = "Significancia"
    ) +
    labs(
      title    = "Coeficientes del modelo GLM",
      subtitle = "IC 95% | Relleno = significativo (p < 0.05) | Vacio = no significativo",
      x = "Coeficiente (log-odds)", y = NULL
    ) +
    tema_atlas() +
    theme(legend.position = "top", legend.box = "horizontal")
}

# --- Tabla DT de variables ---
tabla_variables_dt <- function(vars_data) {
  dat <- vars_data |>
    filtrar_geometricas() |>
    select(name, estimate, std.error, statistic, p, direccion, significativo) |>
    mutate(
      nombre = ifelse(name %in% names(DICCIONARIO_VARS),
                      DICCIONARIO_VARS[name], name),
      estimate  = round(estimate, 4),
      std.error = round(std.error, 4),
      statistic = round(statistic, 3),
      p         = round(p, 4)
    ) |>
    select(name, nombre, estimate, std.error, statistic, p, direccion, significativo) |>
    arrange(p)

  DT::datatable(
    dat,
    options = list(pageLength = 15, dom = "tip", scrollX = TRUE,
                   order = list(list(4, "asc"))),
    rownames = FALSE,
    colnames = c("Codigo", "Variable", "Coeficiente", "Error std.", "z-value", "p-valor",
                 "Efecto", "Significativo"),
    caption = htmltools::tags$caption(
      style = "caption-side: top; font-size: 12px; color: #8D99AE; padding: 6px 0;",
      htmltools::HTML("p-valor: <span style='background:#D1FAE5;padding:2px 6px;border-radius:3px;'>verde = p &lt; 0.01</span> &nbsp; <span style='background:#FEF3C7;padding:2px 6px;border-radius:3px;'>amarillo = p &lt; 0.05</span> &nbsp; blanco = no significativo")
    )
  ) |>
    DT::formatStyle("p",
      backgroundColor = DT::styleInterval(
        cuts   = c(0.01, 0.05),
        values = c("#D1FAE5", "#FEF3C7", "white")
      )
    ) |>
    DT::formatStyle("direccion",
      color = DT::styleEqual(
        levels = c("positivo", "negativo", "neutro"),
        values = c("#06D6A0", "#EF476F", "#8D99AE")
      ),
      fontWeight = "bold"
    )
}

# --- Curvas de respuesta (panel unico, alto impacto) ---
grafico_curva_respuesta <- function(curvas_data, variable_sel) {
  dat <- curvas_data |>
    filtrar_geometricas("variable") |>
    filter(variable == variable_sel)
  if (nrow(dat) == 0) return(NULL)

  mediana_x <- median(dat$x, na.rm = TRUE)

  # Calcular rango de x donde hay mas datos (percentil 10-90) para sombrear
  q10 <- quantile(dat$x, 0.05, na.rm = TRUE)
  q90 <- quantile(dat$x, 0.95, na.rm = TRUE)

  # Colores
  col_fav  <- "#FF6B35"
  col_prob <- "#0077B6"

  # Area bajo la curva de favorabilidad
  p <- ggplot(dat, aes(x = x)) +
    # Zona de datos fiables
    annotate("rect", xmin = q10, xmax = q90, ymin = -Inf, ymax = Inf,
             fill = "#F0F4F8", alpha = 0.6) +
    # Referencia F=0.5
    geom_hline(yintercept = 0.5, linetype = "dashed", color = "#CBD5E0", linewidth = 0.5) +
    # Area bajo favorabilidad
    geom_ribbon(aes(ymin = 0, ymax = favorabilidad), fill = col_fav, alpha = 0.12) +
    # Linea de probabilidad (secundaria, fina)
    geom_line(aes(y = probabilidad), color = col_prob, linewidth = 0.9, alpha = 0.6) +
    # Linea de favorabilidad (principal, gruesa)
    geom_line(aes(y = favorabilidad), color = col_fav, linewidth = 1.6) +
    # Mediana
    geom_vline(xintercept = mediana_x, linetype = "dotted",
               color = "#A0AEC0", linewidth = 0.6) +
    annotate("label", x = mediana_x, y = 0.97, label = "med.",
             fill = "white", color = "#718096", size = 3,
             label.size = 0.2, label.r = unit(3, "pt"), alpha = 0.9) +
    # Etiquetas de lineas
    annotate("text", x = max(dat$x) * 0.98, y = tail(dat$favorabilidad, 1),
             label = "Favorabilidad", color = col_fav, fontface = "bold",
             size = 3.5, hjust = 1, vjust = -0.5) +
    annotate("text", x = max(dat$x) * 0.98, y = tail(dat$probabilidad, 1),
             label = "Probabilidad", color = col_prob,
             size = 3.2, hjust = 1, vjust = 1.5, alpha = 0.7) +
    scale_y_continuous(
      limits = c(0, 1), breaks = seq(0, 1, 0.25),
      labels = c("0", "0.25", "0.50", "0.75", "1.00")
    ) +
    labs(
      title = variable_sel,
      subtitle = paste0(
        "Naranja = favorabilidad (corregida por prevalencia) | ",
        "Azul = probabilidad GLM\n",
        "Zona sombreada = rango central de los datos (P5-P95) | ",
        "Linea discontinua = F = 0.5"
      ),
      x = variable_sel,
      y = "Respuesta"
    ) +
    tema_atlas(base_size = 14) +
    theme(
      plot.title = element_text(size = 16, face = "bold.italic"),
      plot.subtitle = element_text(size = 10.5, lineheight = 1.3)
    )

  p
}
