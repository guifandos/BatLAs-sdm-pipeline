# Auditoria Pre-Workflow: Atlas de Murcielagos de la Peninsula Iberica

> **Fecha**: 2026-02-16
> **Version auditada**: 1.0.0 (commit 328a4f9)
> **Objetivo**: Verificar que todo funciona, esta optimizado y es reproducible
> antes de lanzar el pipeline de modelizacion.

---

## Resumen Ejecutivo

| Categoria | Criticos | Medios | Bajos |
|-----------|----------|--------|-------|
| Configuracion y dependencias | 2 | 3 | 2 |
| Preparacion de datos (Fase 0) | 2 | 4 | 2 |
| Seleccion de variables (Fase 1) | 2 | 3 | 3 |
| Modelizacion (Fases 2-6) | 3 | 5 | 3 |
| Visualizacion (Fase 7) | 0 | 2 | 2 |
| Reproducibilidad | 3 | 2 | 1 |
| **TOTAL** | **12** | **19** | **13** |

---

## 1. CONFIGURACION Y DEPENDENCIAS

### 1.1 CRITICO: renv.lock no existe

**Problema**: El archivo `renv.lock` no existe en el repositorio. El paquete `renv`
esta listado en `00_packages.R` y el README menciona `renv::restore()`, pero sin el
lockfile no se puede restaurar el entorno exacto.

**Impacto**: Cualquier colaborador que clone el repositorio obtendra versiones
diferentes de los paquetes, haciendo los resultados no reproducibles.

**Solucion**: Ejecutar `renv::init()` y `renv::snapshot()` para generar `renv.lock`.

### 1.2 CRITICO: .gitkeep faltantes en directorios intermedios

**Problema**: `data/processed/.gitkeep` y `data/modelado_ready/.gitkeep` no existen,
pero `.gitignore` los excluye explicitamente con `!data/processed/.gitkeep`. Al clonar
el repositorio, estos directorios no se crearan.

**Impacto**: `run_pipeline.R` crea estos directorios (lineas 58-59) con
`dir.create(recursive=TRUE)`, por lo que el pipeline no falla. Pero es inconsistente
con la intencion del `.gitignore`.

**Solucion**: Crear los archivos `.gitkeep` faltantes.

### 1.3 MEDIO: Paquete `broom` no declarado en dependencias

**Problema**: `03a_modelo_ambiental.R:155` usa `broom::tidy()` pero `broom` no esta
en la lista de `paquetes_requeridos` en `00_packages.R`.

**Impacto**: Si `broom` no esta instalado, la fase 2 falla al guardar coeficientes
del GLM.

**Solucion**: Anadir `"broom"` a `paquetes_requeridos` en `00_packages.R`.

### 1.4 MEDIO: Ruta `variables_forestales` declarada pero nunca usada

**Problema**: `00_config.R:37` define `variables_forestales` pero ningun script lo
referencia. Es codigo muerto en la configuracion.

**Impacto**: Confunde a colaboradores que buscan donde se usan las variables
forestales.

**Solucion**: Eliminar la ruta si no se usa, o documentar que es para uso futuro.

### 1.5 MEDIO: Variables `LamArt_HISTO_1/2` referenciadas en metadata pero
inexistentes en el pipeline

**Problema**: `gremios_alimentacion.csv` lista `LamArt_HISTO_1,LamArt_HISTO_2` como
variables prioritarias para el gremio "Ripario", pero estas variables no existen en
ningun script R ni en el diccionario de variables (`diccionario_variables.csv`).

**Impacto**: Las especies riparias (M. daubentonii, M. capaccinii, P. pygmaeus) no
recibiran prioridad correcta para variables acuaticas durante la seleccion de
variables.

**Solucion**: Verificar si estas variables existen en los datos brutos Excel y
anadirlas al diccionario, o reemplazarlas por `CLC_acuatico` en
`gremios_alimentacion.csv`.

### 1.6 BAJO: `00_packages.R` no carga todos los paquetes usados

**Problema**: Solo carga explicitamente 7 de 18 paquetes con `library()`. Paquetes
como `car`, `MuMIn`, `readxl`, `FactoMineR`, `terra`, `future`, `future.apply` se
instalan pero no se cargan globalmente.

**Impacto**: Cada script que los necesita debe cargarlos individualmente, lo cual
funciona pero es propenso a errores si un script olvida hacerlo.

