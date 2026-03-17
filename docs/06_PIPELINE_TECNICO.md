# Documentación Técnica del Pipeline

Referencia técnica completa del pipeline de modelización de distribución de especies (SDM) del Atlas de Murciélagos de la Península Ibérica. Para una visión general, consultar el [README](../README.md) y el [flujo completo](00_FLUJO_COMPLETO.md).

---

## Índice

1. [Parámetros de configuración](#1-parámetros-de-configuración)
2. [Selección de variables](#2-selección-de-variables)
3. [Transformación de favorabilidad](#3-transformación-de-favorabilidad)
4. [Modelo ambiental (GLM)](#4-modelo-ambiental-glm)
5. [Modelo espacial (GAM/GLM)](#5-modelo-espacial-gamglm)
6. [Intersección fuzzy](#6-intersección-fuzzy)
7. [Validación cruzada espacial](#7-validación-cruzada-espacial)
8. [Índice de incertidumbre](#8-índice-de-incertidumbre)
9. [Sistema de gremios ecológicos](#9-sistema-de-gremios-ecológicos)
10. [Salvaguardas y validaciones](#10-salvaguardas-y-validaciones)
11. [Estructura de salidas](#11-estructura-de-salidas)
12. [Sistema de tests](#12-sistema-de-tests)
13. [Tabla resumen de parámetros](#13-tabla-resumen-de-parámetros)

---

## 1. Parámetros de configuración

Toda la configuración se centraliza en `R/00_setup/00_config.R`. Los valores principales:

### Bootstrap y validación

| Parámetro | Valor (producción) | Valor (test) |
|-----------|-------------------|--------------|
| Iteraciones bootstrap | 200 | 50 |
| Split train/test | 70/30 | 70/30 |
| k-folds CV | 5 | 5 |
| Repeticiones CV | 10 | 10 |
| Método bloques CV | k-means espacial | k-means espacial |

### Selección de variables

| Parámetro | Valor | Referencia |
|-----------|-------|------------|
| Umbral correlación (Spearman) | 0.80 | Muñoz & Real (2006) |
| Umbral VIF | 10 | Dormann et al. (2013) |
| Ratio mínimo N/p | 8 | Regla de Harrell |
| Mín. variables de gremio | 2 | — |
| Mín. presencias para modelizar | 30 | — |
| Máx. variables (modelo reducido, 30-59 pres.) | 5 | — |
| Iteraciones stability selection | 100 | — |
| Umbral frecuencia stability | 0.60 | — |

### Modelo espacial

| Parámetro | Valor |
|-----------|-------|
| Métodos comparados | GLM2 (polinomial 2º), GLM3 (3º), GAM (tensor) |
| k máximo GAM | 30 |
| k adaptativo | `min(k_gam, floor(n_pres/4))`, mínimo 5 |
| Criterio selección | AICc |

### Incertidumbre

| Parámetro | Valor |
|-----------|-------|
| Pesos fijos | MESS=0.33, Bootstrap=0.33, Esfuerzo=0.34 |
| Umbral MESS (extrapolación) | −10 |
| Factor esfuerzo (0 métodos) | 1.0 |
| Factor esfuerzo (1 método) | 0.7 |
| Factor esfuerzo (2 métodos) | 0.5 |
| Factor esfuerzo (3+ métodos) | 0.3 |

### CRS y visualización

- **CRS de salida:** ETRS89/UTM 30N (EPSG:25830)
- **Paleta favorabilidad:** batlow
- **Paleta incertidumbre:** lajolla
- **DPI mapas:** 300
- **Dimensiones:** 20×20 cm

---

## 2. Selección de variables

Pipeline de 7 fases que combina criterios ecológicos y estadísticos. Se ejecuta independientemente para cada especie.

### Fase 1: Preselección por gremio

Filtra las ~90 variables candidatas según el gremio de refugio y alimentación de la especie. Solo pasan variables con `prioridad > 0`.

### Fase 2: Limpieza básica

- Elimina variables con >30% datos faltantes
- Elimina variables constantes o casi-constantes (varianza < 1e-10)
- Elimina variables categóricas
- Detecta separación perfecta/cuasi-completa (problema de convergencia GLM)

### Fase 3: Select07 ponderado + Salvaguarda 1

Algoritmo de Muñoz & Real (2006): selección por correlación de Spearman, ordenando variables por (1) prioridad de gremio descendente y (2) AIC univariante ascendente. Umbral: |r| < 0.80.

**Salvaguarda 1:** Si quedan menos de `min_gremio` variables de gremio tras select07, se reintroducen las mejores (por AIC) variables de gremio eliminadas.

### Fase 4: VIF iterativo ponderado

Eliminación iterativa de variables con VIF > 10, priorizando la eliminación de variables de baja prioridad ecológica. Si todas son de alta prioridad, se elimina la de peor AIC.

### Fase 5: Control de muestreo + Salvaguarda 2

Aplica la regla de Harrell: máximo `floor(n_pres / 8)` variables. Para especies con 30-59 presencias, máximo 5 variables.

**Salvaguarda 2:** En modelos reducidos, intercambia variables de baja prioridad (p=1) por variables de gremio (p≥2) para garantizar relevancia ecológica.

### Fase 6: Validación ecológica + Salvaguarda 3

Verifica que el modelo final contenga:
- Al menos una variable climática
- Al menos una variable de gremio (prioridad ≥2)
- Al menos una variable nuclear del gremio (prioridad=4) si existe

**Salvaguarda 3:** Rescata variables climáticas o de gremio del pool de eliminadas si faltan.

### Fase 7: Validación predictiva

Evaluación k-fold (k=5) con AUC, TSS y Kappa. Máximo 15 variables para evitar sobreajuste en validación.

### Sistema de prioridades

```
Prioridad 4: Variables nucleares del gremio (esenciales)
Prioridad 3: Variables climáticas/base (siempre relevantes)
Prioridad 2: Variables complementarias del gremio
Prioridad 1: Variables permitidas (baja relevancia ecológica)
Prioridad 0: Excluidas a priori (ecológicamente irrelevantes)
```

---

## 3. Transformación de favorabilidad

Transforma la probabilidad logística en favorabilidad ambiental (Real et al. 2006), corrigiendo el sesgo de prevalencia:

```
F = odds / (prevalencia + odds)

donde:
  odds = prob / (1 - prob)
  prevalencia = n_presencias / n_ausencias
```

La favorabilidad se acota en [0, 1] y los NAs se reemplazan por 0. Esto permite la comparación directa entre especies con diferentes proporciones de presencia/ausencia.

**Transformación inversa:**
```
prob = (F × prevalencia) / (1 - F + F × prevalencia)
```

---

## 4. Modelo ambiental (GLM)

### Especificación

```r
PA ~ var1 + var2 + ... + varn
family = binomial(link = "logit")
```

### Proceso

1. **Split estratificado** train/test (70/30) sobre presencias y ausencias por separado
2. **Ajuste GLM** binomial sobre datos de entrenamiento
3. **Predicción** sobre el conjunto test → probabilidad → favorabilidad
4. **Métricas** de discriminación (AUC, TSS) en test
5. **Bootstrap** (200 iteraciones): remuestreo con reemplazo del set de entrenamiento
6. **Imputación:** NAs en predicciones del grid rellenados con medianas del set de entrenamiento

### Salidas

| Variable | Descripción |
|----------|-------------|
| `F_glm_mean` | Media de favorabilidad bootstrap |
| `F_glm_sd` | SD entre iteraciones bootstrap |
| `q025`, `q975` | Percentiles 2.5 y 97.5 (IC 95%) |
| `W_glm` | Amplitud bootstrap = q975 − q025 |

---

## 5. Modelo espacial (GAM/GLM)

### Tres métodos comparados por AICc

```
GLM2:  PA ~ X + Y + X² + Y² + X×Y                              [polinomial 2º orden]
GLM3:  PA ~ X + Y + X² + Y² + X×Y + X³ + Y³ + X²×Y + X×Y²     [polinomial 3er orden]
GAM:   PA ~ s(X, Y, k=k_gam)                                    [producto tensor suavizado]
```

El valor de k para el GAM se adapta al tamaño muestral: `k = min(30, floor(n_pres/4))`, con mínimo 5.

Se selecciona el método con menor AICc (Burnham & Anderson 2002) y se aplica bootstrap de 200 iteraciones.

### Enfoque alternativo: residuos del modelo ambiental

El script `03b_bis_espacial_residuos.R` implementa un enfoque que modela los residuos del GLM ambiental (`PA - prob_ambiental`) en lugar de la PA directa, usando `family = gaussian`. Esto evita el doble conteo de la señal ambiental en la intersección fuzzy, ya que el modelo espacial solo captura la estructura geográfica residual (dispersión, barreras, historia biogeográfica).

Se activa con `CONFIG$espacial$usar_residuos = TRUE` o ejecutando `03b_bis` de forma independiente. El script incluye diagnósticos de residuos y comparación AICc entre ambos enfoques por especie. El enfoque de residuos es preferible cuando el AUC ambiental es alto (>0.8); el enfoque estándar (PA directa) es más robusto cuando el modelo ambiental es débil.

Marco teórico: partición de la variación espacial (Borcard et al. 1992, Legendre & Legendre 2012). Ver `docs/03_MODELIZACION.md` para la justificación detallada.

---

## 6. Intersección fuzzy

Combina las predicciones ambiental y espacial mediante el operador fuzzy geométrico (Acevedo & Real 2012):

```
F_final = √(F_ambiental × F_espacial)
```

**Operadores alternativos** (configurables):

| Operador | Fórmula | Carácter |
|----------|---------|----------|
| Geométrico (defecto) | `√(F_amb × F_esp)` | Conservador |
| Mínimo (pmin) | `min(F_amb, F_esp)` | Muy conservador |
| Compensatorio | `(F_amb^γ + F_esp^γ) / 2`, γ=0.5 | Menos conservador |

El operador se aplica a cada par de muestras bootstrap (b=1..200), calculando media, SD y percentiles del resultado.

---

## 7. Validación cruzada espacial

### Bloques espaciales

Los bloques se generan por k-means clustering sobre las coordenadas (X, Y), evitando la autocorrelación espacial entre conjuntos de entrenamiento y test.

### Protocolo

```
Para cada repetición r = 1..10:
  seed = seed_base + r - 1
  bloques = kmeans(coordenadas, k=5, nstart=25)

  Para cada fold i = 1..5:
    train = bloques ≠ i
    test  = bloques = i
    Ajustar GLM en train
    Predecir en test
    Calcular AUC, TSS, Kappa

Resultado: media ± SD de las 50 evaluaciones (5 folds × 10 repeticiones)
```

### Métricas

| Métrica | Rango | Interpretación |
|---------|-------|----------------|
| AUC | [0, 1] | Discriminación (0.5 = aleatorio) |
| TSS | [−1, 1] | Sensibilidad + Especificidad − 1 |
| Kappa | [−1, 1] | Concordancia corregida por azar |

---

## 8. Índice de incertidumbre

Índice compuesto que integra tres fuentes independientes:

### Componente 1: MESS (extrapolación ambiental)

Multivariate Environmental Similarity Surface (Elith et al. 2010):

```
Para cada celda y cada variable i:
  Si valor dentro del rango de entrenamiento:
    sim[i] = min((valor - min)/rango, (max - valor)/rango) × 100
  Si valor fuera del rango:
    sim[i] = -(distancia al límite más cercano)/rango × 100

MESS = min(sim) sobre todas las variables
MESS_norm = min(max(-MESS/100, 0), 1)
```

Umbral de extrapolación severa: MESS < −10.

### Componente 2: Amplitud bootstrap

```
W_bootstrap = q97.5 - q2.5 (de 200 muestras bootstrap)
W_norm = W_bootstrap / max(W_bootstrap)
```

### Componente 3: Esfuerzo de muestreo

```
factor_esfuerzo según nº de métodos de muestreo por cuadrícula:
  0 métodos (no muestreada) → 1.0
  1 método  → 0.7
  2 métodos → 0.5
  3+ métodos → 0.3
```

### Índice final

```
U_final = 0.33 × MESS_norm + 0.33 × W_norm + 0.34 × factor_esfuerzo

Opción adaptativa (pesos proporcionales a la varianza de cada componente):
  w_i = var(componente_i) / Σvar(componentes)
  U_final = Σ(w_i × componente_i)

U_final = min(U_final, 1)
```

---

## 9. Sistema de gremios ecológicos

### Categorías de refugio (4)

| Gremio | Descripción |
|--------|-------------|
| Cavernícola | Refugio en cuevas y cavidades subterráneas |
| Arborícola | Refugio en árboles (huecos, corteza) |
| Fisurícola | Refugio en fisuras de roca |
| Generalista | Refugio flexible (múltiples tipos) |

### Categorías de alimentación (6)

| Gremio | Hábitat de caza | Variables prioritarias |
|--------|-----------------|----------------------|
| Forestal | Ambientes forestales cerrados | C_forest_total, C_forest_cadu, Shannon |
| Ripario | Cuerpos de agua | Masas_agua, Riberas_arb, C_amb_acuat |
| Generalista | Múltiples hábitats | Shannon, C_forest_total, Herb_ralos |
| Mosaico | Paisajes agrícolas heterogéneos | Olivar, Mosaico_agri, Cul_herb |
| Pastizal | Áreas abiertas y pastizales | Herb_ralos, Herb_altos, Cul_herb |
| Aéreo | Vuelo alto sobre áreas abiertas | Alt_rec, Herb_ralos, Slop_rec |

### Grupos de variables (~90 candidatas)

- **Climáticas** (prioridad 3): 45+ variables bioclimáticas (T*, P*, DP*, DTN*, DTX*, SID, SIS)
- **Forestales** (prioridad 2-4): 27+ especies arbóreas e índices forestales
- **Geológicas** (prioridad 2-3): 20+ variables (Karst_*, Lito_*, Roquedos)
- **Acuáticas** (prioridad 2-4): 10+ variables (Masas_agua, Rios_anchos, etc.)
- **Topográficas** (prioridad 2-3): 8 variables (Alt_rec, Slop_rec, ETP_rec, CTI)
- **Urbanas** (prioridad 1-2): 6 variables antrópicas

---

## 10. Salvaguardas y validaciones

### Salvaguardas en la selección de variables

| Salvaguarda | Fase | Acción |
|-------------|------|--------|
| **S1**: Rescate de gremio | 3 (select07) | Reintroduce variables de gremio eliminadas por correlación |
| **S2**: Intercambio de prioridad | 5 (muestreo) | Sustituye variables p=1 por p≥2 en modelos reducidos |
| **S3**: Rescate de componentes | 6 (ecológica) | Rescata variables climáticas/gremio faltantes |

### Validaciones automáticas

- **`validar_config()`**: Verifica existencia de archivos, rangos de parámetros, suma de pesos
- **`validar_metadata()`**: Consistencia gremio-especie, categorías válidas, sin duplicados
- **Pre-flight checks**: Verifica existencia de archivos intermedios si fases anteriores desactivadas
- **Detección de separación perfecta**: Identifica variables problemáticas antes del análisis multivariante
- **Flags de convergencia**: Avisa si el GLM no converge durante bootstrap

### Sistema de checkpoints

Cada fase crea archivos checkpoint para evitar recálculos. `force_rerun = TRUE` recalcula todas las especies.

---

## 11. Estructura de salidas

### Por especie

```
output/modelos/{especie}/
├── ambiental/
│   ├── predicciones.csv          # F_glm_mean, F_glm_sd, q025, q975, W_glm
│   ├── metricas_holdout.csv      # AUC, TSS, threshold
│   ├── coeficientes_glm.csv      # term, estimate, std.error, CI, p-valor
│   ├── modelo_glm.rds            # Objeto GLM ajustado
│   ├── bootstrap_samples.rds     # Matriz 200 × n_celdas
│   ├── datos_entrenamiento.rds   # Set de entrenamiento
│   └── metadata.json             # n_pres, n_aus, n_vars, AUC, TSS, fecha
├── espacial/
│   ├── predicciones.csv          # F_esp_mean, F_esp_sd
│   ├── comparacion_aicc.csv      # AICc por método
│   └── modelo_espacial.rds       # Modelo seleccionado
├── espacial_residuos/              # (opcional, si usar_residuos=TRUE o 03b_bis)
│   ├── predicciones.csv          # F_esp_res_mean, pred_residuo, p_total
│   ├── diagnostico_residuos.csv  # Estadísticos de residuos
│   ├── comparacion_aicc.csv      # AICc residuos vs PA directa
│   └── metadata.json             # Enfoque, var_ratio_residual
├── interseccion/
│   ├── predicciones.csv          # F_final_mean, F_final_sd, q025, q975
│   └── bootstrap_samples.rds     # Matriz 200 × n_celdas (fuzzy)
├── validacion/
│   ├── metricas_cv.csv           # AUC, TSS por fold y repetición
│   └── resumen_cv.csv            # Media ± SD agregada
├── incertidumbre/
│   └── incertidumbre.csv         # MESS, W_bootstrap, esfuerzo, U_final
└── mapas/
    ├── {especie}_favorabilidad.tif
    └── {especie}_incertidumbre.tif
```

### Selección de variables

```
output/seleccion_variables/
├── variables_json/{especie}.json         # Metadatos completos de selección
└── diagnosticos/{especie}_diagnostico.csv # Log fase a fase
```

---

## 12. Sistema de tests

40+ tests automatizados en `tests/test_pipeline.R`:

| Grupo | Tests |
|-------|-------|
| Configuración | Rangos de parámetros, suma de pesos |
| Funciones core | Favorabilidad, métricas, imputación |
| CORINE | Agregación de usos del suelo |
| Gremios | Prioridades, asignación de especies |
| GLM + Favorabilidad | Ajuste básico del modelo |
| Selección de variables | Fases 1-2 del pipeline |
| Operadores fuzzy | Media geométrica, pmin, compensatorio |
| Logging | Creación y escritura de logs |
| Metadatos | Consistencia gremio-especie |
| Fail-fast | Validación de categorías, detección de duplicados |

**Datos sintéticos:** 500 celdas, 10 variables, 2 especies simuladas (R. ferrumequinum como cavernícola, P. pipistrellus como generalista). Seed fijo (42) para reproducibilidad.

---

## 13. Tabla resumen de parámetros

| Parámetro | Valor | Justificación |
|-----------|-------|---------------|
| Bootstrap n | 200 | IC 95% estables, eficiencia computacional |
| Split train/test | 70/30 | Suficientes datos de entrenamiento, validación independiente |
| Seed | 123 | Reproducibilidad, mismo seed entre especies |
| Umbral correlación | 0.80 | Elimina redundancia severa, preserva complementariedad |
| Umbral VIF | 10 | Estándar ecológico (Dormann et al. 2013) |
| Mín. presencias | 30 | Mínimo para GLM fiable |
| Ratio N/p | 8 | Regla de Harrell (conservador) |
| Mín. variables gremio | 2 | Garantiza relevancia ecológica |
| k-folds | 5 | Equilibrio coste computacional / precisión |
| Umbral MESS | −10 | Identifica extrapolación severa |
| Factor esfuerzo 3+ | 0.3 | Muestreo multimétodo reduce incertidumbre 70% |

---

## Referencias

- Acevedo, P. & Real, R. (2012). Favourability: concept, distinctive characteristics and potential usefulness. *Naturwissenschaften*, 99, 515-522.
- Borcard, D., Legendre, P. & Drapeau, P. (1992). Partialling out the spatial component of ecological variation. *Ecology*, 73, 1045-1055.
- Burnham, K.P. & Anderson, D.R. (2002). *Model Selection and Multimodel Inference*. Springer.
- Dormann, C.F. et al. (2013). Collinearity: a review of methods to deal with it. *Ecography*, 36, 27-46.
- Elith, J. et al. (2010). The art of modelling range-shifting species. *Methods in Ecology and Evolution*, 1, 330-342.
- Muñoz, A.R. & Real, R. (2006). Assessing the potential range expansion of the exotic monk parakeet in Spain. *Diversity and Distributions*, 12, 656-665.
- Real, R. et al. (2006). Obtaining environmental favourability functions from logistic regression. *Environmental and Ecological Statistics*, 13, 237-245.
- Roberts, D.R. et al. (2017). Cross-validation strategies for data with temporal, spatial, hierarchical, or phylogenetic structure. *Ecography*, 40, 913-929.
