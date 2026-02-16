# Flujo de Trabajo Completo

## Diagrama del Pipeline

```
DATOS BRUTOS                    PREPARACION (Fase 0)
  presencias.csv    ---->  01a: Cargar presencias
  10x10_*.csv       ---->  01b: Cargar variables
                           01c: Agrupar CORINE (9 grupos ecologicos)
                           01d: Procesar geologia (Karst + Litologia + PCA)
                           01e: Crear matriz PA (especie x cuadricula)
                           01f: Separar por metodo
                                    |
                                    v
                           PAxENV_all_metodos.rds
                           esfuerzo_por_metodo.rds
                                    |
                                    v
SELECCION (Fase 1) -----> 02d: Ejecutar seleccion
  gremios_*.csv               |
  especies_gremios.csv         +---> variables_json/{especie}.json
                                    |
                                    v
MODELIZACION (Fases 2-6)
  03a: GLM + Favorabilidad + Bootstrap (n=500)
       |
       v
  03b: GAM/GLM espacial (seleccion por AICc)
       |
       v
  03c: Interseccion fuzzy: F = sqrt(F_amb x F_esp)
       |
       v
  03d: Validacion cruzada espacial (k=5)
       |
       v
  03e: Incertidumbre: U = w1*MESS + w2*W_boot + w3*esfuerzo
       |
       v
VISUALIZACION (Fase 7)
  04a: Mapas atlas (panel SECEMU 2x2)
  04b: Paneles incertidumbre
  04c: Figuras resumen
```

## Dependencias entre fases

| Fase | Requiere |
|---|---|
| 0 (Preparacion) | Datos brutos en data/raw/ |
| 1 (Seleccion) | Fase 0: PAxENV_all_metodos.rds |
| 2 (GLM) | Fase 1: JSONs de variables |
| 3 (GAM) | Fase 2: datos_entrenamiento.rds |
| 4 (Fuzzy) | Fases 2+3: bootstrap_samples.rds |
| 5 (CV) | Fase 1: JSONs de variables |
| 6 (Incertidumbre) | Fases 4+esfuerzo: predicciones + MESS |
| 7 (Mapas) | Fases 2+4+6: todas las predicciones |

## Tiempos estimados (25 especies, 500 bootstrap)

| Fase | Tiempo aprox. |
|---|---|
| Preparacion | 5-10 min |
| Seleccion | 5-15 min |
| Modelo ambiental | 1-2 h |
| Modelo espacial | 1-2 h |
| Interseccion | 5-10 min |
| Validacion | 15-30 min |
| Incertidumbre | 5-10 min |
| Mapas | 10-20 min |
| **TOTAL** | **3-6 h** |