### 1.7 BAJO: Falta `.Rprofile` para activacion automatica de renv

**Problema**: No existe `.Rprofile` en la raiz del proyecto. Sin el, `renv` no se
activa automaticamente al abrir el proyecto.

---

## 2. PREPARACION DE DATOS (Fase 0)

### 2.1 CRITICO: `match()` puede introducir NAs silenciosos en 01a

**Archivo**: `R/01_data_preparation/01a_preparar_PA_metodo.R` (~linea 360)

**Problema**: El uso de `match()` para mapear especies a complejos cripticos puede
devolver `NA` si un nombre de especie no coincide exactamente. Estos NAs se propagan
silenciosamente al campo `especie_modelo`.

**Impacto**: Presencias de especies con nombres ligeramente diferentes (tildes,
espacios extra) se pierden silenciosamente.

**Solucion**: Anadir validacion post-match:
```r
n_na <- sum(is.na(datos$especie_modelo))
if (n_na > 0) {
  warning(sprintf("ATENCION: %d registros con especie_modelo = NA tras aplicar cripticos", n_na))
}
```

### 2.2 CRITICO: Perdida silenciosa de datos en 01f si IDs no coinciden al 80%

**Archivo**: `R/01_data_preparation/01f_unir_predictores.R` (~lineas 58-64)

**Problema**: Si solo el 80% de los IDs de PA coinciden con los predictores, el
script solo emite un warning pero continua. Esto puede resultar en la perdida del 20%
de los datos de presencia sin detener el pipeline.

**Impacto**: Modelos entrenados con datos incompletos, sesgando resultados.

**Solucion**: Convertir el warning en error o hacer el umbral configurable en CONFIG.

### 2.3 MEDIO: `pivot_wider()` sin deduplicacion en 01g

**Archivo**: `R/01_data_preparation/01g_crear_PAxENV_metodo.R` (~lineas 150-151)

**Problema**: `pivot_wider()` se usa sin verificar duplicados previos. Si hay filas
duplicadas (misma cuadricula + especie + metodo), `pivot_wider()` puede fallar o
perder datos.

**Solucion**: Anadir `distinct()` antes de `pivot_wider()` o verificar duplicados.

### 2.4 MEDIO: Comparacion fragil de CRS en 01b

**Archivo**: `R/01_data_preparation/01b_cargar_malla.R` (~linea 109)

**Problema**: La comparacion `st_crs(malla_bal) != st_crs(malla_pi)` es fragil porque
objetos CRS pueden representar la misma proyeccion con metadatos diferentes.

**Solucion**: Comparar codigos EPSG en lugar de objetos CRS completos.

### 2.5 MEDIO: Dos tablas PA creadas independientemente en 01g

**Archivo**: `R/01_data_preparation/01g_crear_PAxENV_metodo.R` (~lineas 197 vs 211)

**Problema**: `paxenv_all` y `pa_all_wide` se crean desde fuentes diferentes
(`paxenv_list` vs `pa_metodo` original). Podrian desincronizarse.

**Solucion**: Derivar `pa_all_wide` de `paxenv_all` en vez de recalcular.

### 2.6 MEDIO: Join failure enmascarado por `replace_na()` en 01g

**Archivo**: `R/01_data_preparation/01g_crear_PAxENV_metodo.R` (~linea 258)

**Problema**: El `left_join()` por `cuadricula_utm_10x10` puede fallar silenciosamente
si hay discrepancias entre tablas. Los NAs resultantes se rellenan con defaults,
enmascarando el fallo.

### 2.7 BAJO: Nombres de columna inconsistentes entre tablas

**Problema**: Algunas tablas usan `cuadricula_utm_10x10` (minusculas) y otras
`CUADRICULA` (mayusculas). Aunque `std_ids_tbl()` normaliza, la mezcla es propensa a
errores de mantenimiento.

### 2.8 BAJO: Rama litologia-only incompleta en 01e

**Archivo**: `R/01_data_preparation/01e_procesar_geologia.R` (~lineas 120-124)

**Problema**: Si solo existen datos de litologia (sin karst), la rama alternativa puede
omitir calculos intermedios (Shannon entropy rowwise) que si se ejecutan dentro de
`build_geo_features()`.

---

## 3. SELECCION DE VARIABLES (Fase 1)

### 3.1 CRITICO: Referencia a `tipo_base` antes de su definicion en 02a

