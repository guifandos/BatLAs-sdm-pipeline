# ==============================================================================
# server.R - Lógica reactiva
# ==============================================================================

# Textos de interpretación por capa
TEXTOS_CAPA <- list(
  F_final = "Favorabilidad integrada (0-1): combina el modelo ambiental y el espacial. Valores > 0.5 indican condiciones globalmente favorables para la especie.",
  F_amb   = "Favorabilidad ambiental (0-1): basada únicamente en las variables ambientales del GLM, independiente de la prevalencia. Refleja la idoneidad del hábitat.",
  F_esp   = "Favorabilidad espacial (0-1): componente geográfico modelado con GAM sobre coordenadas. Captura patrones espaciales no explicados por las variables ambientales.",
  U_final = "Incertidumbre (0-1): combina extrapolación ambiental (MESS), variabilidad bootstrap y esfuerzo de muestreo. Valores altos = menor fiabilidad de la predicción.",
  bivariado = "Mapa bivariado: cruza favorabilidad (eje vertical) con incertidumbre (eje horizontal). Las celdas verde oscuro son las de mayor favorabilidad y menor incertidumbre."
)

server <- function(input, output, session) {

  # --- Gestión de inactividad ---
  session_continued <- reactiveVal(FALSE)

  observeEvent(input$inactivity_warning, {
    session_continued(FALSE)
    showModal(modalDialog(
      title = "Sesión inactiva",
      tags$p("Tu sesión ha estado inactiva durante un tiempo.",
             "La aplicación se cerrará en 60 segundos a menos que continúes."),
      footer = actionButton("btn_continue_session", "Continuar sesión",
                            class = "btn-primary"),
      easyClose = FALSE
    ))
    later::later(function() {
      if (!isolate(session_continued())) {
        session$close()
      }
    }, delay = 60)
  })

  observeEvent(input$btn_continue_session, {
    session_continued(TRUE)
    removeModal()
  })

  # Ocultar/mostrar sidebar según la pestaña activa
  observeEvent(input$tabs, {
    if (input$tabs %in% c("Proyecto", "Metodología")) {
      shinyjs::runjs("$('.bslib-page-sidebar .sidebar').hide(); $('.bslib-page-sidebar .main').css('grid-column', '1 / -1');")
    } else {
      shinyjs::runjs("$('.bslib-page-sidebar .sidebar').show(); $('.bslib-page-sidebar .main').css('grid-column', '');")
    }
  })

  # Especie activa
  datos_especie <- reactive({
    sp_file <- input$sel_especie
    req(sp_file)
    tryCatch(
      cargar_especie(sp_file),
      error = function(e) {
        showNotification(paste("Error cargando", sp_file, ":", e$message),
                         type = "error")
        NULL
      }
    )
  })

  # --- Sidebar: Ficha de especie ---
  output$ficha_especie <- renderUI({
    d <- datos_especie()
    req(d)
    ficha_especie_ui(d$meta)
  })

  # ========================================================================
  # Tab 1: Distribución
  # ========================================================================

  output$mapa_leaflet <- renderLeaflet({
    d <- datos_especie()
    req(d)
    crear_mapa_leaflet(d$mapa, capa = isolate(input$sel_capa) %||% "F_final")
  })

  observeEvent(input$sel_capa, {
    d <- datos_especie()
    req(d)
    actualizar_capa_mapa(leafletProxy("mapa_leaflet"), d$mapa, input$sel_capa)
  })

  # Texto de interpretación de la capa activa
  output$texto_capa <- renderUI({
    capa <- input$sel_capa %||% "F_final"
    texto <- TEXTOS_CAPA[[capa]] %||% ""
    tags$p(texto)
  })

  # Modal: Panel SECEMU
  observeEvent(input$btn_panel_secemu, {
    sp_file <- input$sel_especie
    req(sp_file)
    png_path <- file.path(DATA_DIR, "mapas_png", sp_file, "panel_SECEMU.png")
    if (file.exists(png_path)) {
      showModal(modalDialog(
        title = paste("Panel SECEMU \u2014", gsub("_", " ", sp_file)),
        tags$img(src = paste0("mapas_png/", sp_file, "/panel_SECEMU.png"),
                 style = "width:100%;"),
        size = "xl", easyClose = TRUE
      ))
    } else {
      showNotification("PNG no disponible", type = "warning")
    }
  })

  # Modal: Panel incertidumbre
  observeEvent(input$btn_panel_incert, {
    sp_file <- input$sel_especie
    req(sp_file)
    png_path <- file.path(DATA_DIR, "mapas_png", sp_file, "panel_incertidumbre.png")
    if (file.exists(png_path)) {
      showModal(modalDialog(
        title = paste("Panel incertidumbre \u2014", gsub("_", " ", sp_file)),
        tags$img(src = paste0("mapas_png/", sp_file, "/panel_incertidumbre.png"),
                 style = "width:100%;"),
        size = "xl", easyClose = TRUE
      ))
    } else {
      showNotification("PNG no disponible", type = "warning")
    }
  })

  # Modal: Curvas respuesta PNG
  observeEvent(input$btn_curvas_png, {
    sp_file <- input$sel_especie
    req(sp_file)
    png_path <- file.path(DATA_DIR, "mapas_png", sp_file, "curvas_respuesta.png")
    if (file.exists(png_path)) {
      showModal(modalDialog(
        title = paste("Curvas de respuesta \u2014", gsub("_", " ", sp_file)),
        tags$img(src = paste0("mapas_png/", sp_file, "/curvas_respuesta.png"),
                 style = "width:100%;"),
        size = "xl", easyClose = TRUE
      ))
    } else {
      showNotification("PNG no disponible", type = "warning")
    }
  })

  # ========================================================================
  # Tab 2: Modelo
  # ========================================================================

  output$tabla_vars <- DT::renderDT({
    d <- datos_especie()
    req(d)
    tabla_variables_dt(d$vars)
  })

  # Modal: Curvas de respuesta desde pestaña Modelo
  observeEvent(input$btn_curvas_modelo, {
    sp_file <- input$sel_especie
    req(sp_file)
    png_path <- file.path(DATA_DIR, "mapas_png", sp_file, "curvas_respuesta.png")
    if (file.exists(png_path)) {
      showModal(modalDialog(
        title = paste("Curvas de respuesta \u2014", gsub("_", " ", sp_file)),
        tags$img(src = paste0("mapas_png/", sp_file, "/curvas_respuesta.png"),
                 style = "width:100%;"),
        size = "xl", easyClose = TRUE
      ))
    } else {
      showNotification("PNG de curvas no disponible para esta especie", type = "warning")
    }
  })
}
