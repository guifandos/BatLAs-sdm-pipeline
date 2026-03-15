# ==============================================================================
# helpers_mapa.R - Funciones leaflet
# ==============================================================================

# Leyenda bivariada mejorada
bivar_legend_html <- function() {
  sz <- "28px"
  '
  <div style="background:white; padding:12px 14px; border-radius:8px;
              box-shadow:0 2px 8px rgba(0,0,0,0.18); font-size:12px; line-height:1.3;">
    <div style="font-weight:700; font-size:13px; color:#1B2A4A; margin-bottom:8px;
                text-align:center;">Favorabilidad &times; Incertidumbre</div>
    <div style="display:flex; align-items:flex-end;">
      <!-- Eje Y label -->
      <div style="writing-mode:vertical-rl; transform:rotate(180deg);
                  font-size:11px; font-weight:600; color:#4A5568;
                  margin-right:6px; text-align:center; height:100px;">
        Favorabilidad &uarr;
      </div>
      <div>
        <!-- Grid 3x3 -->
        <table style="border-collapse:collapse;">
          <tr>
            <td style="width:28px;height:28px;background:#006d2c;border:1.5px solid #fff;" title="Alta F / Baja U"></td>
            <td style="width:28px;height:28px;background:#31a354;border:1.5px solid #fff;" title="Alta F / Media U"></td>
            <td style="width:28px;height:28px;background:#74c476;border:1.5px solid #fff;" title="Alta F / Alta U"></td>
          </tr>
          <tr>
            <td style="width:28px;height:28px;background:#feb24c;border:1.5px solid #fff;" title="Media F / Baja U"></td>
            <td style="width:28px;height:28px;background:#fed976;border:1.5px solid #fff;" title="Media F / Media U"></td>
            <td style="width:28px;height:28px;background:#ffffcc;border:1.5px solid #fff;" title="Media F / Alta U"></td>
          </tr>
          <tr>
            <td style="width:28px;height:28px;background:#3182bd;border:1.5px solid #fff;" title="Baja F / Baja U"></td>
            <td style="width:28px;height:28px;background:#9ecae1;border:1.5px solid #fff;" title="Baja F / Media U"></td>
            <td style="width:28px;height:28px;background:#deebf7;border:1.5px solid #fff;" title="Baja F / Alta U"></td>
          </tr>
        </table>
        <!-- Eje X label -->
        <div style="text-align:center; font-size:11px; font-weight:600;
                    color:#4A5568; margin-top:4px;">
          Incertidumbre &rarr;
        </div>
      </div>
      <!-- Etiquetas laterales -->
      <div style="display:flex; flex-direction:column; justify-content:space-between;
                  height:90px; margin-left:5px; font-size:9.5px; color:#718096;">
        <span>Alta</span>
        <span>Media</span>
        <span>Baja</span>
      </div>
    </div>
  </div>'
}

CAPAS_INFO <- list(
  F_final = list(pal = PAL_FAV,  domain = c(0, 1), label = "Favorabilidad integrada"),
  F_amb   = list(pal = PAL_FAV,  domain = c(0, 1), label = "Favorabilidad ambiental"),
  F_esp   = list(pal = PAL_ESP,  domain = c(0, 1), label = "Favorabilidad espacial"),
  U_final = list(pal = PAL_INCE, domain = c(0, 1), label = "Incertidumbre")
)

get_pal <- function(capa, mapa_sf) {
  info <- CAPAS_INFO[[capa]]
  dom <- if (is.null(info$domain)) range(mapa_sf[[capa]], na.rm = TRUE) else info$domain
  colorNumeric(info$pal, domain = dom, na.color = "transparent")
}

# Paleta bivariada: F_final (eje color) x U_final (eje saturacion)
get_bivar_colors <- function(mapa_sf) {
  # Clasificar en 3x3
  f_breaks <- quantile(mapa_sf$F_final, probs = c(0, 1/3, 2/3, 1), na.rm = TRUE)
  u_breaks <- quantile(mapa_sf$U_final, probs = c(0, 1/3, 2/3, 1), na.rm = TRUE)

  f_class <- as.integer(cut(mapa_sf$F_final, breaks = f_breaks, include.lowest = TRUE))
  u_class <- as.integer(cut(mapa_sf$U_final, breaks = u_breaks, include.lowest = TRUE))

  # Matriz 3x3 bivariada (fav rows, incert cols) - azul/amarillo/verde
  biv_pal <- matrix(c(
    "#3182bd", "#9ecae1", "#deebf7",  # Fav baja:  azules
    "#feb24c", "#fed976", "#ffffcc",  # Fav media: amarillos
    "#006d2c", "#31a354", "#74c476"   # Fav alta:  verdes
  ), nrow = 3, byrow = TRUE)

  colors <- rep("#E8E8E8", length(f_class))
  valid <- !is.na(f_class) & !is.na(u_class)
  colors[valid] <- biv_pal[cbind(f_class[valid], u_class[valid])]
  colors
}

