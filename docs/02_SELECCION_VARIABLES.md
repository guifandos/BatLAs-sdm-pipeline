# Seleccion de Variables

## Metodologia: Pipeline de 7 fases

### Fase 1: Pre-seleccion por gremio
Variables prioritarias segun clasificacion ecologica de la especie (refugio x alimentacion).
Se leen de `data/metadata/gremios_refugio.csv` y `data/metadata/gremios_alimentacion.csv`.

### Fase 2: select07 en variables de gremio
Algoritmo basado en importancia univariada (AIC) y correlacion.
Umbral de correlacion: 0.8 (parametro `CONFIG$seleccion$correlation_threshold`).

### Fase 3: select07 en variables secundarias
Mismo algoritmo aplicado al resto de variables ambientales.

### Fase 4: Filtro VIF
Eliminacion iterativa de variables con VIF > 10.
Safeguard: variables de gremio se protegen si hay alternativas no-gremio con VIF alto.

### Fase 5: Ratio N/p
Maximo de variables = presencias / 8 (parametro `CONFIG$seleccion$ratio_Np`).
Prioridad: variables de gremio sobre secundarias.

### Fase 6: Safeguard ecologico
Minimo de 2 variables del gremio en la seleccion final.

### Fase 7: Exportacion JSON
Un archivo JSON por especie con variables seleccionadas y sus importancias.

## Modificar gremios

Para cambiar la clasificacion de una especie:
1. Editar `data/metadata/especies_gremios.csv`
2. Re-ejecutar `source("R/02_variable_selection/02d_ejecutar_seleccion.R")`

Para cambiar las variables asociadas a un gremio:
1. Editar `data/metadata/gremios_refugio.csv` o `gremios_alimentacion.csv`
2. Re-ejecutar la seleccion

## Output

Directorio: `output/seleccion_variables/variables_json/`

Formato JSON por especie:
```json
{
  "especie": "Rhinolophus ferrumequinum",
  "gremio_refugio": "Cavernicola",
  "gremio_alimentacion": "Forestal",
  "n_presencias": 245,
  "n_ausencias": 5185,
  "variables_finales": {
    "name": ["Karst_principal", "CLC_bosques", "Bio01", ...],
    "importancia": [0.15, 0.12, 0.09, ...]
  }
}
```