**Archivo**: `R/02_variable_selection/02a_funciones_gremios.R` (~linea 519)

**Problema**: Cuando una especie no se encuentra en los metadatos, se crea un tibble
que referencia `tipo_base` en el calculo de `es_climatica`, pero `tipo_base` aun no
esta definida en ese punto del tibble.

**Impacto**: Produce NAs en la clasificacion climatica de variables, afectando las
salvaguardas ecologicas.

**Solucion**: Definir `tipo_base` antes del tibble o usar la fuente correcta.

### 3.2 CRITICO: Referencia a `f6` antes de su creacion en 02b

**Archivo**: `R/02_variable_selection/02b_pipeline_seleccion.R` (~linea 637)

**Problema**: La condicion `nrow(f6$var_info) > 0` se evalua antes de que `f6` sea
computado por `fase6_control_ecologico()`.

**Impacto**: Error de ejecucion que detiene la seleccion de variables para todas las
especies.

### 3.3 MEDIO: `vars_eliminadas_todas` no incluye f5$removed en 02b

**Archivo**: `R/02_variable_selection/02b_pipeline_seleccion.R` (~linea 630)

**Problema**: La lista de variables eliminadas para rescate solo incluye f2-f4 pero
no f5, creando un pool de rescate incompleto.

### 3.4 MEDIO: `fromJSON()` sin error handling en 02c y 02d

**Archivos**: `02c_diagnostico.R:56`, `02d_ejecutar_seleccion.R:42`

**Problema**: La lectura de JSONs y RDS no esta envuelta en `tryCatch()`. Un archivo
corrupto detiene todo el diagnostico.

### 3.5 MEDIO: NULL dereference en info$validation en 02c

**Archivo**: `R/02_variable_selection/02c_diagnostico.R` (~lineas 78-80)

**Problema**: Accede a `info$validation$AUC_mean` sin verificar primero si
`info$validation` es NULL.

### 3.6 BAJO: Codigo muerto - variable `use_modeva` en 02b

**Archivo**: `R/02_variable_selection/02b_pipeline_seleccion.R` (~lineas 33-38)

**Problema**: Se crea `use_modeva` flag pero nunca se referencia en el codigo.

### 3.7 BAJO: Duplicacion de escritura CSV entre 02c y 02d

**Problema**: Tanto `02c_diagnostico.R` como `02d_ejecutar_seleccion.R` escriben
`resumen_seleccion.csv`, pudiendo sobreescribirse mutuamente.

### 3.8 BAJO: Patron `str_replace_all(sp, " ", "_")` duplicado

**Problema**: La conversion de nombre de especie a nombre de archivo esta duplicada
en multiples archivos. Deberia ser una funcion en `utils_checkpoints.R`.

---

## 4. MODELIZACION (Fases 2-6)

### 4.1 CRITICO: Division por cero en calculo de incertidumbre (03e)

**Archivo**: `R/03_modeling/03e_incertidumbre.R` (~linea 119)

**Problema**: `W_norm <- W_boot / max(W_boot, na.rm=TRUE)`. Si todos los valores de
bootstrap width son 0 (modelo sin variabilidad), `max()` retorna 0 y se produce
division por cero, generando `Inf` en el indice de incertidumbre.

**Impacto**: Mapas de incertidumbre con valores infinitos. Puede propagar a
visualizacion.

**Solucion**:
```r
max_W <- max(W_boot, na.rm = TRUE)
W_norm <- if (max_W > 0) W_boot / max_W else rep(0, length(W_boot))
```

### 4.2 CRITICO: Threshold de min_presencias inconsistente en 03d

**Archivo**: `R/03_modeling/03d_validacion_cv.R` (~linea 64)

**Problema**: Usa un valor hardcoded de 10 como minimo de presencias, mientras que
`CONFIG$ambiental$min_presencias = 30`. Esto permite que la validacion cruzada procese
especies que fueron rechazadas por el modelo ambiental.

**Impacto**: Resultados de CV para especies con <30 presencias que no tienen modelo,
creando inconsistencia.

**Solucion**: Usar `CONFIG$ambiental$min_presencias` en lugar del valor hardcoded.

### 4.3 CRITICO: Truncado silencioso de matrices bootstrap en 03c

**Archivo**: `R/03_modeling/03c_interseccion_fuzzy.R` (~linea 70)

