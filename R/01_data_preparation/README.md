# Fase 0: Preparacion de Datos

Pipeline de 8 pasos que transforma datos brutos (CSV, Excel, Shapefiles) en matrices PAxENV listas para modelizacion.

## Orden de ejecucion

```
01a -> 01b -> 01c -> 01d -> 01e -> 01f -> 01g -> [01h]
```

| Script | Funcion | Input | Output |
|--------|---------|-------|--------|
| `01a_preparar_PA_metodo.R` | Cargar presencias, clasificar metodos, aplicar complejos cripticos | CSV presencias, CSV complejos | `pa_metodo.rds`, `muestras_metodo_wide.rds` |
| `01b_cargar_malla.R` | Cargar shapefiles UTM 10x10 (Peninsula + Baleares) | Shapefiles (.shp) | `malla_union.rds` |
| `01c_cargar_variables_excel.R` | Leer variables ambientales desde Excel, escalar | Excel (.xlsx) | `predictores_SEO.rds` |
| `01d_agrupar_corine.R` | Agrupar CORINE Land Cover en 9 categorias ecologicas | `predictores_SEO.rds` | `predictores_SEO.rds` (actualizado) |
| `01e_procesar_geologia.R` | Construir features geologicos (Karst + Litologia + PCA) | CSVs Karst/Lito | `geo_features.rds` |
| `01f_unir_predictores.R` | Unir predictores SEO + GEO, integrar Baleares | `predictores_SEO.rds`, `geo_features.rds` | `predictores_SEO_GEO.rds` |
| `01g_crear_PAxENV_metodo.R` | Crear matrices PAxENV por metodo + formato ancho compatible | PA + predictores | `PAxENV_*.rds`, `PAxENV_all_metodos.rds` |
| `01h_mapa_chequeo.R` | Mapas QA de predictores (opcional) | `predictores_SEO_GEO_sf.rds` | PNGs en `output/figs/` |

## Inputs necesarios (en `data/raw/`)

- `presencias/_final_coords_UTM_editada_20250929.csv` - Registros con especie, cuadricula, metodologia
- `shapefiles/Malla10x10_clip.shp` - Malla UTM 10x10 Peninsula
- `shapefiles/Malla10x10_BAL_Clip_nueva.shp` - Malla UTM 10x10 Baleares
- `variables/Variables_EC.xlsx` - Variables ambientales Peninsula
- `variables/Variables_BAL.xlsx` - Variables ambientales Baleares
- `variables/10x10_Karst_PIBAL.csv` - Datos karsticos
- `variables/10x10_lito_COLOR_PIBAL.csv` - Datos litologicos

## Outputs generados (en `data/`)

### `data/processed/`
- `pa_metodo.rds` - Tabla PA larga (especie x cuadricula x metodo)
- `muestras_metodo.rds` - Registros por cuadricula/metodo
- `muestras_metodo_wide.rds` - Cuadriculas con indicadores m_acustica, m_captura, etc.
- `malla_union.rds` - Malla UTM 10x10 unificada (sf)
- `predictores_SEO.rds` - Variables ambientales (lista con ec, bal, malla)
- `geo_features.rds` - Variables geologicas derivadas
- `predictores_SEO_GEO.rds` - Union de todas las variables predictoras
- `predictores_SEO_GEO_sf.rds` - Idem con geometria (sf)

### `data/modelado_ready/`
- `PAxENV_acustica.rds` - PAxENV para metodo acustica
- `PAxENV_captura.rds` - PAxENV para metodo captura
- `PAxENV_cuevas.rds` - PAxENV para metodo cuevas
- `PAxENV_otros.rds` - PAxENV para metodo otros
- `PAxENV_por_metodo_all.rds` - PAxENV combinado (formato largo)
- `PAxENV_all_metodos.rds` - Formato ancho compatible con Fase 2+ (sp_* + predictores + esfuerzo)

## Notas

- **Canarias**: Se filtran automaticamente las cuadriculas con prefijo `28R`
- **Baleares**: Se integran reproyectando al CRS de Peninsula si difieren
- **IDs**: Todos los IDs de cuadricula se normalizan con `norm_id()` (uppercase, sin espacios)
- **Complejos cripticos**: Se leen de `data/metadata/complejos_taxonomicos.csv`
- **QA mapas**: `01h` solo se ejecuta si `CONFIG$control$ejecutar$qa_mapas = TRUE`
