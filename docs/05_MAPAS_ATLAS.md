# Mapas Atlas

## Tipos de mapas generados

### Panel SECEMU (2x2)
- **Modelo Ambiental**: Favorabilidad del GLM
- **Modelo Final**: Favorabilidad tras interseccion fuzzy
- **Incertidumbre**: Incertidumbre compuesta final
- **Presencia Observada**: Cuadriculas con registros

### Panel Incertidumbre (2x2)
- **MESS**: Mapa de extrapolacion ambiental
- **Bootstrap W**: Amplitud del intervalo de confianza
- **Incertidumbre Final**: Combinacion ponderada
- **Bivariado**: Favorabilidad x Incertidumbre (3x3)

### Mapa bivariado
Combina favorabilidad e incertidumbre en una matriz 3x3:
- Eje X: Favorabilidad (Bajo/Medio/Alto)
- Eje Y: Incertidumbre (Baja/Media/Alta)
- 9 colores unicos para las combinaciones

## Paletas de colores

Todas las paletas son colorblind-friendly (paquete `scico`):
- **Favorabilidad**: batlow (azul -> amarillo)
- **Incertidumbre**: lajolla (beige -> marron)
- **MESS**: vik (azul <- blanco -> rojo, divergente)

## Configuracion

```r
CONFIG$mapas$dpi = 300           # Resolucion
CONFIG$mapas$ancho_cm = 20       # Ancho en cm
CONFIG$mapas$alto_cm = 20        # Alto en cm
CONFIG$mapas$crs_salida = 25830  # ETRS89/UTM 30N
```

## Outputs por especie

```
output/modelos/{Especie}/mapas/
  |-- panel_SECEMU.png           # 24x20 cm, 300 DPI
  |-- panel_incertidumbre.png    # 24x20 cm, 300 DPI
  +-- mapa_bivariado.png         # 16x12 cm, 300 DPI
```