**Problema**: Si las matrices de bootstrap ambiental y espacial tienen diferente
numero de columnas (p.ej., una tiene 500 y otra 498 por fallos en iteraciones),
el codigo trunca silenciosamente al minimo sin avisar.

**Impacto**: Perdida de iteraciones bootstrap sin registro.

**Solucion**: Anadir log_event() cuando las dimensiones difieren.

### 4.4 MEDIO: Train/test split no estratificado en 03a

**Archivo**: `R/03_modeling/03a_modelo_ambiental.R` (~lineas 88-93)

**Problema**: El split 70/30 usa `sample()` simple sin estratificar por
presencia/ausencia. Con prevalencia baja (<10%), el test set puede no tener
presencias suficientes.

**Solucion**: Usar muestreo estratificado (separar presencias y ausencias,
muestrear 70% de cada grupo).

### 4.5 MEDIO: `readRDS()`/`fromJSON()` sin error handling en multiples scripts

**Archivos afectados**: 03a, 03b, 03c, 03d, 03e

**Problema**: Lectura de archivos intermedios sin `tryCatch()`. Un archivo corrupto
detiene el pipeline completo.

### 4.6 MEDIO: `rowMeans()` produce NaN en vez de NA en 03a

**Archivo**: `R/03_modeling/03a_modelo_ambiental.R` (~linea 147)

**Problema**: `rowMeans(boot_matrix, na.rm=TRUE)` retorna `NaN` (no NA) si toda la
fila es NA. Esto puede causar problemas downstream donde se filtra por `is.na()`.

### 4.7 MEDIO: kmeans puede fallar con pocas observaciones en 03d

**Archivo**: `R/03_modeling/03d_validacion_cv.R` (~linea 76)

**Problema**: `kmeans(coords, centers=5)` falla si hay menos de 5 observaciones.
No hay `tryCatch()` ni verificacion de `n >= k_folds`.

### 4.8 MEDIO: Normalizacion MESS con divisor hardcoded en 03e

**Archivo**: `R/03_modeling/03e_incertidumbre.R` (~linea 115)

**Problema**: `mess_norm <- pmin(pmax(-mess_vals / 100, 0), 1)` usa 100 como
divisor hardcoded. Este valor no esta en CONFIG ni documentado.

### 4.9 BAJO: Umbral AUC hardcoded en 04c

**Archivo**: `R/04_visualization/04c_figuras_resumen.R` (~linea 68)

**Problema**: `geom_hline(yintercept = 0.7)` usa 0.7 como referencia AUC sin
parametrizar.

### 4.10 BAJO: Dimensiones de mapa hardcoded en 04a

**Archivo**: `R/04_visualization/04a_mapas_atlas.R` (~linea 93)

**Problema**: Usa dimensiones fijas de 24x20 cm en vez de CONFIG$mapas$ancho_cm y
CONFIG$mapas$alto_cm.

### 4.11 BAJO: Validacion incompleta de archivos en 04a

**Archivo**: `R/04_visualization/04a_mapas_atlas.R` (~linea 70)

**Problema**: Verifica existencia de interseccion e incertidumbre pero no del modelo
ambiental antes de intentar leer sus predicciones.

---

## 5. REPRODUCIBILIDAD

### 5.1 CRITICO: Sin renv.lock - Entorno no reproducible

**Estado actual**: `renv` esta como dependencia pero no hay `renv.lock` ni `renv/`
en el repositorio.

**Impacto**: Imposible garantizar que dos ejecuciones del pipeline usen exactamente
las mismas versiones de paquetes.

**Accion requerida**:
1. Ejecutar `renv::init()` en el proyecto
2. Ejecutar `renv::snapshot()` para generar `renv.lock`
3. Verificar que `renv.lock` esta en el repositorio (no en `.gitignore`)

### 5.2 CRITICO: Tests incompletos

**Archivo**: `tests/test_pipeline.R`

**Problemas identificados**:
- Solo testa 5 funciones de ~30+ funciones en el pipeline
- No testa el flujo completo (end-to-end con datos simulados)
- No testa seleccion de variables (02b)
- No testa modelo espacial (03b)
- No testa interseccion fuzzy (03c)
- No testa incertidumbre (03e)
- No testa lectura/escritura de checkpoints
- No verifica configuracion con `validar_config()`
- Usa `source()` relativo: requiere ejecutarse desde la raiz del proyecto

