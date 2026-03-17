# Modelizacion

## Modelo ambiental (GLM + Favorabilidad)

### Ajuste
- GLM binomial con variables seleccionadas en Fase 1
- Split hold-out 70/30 para evaluacion
- Metricas: AUC, TSS, Sensibilidad, Especificidad

### Favorabilidad (Real et al. 2006)
Transforma probabilidades del GLM corrigiendo el sesgo de prevalencia:

```
F = (P/(1-P)) / ((n1/n0) + P/(1-P))
```

Donde P = probabilidad del modelo, n1 = presencias, n0 = ausencias.

### Bootstrap
- 200 iteraciones (configurable en `CONFIG$ambiental$n_bootstrap`)
- Remuestreo con reemplazo de los datos de entrenamiento
- Genera intervalos de confianza del 95%

## Modelo espacial (GAM)

Compara tres modelos espaciales basados en coordenadas X,Y:
1. **GLM grado 2**: X + Y + X^2 + Y^2 + X*Y
2. **GLM grado 3**: Anade terminos cubicos
3. **GAM**: Spline bivariado s(X, Y, k=30)

Seleccion automatica por AICc. Bootstrap independiente del modelo ambiental.

### Enfoque alternativo: modelo espacial sobre residuos

El pipeline incluye un enfoque alternativo (`03b_bis_espacial_residuos.R`) que modela los **residuos del GLM ambiental** en lugar de la PA directa, evitando el doble conteo del efecto ambiental en la interseccion fuzzy.

**El problema del doble conteo.** Cuando el GAM espacial modela `PA ~ f(X,Y)`, la PA ya contiene la senal ambiental (p.ej., los murcielagos cavernicolas viven donde hay karst, y el karst tiene una distribucion geografica concreta). El GAM captura esa senal indirectamente, y al combinar con la interseccion fuzzy el efecto ambiental se cuenta dos veces: una en F_ambiental y otra dentro de F_espacial.

**La solucion.** Modelar los residuos:

```
residuos = PA - prob_ambiental    (prob del GLM de Fase 2)
residuos ~ s(X, Y, k = k_adaptativo)    [family = gaussian]
```

Los residuos representan la parte de la distribucion que el modelo ambiental NO explica: autocorrelacion espacial pura, dispersion limitada, barreras geograficas, historia biogeografica. La prediccion final se reconstruye como:

```
p_total = p_ambiental + f_espacial(residuo)    [truncado a 0-1]
F_espacial_residuos = favorabilidad(p_total)
```

Se usa `family = gaussian` (no binomial) porque los residuos son continuos en [-1, 1].

**Cuando usar cada enfoque:**

| Criterio | PA directa (03b, default) | Residuos (03b_bis) |
|----------|--------------------------|---------------------|
| Simplicidad | Mayor | Requiere modelo ambiental previo |
| Doble conteo | Posible | Evitado |
| AUC ambiental bajo (<0.7) | Recomendado | La senal residual puede ser ruidosa |
| AUC ambiental alto (>0.8) | El modelo espacial aporta poco nuevo | Recomendado |
| Incertidumbre | Componentes correlacionadas | Componentes independientes |
| Precedentes | Mayoria de atlas (Munoz et al. 2005, Barbosa et al. 2009) | Borcard et al. (1992), Legendre & Legendre (2012) |

**Activacion:**
- En `00_config.R`: `CONFIG$espacial$usar_residuos = TRUE` (integrado en 03b)
- O ejecutar `03b_bis_espacial_residuos.R` de forma independiente (incluye diagnosticos de residuos y tabla comparativa AICc entre ambos enfoques)

El script 03b_bis genera una tabla comparativa por especie (AICc residuos vs PA directa) y un ratio de varianza residual que indica cuanta variacion queda por explicar tras el modelo ambiental.

## Interseccion fuzzy

Combina favorabilidad ambiental y espacial:

```
F_final = sqrt(F_ambiental * F_espacial)    # Metodo geometrico (por defecto)
F_final = min(F_ambiental, F_espacial)      # Minimo conservador
F_final = (F_amb^g + F_esp^g) / 2           # Compensatorio (gamma = 0.5)
```

Se aplica a cada iteracion bootstrap para propagar incertidumbre.

## Incertidumbre

Combinacion ponderada de tres componentes:

```
U = 0.33 * MESS_norm + 0.33 * W_bootstrap_norm + 0.34 * factor_esfuerzo
```

- **MESS**: Extrapolacion ambiental (valores negativos = fuera del rango de entrenamiento)
- **W_bootstrap**: Amplitud del intervalo de confianza 95%
- **Factor esfuerzo**: Basado en numero de metodos de muestreo por cuadricula
  - 0 metodos: factor = 1.0 (maxima incertidumbre)
  - 1 metodo: factor = 0.7
  - 2 metodos: factor = 0.5
  - 3+ metodos: factor = 0.3

## Referencias

- Real R. et al. (2006) Obtaining environmental favourability functions from logistic regression. *Environmental and Ecological Statistics*, 13:237-245.
- Borcard, D., Legendre, P. & Drapeau, P. (1992). Partialling out the spatial component of ecological variation. *Ecology*, 73:1045-1055.
- Legendre, P. & Legendre, L. (2012). *Numerical Ecology*. 3rd ed. Elsevier.
