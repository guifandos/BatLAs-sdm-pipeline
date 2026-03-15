# ==============================================================================
# helpers_ui.R - Componentes UI reutilizables
# ==============================================================================

# Paleta principal - color-blind friendly, alto impacto visual (viridis-inspired)
COLORES <- list(
  primario   = "#1B2A4A",   # Azul noche profundo
  secundario = "#00B4D8",   # Cyan vibrante
  acento     = "#FF6B35",   # Naranja energético
  fondo      = "#F7F9FC",   # Gris azulado muy claro
  panel      = "#FFFFFF",
  borde      = "#E2E8F0",
  positivo   = "#06D6A0",   # Verde menta (CB-friendly)
  negativo   = "#EF476F",   # Rosa fuerte (CB-friendly)
  neutro     = "#8D99AE",
  texto      = "#2D3748"
)

# Colores gremio refugio - CB-friendly
COLORES_REFUGIO <- c(
  "Cavernicola" = "#0077B6",
  "Arboricola"  = "#06D6A0",
  "Fisuricola"  = "#FF6B35",
  "Generalista" = "#8338EC"
)

# Colores gremio alimentacion - CB-friendly
COLORES_ALIM <- c(
  "Forestal"    = "#06D6A0",
  "Ripario"     = "#0077B6",
  "Pastizal"    = "#FFD166",
  "Mosaico"     = "#FF6B35",
  "Aereo"       = "#8338EC",
  "Generalista" = "#8D99AE"
)

# Paletas para mapas - viridis-inspired, CB-friendly, elegantes
PAL_FAV  <- c("#FDE725", "#5DC863", "#21908C", "#3B528B", "#440154")  # viridis
PAL_INCE <- c("#FCFDBF", "#FCA636", "#E45A31", "#982D80", "#3B0F70")  # inferno
PAL_ESP  <- c("#F0F921", "#FCCE25", "#ED7953", "#CC4778", "#7E03A8")  # plasma

# Badge de gremio
badge_gremio <- function(gremio, tipo = "refugio") {
  cols <- if (tipo == "refugio") COLORES_REFUGIO else COLORES_ALIM
  bg <- unname(cols[gremio])
  if (is.na(bg) || is.null(bg)) bg <- COLORES$neutro
  label <- if (tipo == "refugio") paste0("Refugio: ", gremio) else paste0("Alimentación: ", gremio)
  tags$span(
    class = "badge-gremio",
    style = sprintf("background-color:%s;", bg),
    label
  )
}

# Tarjeta de métrica
metrica_card <- function(label, valor, tooltip = NULL) {
  card <- tags$div(
    class = "metrica-card",
    tags$span(class = "metrica-label", label),
    tags$span(class = "metrica-valor", valor)
  )
  if (!is.null(tooltip)) {
    card <- tippy::tippy(card, tooltip = tooltip, placement = "right")
  }
  card
}

# Ficha completa de especie
ficha_especie_ui <- function(meta_sp) {
  if (is.null(meta_sp) || nrow(meta_sp) == 0) return(NULL)

  tagList(
    tags$h5(tags$em(meta_sp$especie),
            style = "font-weight:bold; color:#1B2A4A; margin-bottom:4px;"),
    tags$div(
      style = "margin: 6px 0;",
      badge_gremio(meta_sp$gremio_refugio, "refugio"),
      badge_gremio(meta_sp$gremio_alimentacion, "alimentacion")
    ),
    tags$hr(style = "margin: 8px 0; border-color:#E2E8F0;"),
    metrica_card("Presencias", format(meta_sp$n_presencias, big.mark = ",")),
    metrica_card("Variables", meta_sp$n_variables),
    tags$hr(style = "margin: 6px 0; border-color:#E2E8F0;"),
    tags$p(tags$strong("Validación cruzada"), style = "font-size:11px; color:#8D99AE; margin:4px 0 2px;"),
    metrica_card("AUC", sprintf("%.3f \u00b1 %.3f", meta_sp$AUC_cv, meta_sp$AUC_cv_sd),
                 tooltip = "Área bajo la curva ROC - 10 rep. x 5 folds"),
    metrica_card("TSS", sprintf("%.3f \u00b1 %.3f", meta_sp$TSS_cv, meta_sp$TSS_cv_sd),
                 tooltip = "True Skill Statistic [-1,1]. >0.5 = bueno"),
    tags$p(tags$strong("Hold-out 70/30"), style = "font-size:11px; color:#8D99AE; margin:6px 0 2px;"),
    metrica_card("AUC", sprintf("%.3f", meta_sp$AUC_holdout)),
    metrica_card("Sensibilidad", sprintf("%.3f", meta_sp$Sens_holdout)),
    metrica_card("Especificidad", sprintf("%.3f", meta_sp$Spec_holdout))
  )
}