**Impacto**: Cambios en funciones clave pueden introducir regresiones sin deteccion.

### 5.3 CRITICO: Flujo documentado vs flujo real inconsistente

**Archivo**: `docs/00_FLUJO_COMPLETO.md`

**Inconsistencias encontradas**:

| Docs dice | Codigo real |
|-----------|-------------|
| 01b: Cargar variables | 01b: Cargar **malla** UTM |
| 01c: Agrupar CORINE | 01c: Cargar variables Excel |
| 01d: Procesar geologia | 01d: Agrupar CORINE |
| 01e: Crear matriz PA | 01e: Procesar geologia |
| 01f: Separar por metodo | 01f: Unir predictores |
| (no mencionado) | 01g: Crear PAxENV por metodo |
| (no mencionado) | 01h: Mapas de chequeo (QA) |

**Impacto**: Documentacion confusa para colaboradores.

### 5.4 MEDIO: Sin CI/CD (GitHub Actions)

**Problema**: No hay archivos `.github/workflows/` para ejecucion automatizada de
tests ni verificacion de sintaxis R.

**Impacto**: Los errores de sintaxis o regresiones solo se detectan manualmente.

### 5.5 MEDIO: `CONFIG$control$ejecutar` tiene fases 0-1 desactivadas por defecto

**Archivo**: `R/00_setup/00_config.R` (lineas 248-249)

**Problema**: Las fases 0 (preparacion) y 1 (seleccion) estan desactivadas (`FALSE`)
por defecto, pero las fases 2-7 estan activadas. Un usuario nuevo que ejecute
`source("R/run_pipeline.R")` saltara la preparacion de datos e intentara modelar
sin datos procesados, lo que fallara.

**Solucion**: O activar todas las fases por defecto, o anadir verificacion en
run_pipeline.R de que los datos procesados existen si las fases 0-1 estan
desactivadas.

### 5.6 BAJO: Semilla diferente para cada CV repeticion

**Problema**: La validacion cruzada usa `seed + rep` como semilla (linea ~68 de 03d),
lo cual es correcto y reproducible, pero no esta documentado explicitamente.

---

## 6. CONSISTENCIA DE METADATOS

### 6.1 Especies modelables vs metadata

| Especie | `modelar` | Nota |
|---------|-----------|------|
| Plecotus teneriffae | FALSE | Solo 15 cuadriculas (< min_presencias=30) |
| Pipistrellus maderensis | FALSE | Criptica, solo genetica |
| Restantes 32 | TRUE | |

**Verificacion**: Los 5 complejos cripticos estan correctamente definidos en
`complejos_taxonomicos.csv` y cada especie miembro tiene la columna `complejo`
correcta en `especies_gremios.csv`.

### 6.2 Categorias de gremio consistentes

| Tipo | Categorias en CSV | Referenciadas en codigo |
|------|-------------------|------------------------|
| Refugio | Cavernicola, Arboricola, Antropofilo, Fisuricola, Rupicola | OK |
| Alimentacion | Forestal, Ripario, Generalista, Mosaico, Pastizal, Aereo | OK |

**Problema detectado**: `gremios_alimentacion.csv` incluye `LamArt_HISTO_1,
LamArt_HISTO_2` en el gremio Ripario. Estas variables **no existen** en:
- `diccionario_variables.csv`
- Ningun script R del pipeline
- Los predictores SEO (Excel)

**Impacto**: El sistema de gremios asignara prioridad a variables fantasma para
3 especies riparias.

---

## 7. OPTIMIZACION

### 7.1 Cosas bien hechas

- Paralelizacion con `future_lapply` disponible y configurable
- k adaptativo para GAM (`k = min(k_gam, floor(n_pres/4))`)
- Checkpoints por especie/fase evitan recalculos
- Logging centralizado en CSV
- Pesos de incertidumbre adaptativos (proporcional a varianza)
- Config centralizada en un solo archivo

### 7.2 Oportunidades de mejora

1. **Memory**: `01c` almacena duplicados `ec` + `ec_raw` y `bal` + `bal_raw`
innecesariamente en memoria. Eliminar las copias `_raw` despues de procesar.

2. **I/O redundante**: `01g` crea `paxenv_all` y `pa_all_wide` independientemente
desde fuentes distintas. Derivar uno del otro ahorraria procesamiento.

