# ==============================================================================
# ui.R - Interfaz de la Shiny app
# ==============================================================================

ui <- tagList(
  tags$footer(
    class = "atlas-footer",
    tags$span("Guillermo Fandos · UCM · 2025")
  ),
  page_sidebar(
  title = tags$span(
    tags$img(src = "Logo_SECEMU-Horizontal.png", height = "28px",
             style = "vertical-align:middle; margin-right:10px;"),
    tags$strong("Atlas de Murciélagos Ibéricos"),
    tags$span(" | SECEMU", style = "color:#00B4D8; font-weight:400; font-size:0.85em;")
  ),
  theme = bs_theme(
    version   = 5,
    bg        = "#F7F9FC",
    fg        = "#1B2A4A",
    primary   = "#1B2A4A",
    secondary = "#00B4D8",
    "font-size-base" = "0.9rem"
  ),
  tags$head(tags$link(rel = "stylesheet", href = "custom.css")),
  shinyjs::useShinyjs(),

  # --- Sidebar ---
  sidebar = sidebar(
    width = 300,
    title = "Especie",
    pickerInput(
      "sel_especie",
      label = NULL,
      choices = ESPECIES_CHOICES,
      selected = ESPECIES_CHOICES[1],
      options = pickerOptions(liveSearch = TRUE, size = 15,
                              style = "btn-outline-dark")
    ),
    tags$hr(),
    uiOutput("ficha_especie")
  ),

  # --- Panel principal con tabs ---
  navset_card_tab(
    id = "tabs",

    # Tab 0: Proyecto
    nav_panel(
      title = "Proyecto",
      icon = icon("house"),
      proyecto_tab_ui()
    ),

    # Tab 0b: Metodología
    nav_panel(
      title = "Metodología",
      icon = icon("flask"),
      metodologia_tab_ui()
    ),

    # Tab 1: Distribución
    nav_panel(
      title = "Distribución",
      icon = icon("map"),
      layout_columns(
        col_widths = c(9, 3),
        card(
          full_screen = TRUE,
          card_header("Mapa de distribución"),
          leafletOutput("mapa_leaflet", height = "580px"),
          tags$div(class = "mapa-interpretacion",
            uiOutput("texto_capa")
          )
        ),
        tagList(
          card(
            card_header("Capa"),
            radioGroupButtons(
              "sel_capa", label = NULL,
              choices = c(
                "Favorabilidad" = "F_final",
                "F. ambiental"  = "F_amb",
                "F. espacial"   = "F_esp",
                "Incertidumbre" = "U_final",
                "Bivariado"     = "bivariado"
              ),
              direction = "vertical",
              size = "sm",
              status = "outline-dark"
            )
          ),
          card(
            card_header("Paneles"),
            actionButton("btn_panel_secemu", "Panel SECEMU",
                         icon = icon("image"),
                         class = "btn-sm btn-outline-primary w-100 mb-2"),
            actionButton("btn_panel_incert", "Panel incertidumbre",
                         icon = icon("chart-area"),
                         class = "btn-sm btn-outline-info w-100 mb-2"),
            actionButton("btn_curvas_png", "Curvas respuesta",
                         icon = icon("chart-line"),
                         class = "btn-sm btn-outline-warning w-100")
          )
        )
      )
    ),

    # Tab 2: Modelo
    nav_panel(
      title = "Modelo",
      icon = icon("chart-bar"),
      card(
        full_screen = TRUE,
        card_header("Variables del modelo GLM"),
        tags$p(class = "mapa-interpretacion", style = "margin-top:0; margin-bottom:10px;",
          "Tabla de variables ambientales incluidas en el modelo, sus coeficientes",
          " y significancia estadística. Las variables significativas (p < 0.05)",
          " son las que más contribuyen a explicar la distribución de la especie."
        ),
        DT::DTOutput("tabla_vars")
      ),
      card(
        class = "mt-3",
        card_header("Curvas de respuesta"),
        tags$p(class = "mapa-interpretacion", style = "margin-top:0; margin-bottom:10px;",
          "Panel con las curvas de favorabilidad parcial para las 4 variables",
          " de mayor impacto del modelo. Cada curva muestra la respuesta de la especie",
          " a una variable, manteniendo el resto en su valor mediano."
        ),
        actionButton("btn_curvas_modelo", "Ver curvas de respuesta",
                     icon = icon("chart-line"),
                     class = "btn-outline-primary mb-2")
      )
    )
  )
))
