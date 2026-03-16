# Atlas de Distribución de Murciélagos de la Península Ibérica

Pipeline reproducible de modelos de distribución de especies (SDM) para las **29 especies de murciélagos** de la Península Ibérica y Baleares, a resolución UTM 10×10 km.

Desarrollado en el marco del proyecto de Seguimiento y Atlas de Quirópteros del Ministerio para la Transición Ecológica (MITECO), coordinado por [SECEMU](https://secemu.org/project/seguimiento-de-fauna/) y Tragsatec, financiado por la UE-NextGenerationEU.

---

## Pipeline

El pipeline combina modelos ambientales (GLM) con modelos espaciales (GAM), aplica la transformación de favorabilidad (Real et al. 2006) y la intersección fuzzy, y cuantifica la incertidumbre multifuente.

```
Fase 0  Preparación de datos         ──  PAxENV por cuadrícula UTM 10×10 km
Fase 1  Selección de variables        ──  Stability selection + VIF + gremios ecológicos
Fase 2  Modelo ambiental              ──  GLM binomial → Favorabilidad (bootstrap 200 iter)
Fase 3  Modelo espacial               ──  GAM/GLM seleccionado por AICc (bootstrap 200 iter)
Fase 4  Intersección fuzzy            ──  F_final = √(F_amb × F_esp)
Fase 5  Validación cruzada espacial   ──  k-fold espacial (k=5, 10 rep)
Fase 6  Incertidumbre                 ──  MESS + Bootstrap CI + Esfuerzo de muestreo
Fase 7  Visualización                 ──  Mapas atlas, curvas de respuesta
```

Orquestado por `R/run_pipeline.R`, configurado desde `R/00_setup/00_config.R`. Cada especie genera su propia carpeta de resultados.

### Selección de variables

Las variables predictoras (~90 candidatas) se seleccionan individualmente para cada especie mediante un pipeline de 7 fases que combina criterios ecológicos (sistema de gremios refugio × alimentación) y estadísticos (correlación, VIF, regla de Harrell, stability selection con 100 submuestras bootstrap).

### Favorabilidad

La probabilidad logística se transforma en **favorabilidad ambiental** (Real et al. 2006), que corrige el sesgo de prevalencia y permite la comparación directa entre especies con diferentes proporciones de presencia/ausencia.

### Incertidumbre

Índice compuesto que integra tres fuentes: extrapolación ambiental (MESS), variabilidad entre modelos bootstrap (amplitud IC 95%) y esfuerzo de muestreo por cuadrícula.

### Mapa bivariado

Visualización 3×3 que cruza favorabilidad (baja/media/alta) con incertidumbre (baja/media/alta), permitiendo identificar las cuadrículas con predicciones más fiables.

---

## Metodología

| Componente | Método | Referencia |
|-----------|--------|------------|
| Modelo ambiental | GLM binomial + Favorabilidad | Real et al. (2006) |
| Modelo espacial | GAM/GLM, selección por AICc | Burnham & Anderson (2002) |
| Intersección | Fuzzy geométrica | Acevedo & Real (2012) |
| Incertidumbre | MESS + Bootstrap + Esfuerzo | Elith et al. (2010) |
| Validación | CV espacial k-fold (bloques k-means) | Roberts et al. (2017) |
| Selección de variables | Stability selection + VIF + gremios | Muñoz & Real (2006), Dormann et al. (2013) |

> **Ámbito geográfico:** Península Ibérica y Baleares. Las Islas Canarias no se incluyen debido a sus particularidades biogeográficas y diferente composición de especies.

---

## Quick start

```r
# 1. Restaurar paquetes
renv::restore()

# 2. Colocar datos brutos en data/raw/

# 3. Ejecutar pipeline completo
source("R/run_pipeline.R")

# 4. Solo tests (sin datos brutos)
source("tests/test_pipeline.R")
```

Los datos brutos no se incluyen en el repositorio. Los metadatos ecológicos (`data/metadata/`) sí están versionados.

---

## Estructura del repositorio

```
R/
├── run_pipeline.R                 # Script maestro
├── 00_setup/                      # Configuración centralizada
├── 01_data_preparation/           # Fase 0: datos brutos → PAxENV
├── 02_variable_selection/         # Fase 1: selección por especie
├── 03_modeling/                   # Fases 2-6: GLM, GAM, fuzzy, CV, incertidumbre
├── 04_visualization/              # Fase 7: mapas y curvas de respuesta
└── utils/                         # Módulos compartidos

shiny_atlas/                       # Aplicación Shiny interactiva
data/metadata/                     # Metadatos ecológicos (versionados)
docs/                              # Documentación detallada por fase
tests/                             # 40+ tests automatizados
```

Archivos auxiliares: `run_pipeline_2014.R` (pipeline temporal ≥2014), `preprocesar_output_shiny.R` (genera datos para la app Shiny).

---

## Aplicación Shiny

Aplicación interactiva para explorar los resultados: mapas Leaflet de favorabilidad e incertidumbre, tabla de variables del modelo, curvas de respuesta y mapa bivariado.

```r
shiny::runApp("shiny_atlas/")
```

---

## Autor

**Guillermo Fandos** — Dpto. Biodiversidad, Ecología y Evolución, Universidad Complutense de Madrid
*(desarrollo del pipeline, modelización y aplicación interactiva)*

## Equipo del Atlas

- **Elena Tena** — SECEMU (coordinación científica y datos)
- **Silvia María Cabezas León** — SECEMU (coordinación científica y datos)
- **Comisión SECEMU** (asesoramiento científico)

## Licencia

Código: MIT License · Datos y resultados: CC BY 4.0

Citación: ver `CITATION.cff`
