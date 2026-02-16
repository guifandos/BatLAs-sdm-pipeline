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
- 500 iteraciones (configurable en `CONFIG$ambiental$n_bootstrap`)
- Remuestreo con reemplazo de los datos de entrenamiento
- Genera intervalos de confianza del 95%

## Modelo espacial (GAM)

Compara tres modelos espaciales basados en coordenadas X,Y:
1. **GLM grado 2**: X + Y + X^2 + Y^2 + X*Y
2. **GLM grado 3**: Anade terminos cubicos
3. **GAM**: Spline bivariado s(X, Y, k=30)

Seleccion automatica por AICc. Bootstrap independiente del modelo ambiental.

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