# Contenido de la pestaña "Proyecto"
proyecto_tab_ui <- function() {
  tagList(
    tags$div(
      class = "proyecto-hero",
      tags$h3("Atlas de Distribución de Murciélagos Ibéricos",
              style = "color:#1B2A4A; font-weight:700;"),
      tags$p(class = "lead-text",
        "Modelos de distribución de especies para las 29 especies de murciélagos",
        " de la Península Ibérica y Baleares, desarrollados en el marco del proyecto",
        " de Seguimiento y Atlas de Quirópteros del Ministerio para la Transición Ecológica (MITECO)."
      )
    ),

    # --- Bloque: Sobre el proyecto + Qué encontrarás ---
    layout_columns(
      col_widths = c(6, 6),
      card(
        class = "info-card",
        card_header(tags$span(icon("info-circle"), " Sobre el proyecto")),
        tags$p("Este proyecto, financiado por la UE-NextGenerationEU y coordinado por",
               " Tragsatec y la ", tags$strong("SECEMU"),
               " (Sociedad Española para la Conservación y Estudio de los Murciélagos),",
               " tiene como objetivo actualizar el atlas y el libro rojo de murciélagos españoles."),
        tags$p("Los datos provienen de:"),
        tags$ul(
          tags$li(tags$strong("~400 localidades"), " de grabaciones de ultrasonidos"),
          tags$li(tags$strong("~200 censos"), " de colonias cavernícolas"),
          tags$li(tags$strong("~220 trampeos"), " nocturnos con redes"),
          tags$li("Muestras genéticas de especies crípticas")
        ),
        tags$p("Periodo de muestreo: 2023-2025. Datos históricos complementarios",
               " desde bases de datos nacionales e internacionales."),
        tags$p(tags$em("Más información:"), " ",
               tags$a(href = "https://secemu.org/project/seguimiento-de-fauna/",
                      target = "_blank", "secemu.org/project/seguimiento-de-fauna"),
               style = "font-size:12px;")
      ),
      card(
        class = "info-card",
        card_header(tags$span(icon("chart-line"), " Qué encontrarás aquí")),
        tags$p("Esta aplicación permite explorar interactivamente los resultados",
               " de los modelos de distribución de cada especie:"),
        tags$ol(
          tags$li(tags$strong("Distribución: "),
                  "Mapas interactivos de favorabilidad ambiental, incertidumbre",
                  " y un mapa bivariado para cada cuadrícula UTM 10x10 km."),
          tags$li(tags$strong("Modelo: "),
                  "Variables ambientales incluidas en el GLM, sus coeficientes",
                  " y significancia estadística."),
          tags$li(tags$strong("Curvas de respuesta: "),
                  "Cómo responde la favorabilidad de cada especie a las 4 variables",
                  " ambientales de mayor impacto, manteniendo el resto en su valor mediano.")
        ),
        tags$hr(style = "margin: 8px 0;"),
        tags$p(icon("hand-point-right"), " ",
               tags$em("Selecciona una especie en el panel lateral y navega por las pestañas."),
               style = "color:#00B4D8; font-weight:500; font-size:13px;")
      )
    ),

    # --- Bloque: Equipo ---
    card(
      class = "info-card",
      card_header(tags$span(icon("users"), " Equipo")),
      tags$div(style = "padding: 10px 14px;",
        tags$div(style = "margin-bottom:10px;",
          tags$span(
            tags$strong("Guillermo Fandos", style = "font-size:16px; color:#1B2A4A;")
          ),
          tags$br(),
          tags$span("Dpto. Biodiversidad, Ecología y Evolución",
                    style = "font-size:13px; color:#718096;"),
          tags$br(),
          tags$span("Universidad Complutense de Madrid",
                    style = "font-size:13px; color:#718096; font-weight:600;")
        ),
        tags$p(
          "Desarrollo y modelado: diseño del pipeline de análisis,",
          " modelos de distribución y esta aplicación interactiva.",
          style = "font-size:13px; color:#4A5568; line-height:1.5; margin-bottom:8px;"
        ),
        tags$hr(style = "margin: 8px 0; border-color:#E2E8F0;"),
        tags$p(
          "La coordinación del proyecto de seguimiento corre a cargo de ",
          tags$strong("SECEMU"), " y ", tags$strong("Tragsatec"),
          ", financiado por la UE-NextGenerationEU a través del MITECO.",
          style = "font-size:13px; color:#4A5568; line-height:1.5;"
        ),
        tags$hr(style = "margin: 10px 0; border-color:#E2E8F0;"),
        tags$div(
          style = "display:flex; align-items:center; justify-content:center; gap:30px; padding:8px 0;",
          tags$img(src = "logo_ucm.jpeg", height = "50px", style = "object-fit:contain;"),
          tags$img(src = "Logo_SECEMU-Horizontal.png", height = "45px", style = "object-fit:contain;"),
          tags$img(src = "logo-miteco.png", height = "50px", style = "object-fit:contain;")
        )
      )
    )
  )
}

