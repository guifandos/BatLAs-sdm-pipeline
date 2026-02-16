# Incertidumbre

## Componentes

### 1. MESS (Multivariate Environmental Similarity Surface)

Detecta cuadriculas donde las condiciones ambientales estan fuera del rango de los datos de entrenamiento.

- Valores positivos: dentro del rango (mas alto = mas central)
- Valor 0: en el limite del rango
- Valores negativos: extrapolacion (mas negativo = mas extremo)
- Umbral de extrapolacion severa: MESS < -10

Se normaliza a [0,1] donde 1 = maxima extrapolacion.

### 2. Ancho del intervalo bootstrap (W)

Amplitud del IC 95% de las predicciones bootstrap:

```
W = q97.5 - q2.5
```

Se normaliza dividiendo por el maximo W observado.

### 3. Factor de esfuerzo de muestreo

Cuadriculas muestreadas con mas metodos tienen menor incertidumbre:

| Metodos | Factor |
|---|---|
| 0 (no muestreado) | 1.0 |
| 1 | 0.7 |
| 2 | 0.5 |
| 3+ | 0.3 |

Metodos considerados: acustica, captura, censos en cuevas, otros.

### Combinacion

```
U_final = w1 * MESS_norm + w2 * W_norm + w3 * factor_esfuerzo
```

Pesos por defecto: w1=0.33, w2=0.33, w3=0.34 (configurables en `CONFIG$incertidumbre`).