crear_mapa_leaflet <- function(mapa_sf, capa = "F_final") {
  if (capa == "bivariado") {
    return(crear_mapa_bivariado(mapa_sf))
  }

  pal <- get_pal(capa, mapa_sf)
  info <- CAPAS_INFO[[capa]]

  fill_vals  <- pal(mapa_sf[[capa]])
  label_vals <- sprintf(
    "<b>%s</b><br><b>%s:</b> %.3f",
    mapa_sf$CUADRICULA, info$label, mapa_sf[[capa]]
  ) |> lapply(htmltools::HTML)

  leaflet(mapa_sf, options = leafletOptions(zoomControl = TRUE)) |>
    addProviderTiles("CartoDB.Positron") |>
    addPolygons(
      fillColor   = fill_vals,
      fillOpacity = 0.8,
      color       = "#FFFFFF",
      weight      = 0.2,
      opacity     = 0.4,
      highlightOptions = highlightOptions(
        weight = 2, color = "#1B2A4A", fillOpacity = 0.95, bringToFront = TRUE
      ),
      label = label_vals,
      labelOptions = labelOptions(
        style = list("font-size" = "12px", "border-radius" = "6px",
                     "padding" = "6px 10px"),
        direction = "auto"
      ),
      group = "datos"
    ) |>
    addLegend(
      pal      = pal,
      values   = mapa_sf[[capa]],
      title    = info$label,
      position = "bottomright",
      opacity  = 0.9,
      layerId  = "legend"
    )
}

crear_mapa_bivariado <- function(mapa_sf) {
  biv_colors <- get_bivar_colors(mapa_sf)
  label_vals <- sprintf(
    "<b>%s</b><br><b>Favorabilidad:</b> %.3f<br><b>Incertidumbre:</b> %.3f",
    mapa_sf$CUADRICULA, mapa_sf$F_final, mapa_sf$U_final
  ) |> lapply(htmltools::HTML)

  m <- leaflet(mapa_sf, options = leafletOptions(zoomControl = TRUE)) |>
    addProviderTiles("CartoDB.Positron") |>
    addPolygons(
      fillColor   = biv_colors,
      fillOpacity = 0.8,
      color       = "#FFFFFF",
      weight      = 0.2,
      opacity     = 0.4,
      highlightOptions = highlightOptions(
        weight = 2, color = "#1B2A4A", fillOpacity = 0.95, bringToFront = TRUE
      ),
      label = label_vals,
      labelOptions = labelOptions(
        style = list("font-size" = "12px", "border-radius" = "6px",
                     "padding" = "6px 10px"),
        direction = "auto"
      ),
      group = "datos"
    ) |>
    addControl(
      html = bivar_legend_html(),
      position = "bottomright"
    )

  m
}

actualizar_capa_mapa <- function(proxy, mapa_sf, capa) {
  if (capa == "bivariado") {
    biv_colors <- get_bivar_colors(mapa_sf)
    label_vals <- sprintf(
      "<b>%s</b><br><b>Favorabilidad:</b> %.3f<br><b>Incertidumbre:</b> %.3f",
      mapa_sf$CUADRICULA, mapa_sf$F_final, mapa_sf$U_final
    ) |> lapply(htmltools::HTML)

    proxy |>
      clearGroup("datos") |>
      removeControl("legend") |>
      addPolygons(
        data = mapa_sf, fillColor = biv_colors, fillOpacity = 0.8,
        color = "#FFFFFF", weight = 0.2, opacity = 0.4,
        highlightOptions = highlightOptions(
          weight = 2, color = "#1B2A4A", fillOpacity = 0.95, bringToFront = TRUE
        ),
        label = label_vals,
        labelOptions = labelOptions(
          style = list("font-size" = "12px", "border-radius" = "6px"),
          direction = "auto"
        ),
        group = "datos"
      ) |>
      addControl(
        html = bivar_legend_html(),
        position = "bottomright"
      )
    return(invisible(proxy))
  }

  pal <- get_pal(capa, mapa_sf)
  info <- CAPAS_INFO[[capa]]

  fill_vals  <- pal(mapa_sf[[capa]])
  label_vals <- sprintf(
    "<b>%s</b><br><b>%s:</b> %.3f",
    mapa_sf$CUADRICULA, info$label, mapa_sf[[capa]]
  ) |> lapply(htmltools::HTML)

  proxy |>
    clearGroup("datos") |>
    removeControl("legend") |>
    addPolygons(
      data = mapa_sf, fillColor = fill_vals, fillOpacity = 0.8,
      color = "#FFFFFF", weight = 0.2, opacity = 0.4,
      highlightOptions = highlightOptions(
        weight = 2, color = "#1B2A4A", fillOpacity = 0.95, bringToFront = TRUE
      ),
      label = label_vals,
      labelOptions = labelOptions(
        style = list("font-size" = "12px", "border-radius" = "6px"),
        direction = "auto"
      ),
      group = "datos"
    ) |>
    addLegend(
      pal = pal, values = mapa_sf[[capa]], title = info$label,
      position = "bottomright", opacity = 0.9, layerId = "legend"
    )
}
