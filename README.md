# Atlas de Distribucion de Murcielagos de la Peninsula Iberica

**Proyecto SECEMU** — Modelos de distribucion de ~30 especies de murcielagos a resolucion UTM 10x10 km.

Pipeline reproducible que combina modelos ambientales (GLM) con modelos espaciales (GAM), aplica transformacion de favorabilidad (Real et al. 2006) e interseccion fuzzy, con cuantificacion de incertidumbre multi-fuente.

---

## Tabla de contenidos

1. [Arquitectura general](#arquitectura-general)
2. [Datos de entrada](#datos-de-entrada)
3. [Fase 0 — Preparacion de datos](#fase-0--preparacion-de-datos)
4. [Fase 1 — Seleccion de variables](#fase-1--seleccion-de-variables)
5. [Fases 2-6 — Modelizacion](#fases-2-6--modelizacion)
6. [Fase 3-bis — Modelo espacial sobre residuos](#fase-3-bis--modelo-espacial-sobre-residuos)
7. [Fase 7 — Visualizacion](#fase-7--visualizacion)
8. [Resumen metodologico](#resumen-metodologico)
9. [Quick start](#quick-start)
10. [Estructura del repositorio](#estructura-del-repositorio)
11. [Sistema de validacion de datos](#sistema-de-validacion-de-datos)
12. [Optimizaciones implementadas](#optimizaciones-implementadas)
13. [Requisitos](#requisitos)
14. [Autores y citacion](#autores-y-citacion)

---

## Arquitectura general

El pipeline esta orquestado por `R/run_pipeline.R` y controlado desde un unico archivo de configuracion (`R/00_setup/00_config.R`). Todas las rutas, umbrales y parametros se definen ahi.

```
Fase 0: Preparacion datos  (01a-01h)       ──  8 scripts
Fase 1: Seleccion variables (02a-02d)      ──  4 scripts
Fase 2: Modelo ambiental    (03a)          ──  GLM + Favorabilidad + Bootstrap
Fase 3: Modelo espacial     (03b)          ──  GAM/GLM sobre PA, seleccion por AICc
  └ 3-bis: Espacial residuos (03b_bis)     ──  GAM sobre residuos del GLM (complementario)
Fase 4: Interseccion fuzzy  (03c)          ──  F = sqrt(F_amb x F_esp)
Fase 5: Validacion cruzada  (03d)          ──  CV espacial k-fold (k=5, 10 rep)
Fase 6: Incertidumbre       (03e)          ──  MESS + Bootstrap + Esfuerzo
Fase 7: Mapas atlas         (04a-04c)      ──  Paneles estilo SECEMU
```

Cada fase puede activarse/desactivarse en `CONFIG$control$ejecutar`. Cada especie genera su propia carpeta de resultados (`output/modelos/{especie}/`).

### Dependencias entre fases

| Fase | Requiere |
|------|----------|
| 0 (Preparacion) | Datos brutos en `data/raw/` |
| 1 (Seleccion) | Fase 0: `PAxENV_all_metodos.rds` |
| 2 (GLM ambiental) | Fase 1: JSONs con variables seleccionadas |
| 3 (GAM espacial) | Fase 2: `datos_entrenamiento.rds` |
| 4 (Fuzzy) | Fases 2 + 3: `bootstrap_samples.rds` |
| 5 (CV) | Fase 1: JSONs (independiente de fases 2-4) |
| 6 (Incertidumbre) | Fases 4 + 0: predicciones + esfuerzo muestreo |
| 7 (Mapas) | Fases 4 + 6: favorabilidad final + incertidumbre |

---

## Datos de entrada

Los datos brutos **no se incluyen** en el repositorio. Deben colocarse en `data/raw/`:

| Archivo | Ruta | Descripcion |
|---------|------|-------------|
| Presencias | `data/raw/presencias/*.csv` | Registros: especie, cuadricula UTM, metodologia |
| Malla Peninsula | `data/raw/shapefiles/Malla10x10_clip.shp` | Grid UTM 10x10 km (zona 30N) |
| Malla Baleares | `data/raw/shapefiles/Malla10x10_BAL_Clip_nueva.shp` | Grid UTM 10x10 km (zona 31N, reproyectado a 30N) |
| Variables EC | `data/raw/variables/Variables_EC.xlsx` | Variables ambientales Peninsula |
| Variables BAL | `data/raw/variables/Variables_BAL.xlsx` | Variables ambientales Baleares |
| Karst | `data/raw/variables/10x10_Karst_PIBAL.csv` | Indices karsticos por cuadricula |
| Litologia | `data/raw/variables/10x10_lito_COLOR_PIBAL.csv` | Clases litologicas por cuadricula |

Los metadatos ecologicos **si estan versionados** en `data/metadata/`:
- `especies_gremios.csv` — asignacion especie-gremio (refugio, alimentacion)
- `gremios_refugio.csv` / `gremios_alimentacion.csv` — variables prioritarias por gremio
- `complejos_taxonomicos.csv` — complejos de especies cripticas
- `diccionario_variables.csv` — diccionario de variables predictoras

---

## Fase 0 — Preparacion de datos

> Scripts: `R/01_data_preparation/01a` a `01h` | ~63 KB de codigo

Transforma los datos brutos en la matriz **PAxENV** (Presencia/Ausencia x Variables Ambientales), lista para modelizar.

| Script | Funcion | Entrada | Salida |
|--------|---------|---------|--------|
| **01a** | Presencias + complejos cripticos + PA por metodo | CSV presencias, complejos CSV | `pa_metodo.rds`, `muestras_metodo_wide.rds` |
| **01b** | Mallas UTM (Peninsula + Baleares) | Shapefiles | `malla_union.rds` (sf) |
| **01c** | Variables ambientales desde Excel | Excel EC + BAL | `predictores_seo.rds` |
| **01d** | Agrupacion CORINE (44 clases a 9 grupos) | predictores_seo | predictores_seo (actualizado) |
| **01e** | Geologia: Karst + Litologia + indices + PCA | CSV karst/lito | `geo_features.rds` |
| **01f** | Union predictores + z-score unificado | SEO + GEO + malla | `predictores_seo_geo.rds` |
| **01g** | PAxENV por metodo + formato ancho | PA + predictores | `PAxENV_*.rds`, `esfuerzo.rds` |
| **01h** | Mapas QA (opcional) | predictores_sf | PNGs de chequeo |

### Decisiones de diseno clave

- **Canarias (28R)** excluidas sistematicamente (diferente region biogeografica)
- **Baleares (zona 31N)** reproyectadas a zona 30N para coherencia espacial
- **Escalado z-score diferido** hasta 01f: se aplica sobre la union Peninsula + Baleares para que media y SD sean unificadas
- **Complejos cripticos**: especies indistinguibles por metodo se agrupan (ej. *Myotis myotis* + *M. blythii* = Myotis_grande)
- **Factor de esfuerzo** por cuadricula: 0 metodos = 1.0, 1 = 0.7, 2 = 0.5, 3+ = 0.3 (usado en Fase 6)

### Producto final de Fase 0

```
data/modelado_ready/
  PAxENV_acustica.rds        # Por metodo de muestreo
  PAxENV_captura.rds
  PAxENV_cuevas.rds
  PAxENV_otros.rds
  PAxENV_all_metodos.rds     # Formato ancho unificado (columnas sp_*)
  esfuerzo.rds               # n_metodos y factor_incert por cuadricula
```

---

## Fase 1 — Seleccion de variables

> Scripts: `R/02_variable_selection/02a` a `02d` | ~72 KB de codigo

Selecciona las variables predictoras optimas para cada especie, combinando criterios ecologicos y estadisticos.

### Sistema de gremios (2 ejes)

Las variables se priorizan segun la ecologia de cada especie:

| Eje | Categorias | Variables prioritarias (ejemplos) |
|-----|-----------|----------------------------------|
| **Refugio** | Cavernicola, Arboricola, Antropofilo, Fisuricola, Rupicola | Karst, CLC_bosques, CLC_urbano, CLC_rupicola |
| **Alimentacion** | Forestal, Ripario, Generalista, Mosaico, Pastizal, Aereo | CLC_bosques, CLC_acuatico, CLC_mosaico, CLC_pastizal |

Cada variable recibe una **prioridad** (4=nucleo, 3=climatica, 2=complementaria, 1=permitida) segun el cruce refugio x alimentacion de la especie. La clasificacion se lee de CSVs, no del codigo.

### Pipeline de 7 fases + 3 salvaguardas

| Fase | Nombre | Metodo | Criterio |
|------|--------|--------|----------|
| 1 | Preseleccion gremio | Ecologico | Eliminar variables con prioridad = 0 |
| 2 | Limpieza basica | QC | NA > 30%, varianza = 0, separacion perfecta |
| 3 | select07 ponderado | Correlacion | \|r\| > 0.8: eliminar variable de menor prioridad (Munoz & Real 2006) |
| 4 | VIF iterativo | Multicolinealidad | VIF > 10: eliminar variable de menor prioridad (Dormann et al. 2013) |
| 5 | Control muestral | Regla de Harrell | N/p >= 8; modelos simples (30-59 pres): max 5 vars |
| 6 | Validacion ecologica | Robustez | Asegurar >= 1 variable climatica y >= 2 de gremio |
| 7 | Validacion predictiva | k-fold CV (k=5) | AUC, TSS, Kappa sobre GLM binomial |

**Salvaguardas integradas:**
- **S1** (post-fase 3): Si quedan < 3 variables de gremio, rescatar las mejores eliminadas por AIC
- **S2** (post-fase 5): En modelos simples, intercambiar variables p=1 por variables de gremio excluidas
- **S3** (post-fase 6): Si falta variable climatica o de gremio, rescatar la mejor eliminada en fases 2-4

### Salida

Un JSON por especie en `output/seleccion_variables/variables_json/`:

```json
{
  "species": "Rhinolophus ferrumequinum",
  "gremio_refugio": "Cavernicola",
  "gremio_alimentacion": "Forestal",
  "n_presences": 245,
  "model_status": "modelo_completo",
  "variables_finales": [...],
  "variables_eliminadas": [...],
  "validation": { "AUC_mean": 0.82, "TSS_mean": 0.51 },
  "alerts": []
}
```

---

## Fases 2-6 — Modelizacion

> Scripts: `R/03_modeling/03a` a `03e` | ~24 KB de codigo

### Fase 2 — Modelo ambiental (03a)

GLM binomial con las variables seleccionadas en Fase 1.

```
Datos:     PAxENV filtrado a cuadriculas muestreadas
Split:     70% entrenamiento / 30% test (seed = 123)
Modelo:    glm(PA ~ var1 + var2 + ... + varN, family = binomial)
Transform: Favorabilidad (Real et al. 2006)
Bootstrap: 500 iteraciones con reemplazo
```

**Transformacion de favorabilidad**: corrige el sesgo de prevalencia del muestreo. Convierte la probabilidad logistica a una escala [0, 1] independiente de la proporcion presencias/ausencias en los datos de entrenamiento:

```
F = (P/(1-P)) / ((n1/n0) + P/(1-P))
```

**Salidas por especie:** predicciones (media, SD, IC 95%), coeficientes GLM, metricas hold-out (AUC, TSS), modelo RDS, matriz bootstrap.

### Fase 3 — Modelo espacial (03b)

Captura autocorrelacion espacial residual no explicada por el ambiente.

| Modelo candidato | Formula | Parametros |
|-----------------|---------|------------|
| GLM 2o orden | PA ~ X + Y + X^2 + Y^2 + XY | 5 |
| GLM 3er orden | PA ~ X + Y + ... + X^3 + Y^3 + X^2Y + XY^2 | 9 |
| GAM | PA ~ s(X, Y, k=30) | ~30 (spline) |

Seleccion automatica por **AICc** (criterio de Akaike corregido para muestras finitas). Bootstrap independiente (500 iter).

### Fase 4 — Interseccion fuzzy (03c)

Combina favorabilidad ambiental y espacial usando teoria de conjuntos difusos:

```
F_final = sqrt(F_ambiental * F_espacial)    # Media geometrica (por defecto)
```

Se aplica a **cada iteracion bootstrap** individualmente, propagando la incertidumbre de ambos modelos al resultado final.

### Fase 5 — Validacion cruzada espacial (03d)

Evaluacion independiente del poder predictivo:

```
Bloques:   k-means (k=5) sobre coordenadas UTM → folds espacialmente cohesivos
Modelo:    GLM ambiental reajustado en cada fold
Metricas:  AUC, TSS, Sensibilidad, Especificidad (media +/- SD)
```

Los bloques espaciales evitan estimaciones optimistas por autocorrelacion entre train y test.

### Fase 6 — Incertidumbre (03e)

Indice compuesto de incertidumbre con tres componentes:

```
U = 0.33 * MESS_norm + 0.33 * W_bootstrap_norm + 0.34 * factor_esfuerzo
```

| Componente | Que mide | Rango |
|-----------|----------|-------|
| **MESS** | Extrapolacion ambiental (distancia al rango de entrenamiento) | [0, 1]: 1 = extrapolacion extrema |
| **W_bootstrap** | Amplitud IC 95% de la favorabilidad (variabilidad del modelo) | [0, 1]: normalizado por max |
| **Factor esfuerzo** | Heterogeneidad en metodos de muestreo por cuadricula | [0.3, 1.0]: mas metodos = menos incertidumbre |

### Flujo de datos completo (Fases 2-6)

```
PAxENV + JSON variables
       |
       v
  [03a] GLM ambiental ──────> F_amb (500 bootstrap)
       |                              |
       | datos_entrenamiento           |
       v                              |
  [03b] GAM/GLM espacial ───> F_esp (500 bootstrap)
                                      |
                                      v
                         [03c] Fuzzy: F_final = sqrt(F_amb * F_esp)
                                      |
                                      v
                         [03e] U_final = MESS + W_boot + esfuerzo
                                      |
  [03d] CV espacial (independiente)    |
       |                              |
       v                              v
  metricas_cv.csv          predicciones + incertidumbre por cuadricula
```

---

## Fase 3-bis — Modelo espacial sobre residuos

> Script complementario: `R/03_modeling/03b_bis_espacial_residuos.R`

### Problema: doble conteo ambiental

En el pipeline estandar, **03a** modela PA ~ ambiente y **03b** modela PA ~ f(X,Y). Pero la PA ya contiene la senal ambiental. Al combinar ambas con fuzzy (F = sqrt(F_amb x F_esp)), la componente ambiental se cuenta dos veces: explicitamente en F_amb e implicitamente dentro de F_esp.

### Solucion: modelar residuos

```
residuos = PA - predict(GLM_ambiental, type = "response")
residuos ~ s(X, Y, k = k_adaptativo)     # family = gaussian
```

Los residuos capturan solo lo que el ambiente NO explica: dispersion limitada, barreras geograficas, refugios glaciares, historia biogeografica. Marco teorico: particion de varianza (Borcard, Legendre & Drapeau, 1992, *Ecology* 73:1045-1055).

### Cuando usar cada enfoque

| Situacion | Enfoque recomendado |
|-----------|-------------------|
| AUC ambiental > 0.8 | **Residuos** — el ambiente ya explica mucha varianza, el espacial estandar es redundante |
| Variables ambientales pobres | **PA directa** — mas robusto sin modelo ambiental fiable |
| Cuantificacion de incertidumbre | **Residuos** — componentes genuinamente independientes |
| Simplicidad | **PA directa** — pipeline estandar |

### Uso

- **Independiente**: `source("R/03_modeling/03b_bis_espacial_residuos.R")` despues de 03a. Guarda en `output/modelos/{especie}/espacial_residuos/` sin tocar el pipeline estandar. Incluye tabla comparativa AICc residuos vs PA directa.
- **Integrado**: `CONFIG$espacial$usar_residuos = TRUE` activa el enfoque en 03b directamente.

---

## Fase 7 — Visualizacion

> Scripts: `R/04_visualization/04a` a `04c` | ~9 KB de codigo

| Script | Funcion | Formato |
|--------|---------|---------|
| **04a** | Mapas atlas: panel 2x2 (favorabilidad + incertidumbre) estilo SECEMU | PNG 300 dpi |
| **04b** | Paneles de incertidumbre detallados (MESS, bootstrap, esfuerzo) | PNG 300 dpi |
| **04c** | Figuras resumen (riqueza, patrones multi-especie) | PNG 300 dpi |

Paletas colorblind-safe: `batlow` (favorabilidad), `lajolla` (incertidumbre). CRS de salida: ETRS89/UTM zona 30N (EPSG:25830).

---

## Resumen metodologico

| Componente | Metodo | Referencia |
|-----------|--------|------------|
| Modelo ambiental | GLM binomial + Favorabilidad | Real et al. (2006) |
| Modelo espacial | GAM/GLM seleccionado por AICc | Burnham & Anderson (2002) |
| Interseccion | Fuzzy geometrica | Acevedo & Real (2012) |
| Incertidumbre | MESS + Bootstrap + Esfuerzo | Elith et al. (2010) |
| Validacion | CV espacial k-fold con bloques k-means | Roberts et al. (2017) |
| Seleccion variables | select07 + VIF + Regla de Harrell + gremios | Munoz & Real (2006), Dormann et al. (2013) |
| Complejos cripticos | Agrupacion taxonomica configurable | — |
| Geologia | Karst + Litologia + Shannon H + PCA | — |
| CORINE | Agrupacion de 44 clases a 9 grupos ecologicos | — |

### Parametros principales (configurables en `00_config.R`)

| Parametro | Valor por defecto | Fase |
|-----------|-------------------|------|
| `correlation_threshold` | 0.8 | Seleccion (fase 3) |
| `vif_threshold` | 10 | Seleccion (fase 4) |
| `ratio_Np` | 8 | Seleccion (fase 5) |
| `min_presencias` | 30 | Seleccion + Modelado |
| `prop_train` | 0.70 | GLM ambiental |
| `n_bootstrap` | 500 | GLM ambiental + espacial |
| `k_gam` | 30 | GAM espacial |
| `metodo_fuzzy` | geometrica | Interseccion |
| `k_folds` | 5 | Validacion cruzada |
| `peso_mess / peso_bootstrap / peso_esfuerzo` | 0.33 / 0.33 / 0.34 | Incertidumbre |

---

## Quick start

```r
# 1. Clonar repositorio
# git clone https://github.com/gfandos/atlas-murcielagos-iberia.git

# 2. Restaurar paquetes
renv::restore()

# 3. Colocar datos brutos en data/raw/ (ver tabla de datos de entrada)

# 4. Configurar R/00_setup/00_config.R
#    - Verificar rutas
#    - Seleccionar fases a ejecutar (CONFIG$control$ejecutar)
#    - Para prueba rapida: CONFIG$especies$piloto = c("Rhinolophus ferrumequinum")

# 5. Ejecutar
source("R/run_pipeline.R")
```

Para modificar la clasificacion ecologica de una especie, editar `data/metadata/especies_gremios.csv`. Para anadir un complejo criptico, editar `data/metadata/complejos_taxonomicos.csv`. No es necesario tocar codigo R.

---

## Estructura del repositorio

```
atlas-murcielagos-iberia/
|
|-- R/
|   |-- run_pipeline.R                    # Script maestro
|   |-- 00_setup/
|   |   |-- 00_config.R                   # TODA la configuracion centralizada
|   |   +-- 00_packages.R                 # Gestion de dependencias
|   |-- 01_data_preparation/              # Fase 0: 8 scripts (01a-01h)
|   |-- 02_variable_selection/            # Fase 1: 4 scripts (02a-02d)
|   |-- 03_modeling/                      # Fases 2-6: 5 scripts + 1 complementario
|   |   |-- 03a_modelo_ambiental.R        # GLM + Favorabilidad + Bootstrap
|   |   |-- 03b_modelo_espacial.R         # GAM/GLM sobre PA directa
|   |   |-- 03b_bis_espacial_residuos.R   # GAM/GLM sobre residuos (complementario)
|   |   |-- 03c_interseccion_fuzzy.R      # F = sqrt(F_amb x F_esp)
|   |   |-- 03d_validacion_cv.R           # CV espacial k-fold
|   |   +-- 03e_incertidumbre.R           # MESS + Bootstrap + Esfuerzo
|   |-- 04_visualization/                 # Fase 7: 3 scripts (04a-04c)
|   +-- utils/                            # 9 modulos compartidos
|       |-- utils_checkpoints.R           # Checkpoints + normalizacion IDs + validar_n_cuadriculas
|       |-- utils_logging.R               # Logging centralizado (CSV estructurado)
|       |-- utils_favorabilidad.R         # Transformacion de favorabilidad
|       |-- utils_metricas.R              # AUC, TSS, sensibilidad, especificidad
|       |-- utils_mapas.R                 # Funciones de cartografia
|       |-- utils_corine.R               # Agrupacion CORINE Land Cover
|       |-- utils_geologia.R             # Karst + litologia + indices
|       |-- utils_litologia.R            # Procesado de litologia
|       +-- utils_pca_litologia.R        # PCA sobre clases litologicas
|
|-- data/
|   |-- raw/                              # Datos brutos (NO en Git)
|   |-- processed/                        # Intermedios (NO en Git)
|   |-- modelado_ready/                   # PAxENV listos (NO en Git)
|   +-- metadata/                         # Metadatos ecologicos (SI en Git)
|
|-- output/
|   |-- modelos/{especie}/                # Resultados por especie
|   |   |-- ambiental/                    # GLM + bootstrap
|   |   |-- espacial/                     # GAM/GLM + AICc
|   |   |-- interseccion/                 # Fuzzy final
|   |   |-- validacion/                   # CV espacial
|   |   +-- incertidumbre/                # Indice compuesto
|   |-- seleccion_variables/              # JSONs + diagnosticos
|   |-- figs/                             # Mapas y figuras
|   +-- logs/                             # Logs de ejecucion
|
|-- docs/                                 # Documentacion detallada por fase
|-- tests/                                # Tests reproducibles
|-- renv/                                 # Reproducibilidad de paquetes
|-- CITATION.cff                          # Formato de citacion
+-- LICENSE                               # CC-BY 4.0
```

---

## Sistema de validacion de datos

La preparacion de datos (Fase 0) incluye un sistema robusto de validacion para detectar errores silenciosos en joins y filtrados.

### Normalizacion de IDs de cuadricula

Cada fuente de datos (CSV, Excel, shapefile) puede usar un nombre diferente para la columna de cuadricula UTM (`CUADRICULA`, `cuadricula`, `UTMCODE`, `UTM_CODE`, `cuadricula_utm_10x10`, ...). La funcion `std_ids_tbl()` (en `utils_checkpoints.R`):

1. **Auto-detecta** la columna ID entre 14 candidatos conocidos
2. **Normaliza los valores**: mayusculas, sin espacios, trim (ej. `" 30s ve "` → `"30SVE"`)
3. **Renombra la columna** al nombre canonico (`CUADRICULA`) para garantizar que todos los joins funcionen

### Validaciones implementadas

| Punto | Script | Tipo | Que valida |
|-------|--------|------|-----------|
| Malla union | 01b | `validar_n_cuadriculas >= 5000` | La malla PI+BAL tiene ~5500 celdas |
| Variables EC | 01c | `validar_n_cuadriculas >= 5000` | Peninsula sin Canarias ~5300+ |
| Join karst+lito | utils_geologia | `stopifnot(nrow == n_pre)` | No se pierden ni duplican filas |
| Join geo+PCA | 01e | `stopifnot(nrow == n_pre)` | PCA no introduce duplicados |
| Join EC+GEO | 01f | Diagnostico IDs + `stopifnot` | Comprueba solapamiento ANTES del join |
| Join malla+pred | 01f | `stopifnot(nrow == n_malla)` | No se pierden cuadriculas |
| Predictores finales | 01f | `validar_n_cuadriculas >= 5000` | Control global post-escalado |
| Join PA+pred | 01g | Diagnostico IDs + `stopifnot` | Verifica >80% de IDs coinciden |
| Join compat+esfuerzo | 01g | `stopifnot(nrow == n_pre)` | Esfuerzo no duplica filas |
| PAxENV final | 01g | `validar_n_cuadriculas >= 5000` | Control global antes de guardar |

Cuando un join produce 0 coincidencias (IDs incompatibles), el pipeline se detiene inmediatamente con un mensaje diagnostico que muestra ejemplos de IDs de ambas tablas para facilitar la depuracion.

---

## Optimizaciones implementadas

### Prioridad alta

| ID | Descripcion | Fase | Estado |
|----|------------|------|--------|
| O1 | **Paralelizacion del loop de especies**: Loops de 03a y 03b refactorizados en funciones (`modelar_ambiental_sp`, `modelar_espacial_sp`) y ejecutados via `future_lapply` cuando `CONFIG$control$usar_parallel = TRUE`. Fallback secuencial automatico. | 2-3 | Implementado |
| O2 | **GAM k adaptativo**: `k = min(k_max, floor(n_pres / 4))` con suelo de 5. Activado via `CONFIG$espacial$k_gam_adaptativo = TRUE`. Evita sobreajuste en especies raras. | 3 | Implementado |
| O3 | **Repeticiones de CV**: `CONFIG$validacion$n_rep = 10` con semilla diferente por repeticion (`seed + rep_i - 1`). Metricas promediadas sobre 10 x 5 = 50 folds para mayor estabilidad. | 5 | Implementado |
| O4 | **Pesos de incertidumbre adaptativos**: Pesos proporcionales a la varianza de cada componente (MESS, bootstrap, esfuerzo). Activado via `CONFIG$incertidumbre$pesos_adaptativos = TRUE`. Fallback a pesos fijos si varianza total = 0. | 6 | Implementado |

### Prioridad media

| ID | Descripcion | Fase | Estado |
|----|------------|------|--------|
| O5 | **Logging en modelo ambiental**: `log_event()` integrado en todo el flujo de 03a (errores GLM, metricas AUC/TSS, checkpoints). Reemplaza `cat()` aislados. | 2 | Implementado |
| O6 | **Stability selection**: Bootstrap de `select07_weighted` (100 submuestras al 80%). Frecuencia de seleccion por variable guardada en JSON (`stability_freq`). Activado via `CONFIG$seleccion$stability_selection = TRUE`. | 1 | Implementado |
| O7 | **Logging centralizado**: Nuevo `utils_logging.R` con `init_log()`, `log_event()`, `read_log()`, `log_summary()`. Genera CSV estructurado con timestamp/fase/especie/nivel/mensaje. Integrado en `run_pipeline.R` y todas las fases de modelado. | Global | Implementado |
| O8 | **Validacion post-join**: `stopifnot()` tras cada `left_join()` critico en 01f (EC+GEO, malla+predictores) y 01g (PA+predictores). Avisos de NAs con conteo y porcentaje. | 0 | Implementado |

### Prioridad baja

| ID | Descripcion | Fase | Estado |
|----|------------|------|--------|
| O9 | **Consolidar filtrado Canarias**: Se filtra en 01a, 01b y 01c independientemente. Centralizar en un unico paso. | 0 | Pendiente |
| O10 | **Modelo de residuos espaciales (opcional)**: Toggle `CONFIG$espacial$usar_residuos = FALSE`. Si se activa, 03b modela los residuos del GLM ambiental en lugar de PA directamente. Desactivado por defecto para mantener independencia de fases. | 3 | Implementado (opcional) |
| O11 | **factor_incert configurable**: Umbrales movidos a `CONFIG$incertidumbre$factor_incert_umbrales` como vector nombrado. 01g lee de CONFIG en lugar de valores hardcoded. | 0 | Implementado |

---

## Requisitos

- **R** >= 4.1
- **Paquetes principales**: tidyverse, sf, terra, mgcv, pROC, car, MuMIn, scico, patchwork, rnaturalearth, rnaturalearthdata, readxl, jsonlite, FactoMineR, factoextra, future, future.apply
- **Gestion de versiones**: `renv` (ejecutar `renv::restore()` tras clonar)

---

## Autores y citacion

- **Guillermo Fandos** — UCM — gfandos@ucm.es (desarrollo del pipeline)
- **Elena Tena** — SECEMU (coordinacion cientifica)

**Licencia**: CC-BY 4.0

**Citacion**: Ver `CITATION.cff`.

---

## Documentacion adicional

Documentacion detallada por fase disponible en `docs/`:

- [`00_FLUJO_COMPLETO.md`](docs/00_FLUJO_COMPLETO.md) — Diagrama de dependencias y tiempos estimados
- [`01_PREPARACION_DATOS.md`](docs/01_PREPARACION_DATOS.md) — Detalles de carga y transformacion
- [`02_SELECCION_VARIABLES.md`](docs/02_SELECCION_VARIABLES.md) — Pipeline de 7 fases
- [`03_MODELIZACION.md`](docs/03_MODELIZACION.md) — GLM, GAM, fuzzy, bootstrap
- [`04_INCERTIDUMBRE.md`](docs/04_INCERTIDUMBRE.md) — MESS, bootstrap width, esfuerzo
- [`05_MAPAS_ATLAS.md`](docs/05_MAPAS_ATLAS.md) — Generacion de mapas y paneles