# Contenido de la pestaña "Metodología" (página corrida, sin cajitas)
metodologia_tab_ui <- function() {
  tags$div(
    class = "metodologia-page",

    tags$h3("Metodología", style = "color:#1B2A4A; font-weight:700; margin-bottom:5px;"),
    tags$p(class = "lead-text",
      "Descripción detallada del flujo de trabajo de la modelización de distribución de especies",
      " utilizado en este atlas."
    ),

    tags$hr(style = "border-color:#E2E8F0;"),

    # --- Datos de partida ---
    tags$h5(icon("database"), " Datos de partida",
            style = "color:#1B2A4A; font-weight:700; margin-top:20px;"),
    tags$p("Se utilizan datos de presencia/ausencia por cuadrícula UTM 10x10 km",
           " procedentes del muestreo estandarizado SECEMU (acústica, capturas, censos",
           " en refugios) y datos históricos. Las ausencias se asignan a cuadrículas",
           " muestreadas sin detección de la especie, según el método de muestreo",
           " adecuado para cada gremio (p.ej., cavernícolas en cuevas, forestales por acústica)."),
    tags$p(tags$strong("Ámbito geográfico:"),
           " Península Ibérica y Baleares. Las Islas Canarias no se incluyen",
           " en la modelización debido a sus particularidades biogeográficas",
           " y a la diferente composición de especies.",
           style = "font-style:italic; color:#718096;"),

    # --- Variables ambientales ---
    tags$h5(icon("layer-group"), " Variables ambientales",
            style = "color:#1B2A4A; font-weight:700; margin-top:24px;"),
    tags$p("Se han compilado ~90 variables predictoras agrupadas en cinco categorías:"),
    tags$div(style = "display:flex; flex-wrap:wrap; gap:6px; margin:10px 0;",
      tags$span(class = "badge-gremio", style = "background:#0077B6;", "Climáticas"),
      tags$span(class = "badge-gremio", style = "background:#8B6914;", "Topográficas"),
      tags$span(class = "badge-gremio", style = "background:#FF6B35;", "Geológicas / kársticas"),
      tags$span(class = "badge-gremio", style = "background:#06D6A0; color:#1B2A4A;", "Coberturas del suelo (CORINE)"),
      tags$span(class = "badge-gremio", style = "background:#8338EC;", "Forestales (IFN)")
    ),
    tags$p("Incluyen bioclimáticas, radiación, días extremos, altitud, pendiente, litología,",
           " karsticidad, coberturas CORINE agregadas, densidades forestales y Shannon de paisaje."),

    # --- Pipeline de modelado ---
    tags$h5(icon("cogs"), " Pipeline de modelado",
            style = "color:#1B2A4A; font-weight:700; margin-top:24px;"),

    tags$div(class = "metodo-paso-v",
      tags$div(class = "paso-num-v", "1"),
      tags$div(class = "paso-contenido",
        tags$h6("Selección de variables"),
        tags$p("Stability selection con 100 submuestras bootstrap.",
               " Solo se retienen variables seleccionadas en >80% de las submuestras.",
               " Filtro adicional de multicolinealidad (VIF) y evaluación AIC univariante.",
               " Cada especie recibe un set individualizado de variables.")
      )
    ),
    tags$div(class = "metodo-paso-v",
      tags$div(class = "paso-num-v", "2"),
      tags$div(class = "paso-contenido",
        tags$h6("Modelo ambiental"),
        tags$p("GLM binomial (logit link) con las variables seleccionadas.",
               " La probabilidad se transforma en favorabilidad ambiental (Real et al. 2006),",
               " que elimina el efecto de la prevalencia y permite comparar entre especies.",
               " IC 95% estimados por bootstrap (200 iteraciones).")
      )
    ),
    tags$div(class = "metodo-paso-v",
      tags$div(class = "paso-num-v", "3"),
      tags$div(class = "paso-contenido",
        tags$h6("Modelo espacial"),
        tags$p("GAM con tensor product smooth sobre las coordenadas (X, Y)",
               " para modelar la autocorrelación espacial residual.",
               " Se integra con el modelo ambiental mediante una intersección fuzzy",
               " (mínimo entre favorabilidad ambiental y espacial).")
      )
    ),
    tags$div(class = "metodo-paso-v",
      tags$div(class = "paso-num-v", "4"),
      tags$div(class = "paso-contenido",
        tags$h6("Validación e incertidumbre"),
        tags$p("Validación cruzada estratificada: 10 repeticiones x 5 folds.",
               " Métricas: AUC, TSS, sensibilidad, especificidad.",
               " Mapa de incertidumbre combinando MESS (extrapolación ambiental),",
               " anchura del IC bootstrap y esfuerzo de muestreo por cuadrícula.")
      )
    ),

    # --- Interpretación de resultados ---
    tags$h5(icon("magnifying-glass-chart"), " Cómo interpretar los resultados",
            style = "color:#1B2A4A; font-weight:700; margin-top:24px;"),
    tags$p(tags$strong("Favorabilidad (0-1):"),
           " Indica cuánto favorecen las condiciones ambientales de una cuadrícula",
           " a la presencia de la especie, independientemente de su prevalencia.",
           " Valores > 0.5 indican condiciones favorables; < 0.5 desfavorables."),
    tags$p(tags$strong("Incertidumbre (0-1):"),
           " Combina tres fuentes: (1) extrapolación ambiental (MESS),",
           " (2) variabilidad entre modelos bootstrap, y (3) esfuerzo de muestreo.",
           " Valores altos = mayor incertidumbre en la predicción."),
    tags$p(tags$strong("Mapa bivariado:"),
           " Combina favorabilidad e incertidumbre en una única visualización.",
           " Las cuadrículas verdes oscuras son las de mayor favorabilidad",
           " y menor incertidumbre (predicciones más fiables)."),

    # --- Referencia ---
    tags$hr(style = "margin-top:24px; border-color:#E2E8F0;"),
    tags$p(style = "font-size:11.5px; color:#8D99AE;",
           tags$strong("Referencia: "),
           "Real, R., Barbosa, A.M. & Vargas, J.M. (2006).",
           " Obtaining environmental favourability functions from logistic regression.",
           tags$em(" Environmental and Ecological Statistics"), ", 13, 237-245.")
  )
}
