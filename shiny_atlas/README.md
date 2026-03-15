# Atlas de Murciélagos Ibéricos — Shiny App

Visualización interactiva de los modelos de distribución de especies (SDM) del Atlas SECEMU.

## Requisitos

```r
install.packages(c("shiny", "bslib", "shinyWidgets", "tidyverse",
                    "sf", "leaflet", "DT", "tippy", "scales"))
```

## Ejecución

Desde la raíz del proyecto:

```r
shiny::runApp("shiny_atlas")
```

## Datos

La app lee datos pregenerados de `output_shiny/`. No recalcula nada.
Para regenerar los datos: `source("preprocesar_output_shiny.R")`

## Estructura

- **Tab 1 - Distribución**: Mapa leaflet interactivo (favorabilidad, incertidumbre, MESS)
- **Tab 2 - Modelo**: Forest plot de coeficientes GLM + tabla + métricas CV
- **Tab 3 - Curvas de respuesta**: Curvas parciales de probabilidad y favorabilidad
- **Tab 4 - Comparativa**: Matriz de gremios, barplot AUC, tabla comparativa
