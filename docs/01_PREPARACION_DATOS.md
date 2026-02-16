# Preparacion de Datos

## Archivos de entrada requeridos

### 1. Presencias

**Archivo**: `data/raw/presencias/_final_coords_UTM_editada_20250929.csv`

Formato CSV con separador `;` y encoding latin1/ISO-8859-1.

Columnas requeridas:
- `especie_definitiva`: Nombre cientifico
- `cuadricula_utm_10x10`: ID de cuadricula UTM 10x10 km
- `metodologia`: Metodo de deteccion (acustica, captura, cueva, etc.)

### 2. Variables ambientales

**Directorio**: `data/raw/variables/`

Archivos CSV con patron `10x10_*.csv`. Cada archivo contiene la columna `CUADRICULA` y una o mas variables.

| Archivo | Variables |
|---|---|
| `10x10_Bio01_PIBAL.csv` | Temperatura media anual |
| `10x10_Bio05_PIBAL.csv` | Temperatura maxima mes mas calido |
| `10x10_Bio06_PIBAL.csv` | Temperatura minima mes mas frio |
| `10x10_Bio12_PIBAL.csv` | Precipitacion anual |
| `10x10_SRTM_PIBAL.csv` | Altitud (SRTM) |
| `10x10_Slope_PIBAL.csv` | Pendiente |
| `10x10_CLC_PIBAL.csv` | CORINE Land Cover (clases HISTO) |
| `10x10_Karst_PIBAL.csv` | Variables de karst |
| `10x10_lito_COLOR_PIBAL.csv` | Litologia |
| `10x10_LamArt_PIBAL.csv` | Laminas de agua artificiales |
| `variables_forestales_10x10.csv` | Estructura forestal |

### 3. Grid espacial

**Archivo**: `data/processed/predictores_all.rds`

Objeto RDS con lista que contiene:
- `$malla_union`: Objeto SF con geometrias de las cuadriculas y coordenadas X, Y
- `$vars_all`: Data frame con todas las variables por cuadricula

## Flujo de scripts

```
01a_cargar_presencias.R
  Input:  data/raw/presencias/*.csv
  Output: data/processed/presencias_raw.rds

01b_cargar_variables.R
  Input:  data/raw/variables/10x10_*.csv
  Output: data/processed/variables_10x10_raw.rds

01c_agrupar_corine.R
  Input:  data/processed/variables_10x10_raw.rds
  Output: data/processed/variables_10x10_corine.rds

01d_procesar_geologia.R
  Input:  data/processed/variables_10x10_corine.rds
  Output: data/processed/variables_10x10_geologia.rds

01e_crear_PA_matriz.R
  Input:  data/processed/presencias_raw.rds
          data/processed/variables_10x10_geologia.rds
  Output: data/processed/datos_presencia_ausencia.rds

01f_separar_por_metodo.R
  Input:  data/processed/datos_presencia_ausencia.rds
          data/processed/presencias_raw.rds
  Output: data/processed/PAxENV_all_metodos.rds     <- ARCHIVO MAESTRO
          data/processed/esfuerzo_por_metodo.rds
```

## Notas importantes

- **Canarias**: Las cuadriculas 28R se excluyen automaticamente (resolucion 5x5 km, analisis separado).
- **Baleares**: Zona UTM 31 (prefijos 31S, 31T). Se incluyen en el analisis principal.
- **Normalizacion IDs**: Usar `norm_id()` de `utils_checkpoints.R` para homogeneizar.
- **Re-ejecucion**: Para incorporar nuevos datos, reemplazar el CSV de presencias y ejecutar desde 01a.