3. **Bootstrap**: Con n_bootstrap=500 y ~25 especies, las fases 2-3 generan ~25,000
ajustes de modelo. La paralelizacion esta disponible pero desactivada por defecto.
Documentar el uso recomendado de `CONFIG$control$n_cores`.

---

## 8. CHECKLIST DE ACCIONES REQUERIDAS

### Antes de ejecutar el pipeline (CRITICAS)

- [ ] **Crear renv.lock**: `renv::init() ; renv::snapshot()`
- [ ] **Corregir `gremios_alimentacion.csv`**: Reemplazar `LamArt_HISTO_1,
  LamArt_HISTO_2` por variables que existan (e.g., `CLC_acuatico`)
- [ ] **Anadir `broom`** a `paquetes_requeridos` en `00_packages.R`
- [ ] **Crear `.gitkeep`** en `data/processed/` y `data/modelado_ready/`
- [ ] **Corregir docs/00_FLUJO_COMPLETO.md** para que coincida con el codigo real
- [ ] **Verificar fases activadas**: Si datos brutos disponibles, activar fases 0-1
  en CONFIG. Si no, verificar que los datos procesados existen.

### Antes de publicar resultados (MEDIAS)

- [ ] Anadir `tryCatch()` a lecturas criticas de `fromJSON()` y `readRDS()`
- [ ] Corregir division por cero en `03e_incertidumbre.R`
- [ ] Usar `CONFIG$ambiental$min_presencias` en `03d_validacion_cv.R`
- [ ] Anadir validacion post-match en `01a` para detectar NAs en complejos
- [ ] Estratificar train/test split en `03a`
- [ ] Anadir log cuando bootstrap matrices se truncan en `03c`
- [ ] Eliminar ruta `variables_forestales` no utilizada de CONFIG

### Mejoras recomendadas (BAJAS)

- [ ] Expandir test suite con tests para fases 1-6
- [ ] Crear GitHub Actions para CI basico (syntax check + tests)
- [ ] Extraer `str_replace_all(sp, " ", "_")` a funcion utilitaria
- [ ] Unificar nomenclatura `cuadricula_utm_10x10` / `CUADRICULA`
- [ ] Parametrizar umbrales hardcoded (AUC=0.7, MESS/100, mapa 24x20 cm)

---

## 9. VERIFICACION DE INTEGRIDAD DE DATOS

### Archivos de metadatos (versionados - verificados OK)

| Archivo | Filas | Columnas | Estado |
|---------|-------|----------|--------|
| `especies_gremios.csv` | 34 | 6 | OK (31 modelables + 2 excluidas + header) |
| `gremios_refugio.csv` | 6 | 3 | OK (5 categorias + header) |
| `gremios_alimentacion.csv` | 7 | 3 | ALERTA (variables fantasma, ver 6.2) |
| `complejos_taxonomicos.csv` | 6 | 4 | OK (5 complejos + header) |
| `diccionario_variables.csv` | 25 | 5 | OK (24 variables + header) |

### Coherencia interna de metadatos

- Todas las especies en `complejos_taxonomicos.csv` existen en
  `especies_gremios.csv`: **OK**
- Todas las categorias de refugio en `especies_gremios.csv` existen en
  `gremios_refugio.csv`: **OK**
- Todas las categorias de alimentacion en `especies_gremios.csv` existen en
  `gremios_alimentacion.csv`: **OK**
- Variables en `gremios_refugio.csv` existen en `diccionario_variables.csv`: **OK**
- Variables en `gremios_alimentacion.csv` existen en `diccionario_variables.csv`:
  **FALLO** (LamArt_HISTO_1, LamArt_HISTO_2)

---

## 10. ESTADO DE LA DOCUMENTACION

| Documento | Estado | Notas |
|-----------|--------|-------|
| README.md | Completo | 25 KB, bien estructurado |
| CITATION.cff | OK | Version 1.0.0, autores correctos |
| LICENSE | OK | CC-BY 4.0 |
| docs/00_FLUJO_COMPLETO.md | **INCORRECTO** | No coincide con scripts reales |
| docs/01_PREPARACION_DATOS.md | OK | |
| docs/02_SELECCION_VARIABLES.md | OK | |
| docs/03_MODELIZACION.md | OK | |
| docs/04_INCERTIDUMBRE.md | OK | |
| docs/05_MAPAS_ATLAS.md | OK | |
| docs/referencias.bib | OK | |
| R/01_data_preparation/README.md | OK | |
