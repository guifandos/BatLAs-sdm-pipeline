# ==============================================================================
# 01g_crear_PAxENV_metodo.R - Crear PAxENV por metodo de muestreo
# ==============================================================================
#
# RAZON CIENTIFICA — PAxENV POR METODO:
# Cada metodo de muestreo de murcielagos tiene sesgos de deteccion distintos:
#   - ACUSTICA: detecta preferentemente especies de vuelo abierto y con
#     ecolocalizacion potente (e.g., Nyctalus, Eptesicus, Pipistrellus).
#     Infradetecta especies de vuelo lento y llamadas debiles (Plecotus,
#     Rhinolophus en espacio abierto).
#   - CAPTURA (redes/arpas): captura especies que vuelan bajo y cerca de
#     vegetacion (Myotis, Rhinolophus). Infradetecta las que vuelan alto.
#   - CUEVAS: muestreo directo de colonias. Detecta solo cavernicolas y
#     solo en cuadriculas con cavidades conocidas.
#   - OTROS: registros oportunistas (atropellos, gatos, rehabilitacion).
#
# Separar los datos por metodo permite modelar la probabilidad de deteccion
# de forma independiente, evitando que los sesgos de un metodo contaminen
# las estimaciones de prevalencia basadas en otro. Cada PAxENV_{metodo}.rds
# contiene solo las cuadriculas donde ese metodo fue aplicado, definiendo
# correctamente el universo de ausencias verdaderas.
#
# RAZON CIENTIFICA — FORMATO ANCHO RETROCOMPATIBLE:
# La Fase 2+ (modelado con BRT/MaxEnt/ensemble) espera una unica tabla con
# columnas sp_{especie} (presencia/ausencia) + predictores ambientales. El
# formato ancho con prefijo "sp_" permite identificar rapidamente las columnas
# de respuesta vs. predictoras, y es compatible con los scripts de seleccion
# de variables y evaluacion de modelos existentes.
#
# RAZON CIENTIFICA — FACTOR DE INCERTIDUMBRE (factor_incert):
# El factor_incert cuantifica la confianza en las ausencias de cada cuadricula
# en funcion del esfuerzo de muestreo. Cuadriculas muestreadas por multiples
# metodos (n_metodos >= 3) tienen mayor probabilidad de haber detectado las
# especies presentes, por lo que sus ausencias son mas fiables (factor = 0.3).
# Cuadriculas no muestreadas (n_metodos = 0) reciben factor = 1.0 (maxima
# incertidumbre). Este factor se usa en Fase 3 para ponderar las predicciones
# en los mapas de incertidumbre.
#
# INPUT:  CONFIG$paths$pa_metodo (from 01a)
#         CONFIG$paths$muestras_metodo_wide (from 01a)
#         CONFIG$paths$predictores_seo_geo (from 01f)
#         CONFIG$paths$malla_union (from 01b)
# OUTPUT: CONFIG$paths$paxenv_all
#         CONFIG$paths$paxenv_acustica
#         CONFIG$paths$paxenv_captura
#         CONFIG$paths$paxenv_cuevas
#         CONFIG$paths$paxenv_otros
#         CONFIG$paths$pa_data (backward-compatible wide format)
#         CONFIG$paths$esfuerzo
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

# --- Cargar configuracion y utilidades (idempotente) ---
if (!exists("CONFIG")) source("R/00_setup/00_config.R")
if (!exists("norm_id")) source("R/utils/utils_checkpoints.R")

suppressPackageStartupMessages({
  library(tidyverse)
  library(sf)
})

cat("\n=== 01g: CREAR PAxENV POR METODO ===\n\n")

# --- 1. Cargar datos ---
pa_metodo <- readRDS(CONFIG$paths$pa_metodo)
muestras_wide <- readRDS(CONFIG$paths$muestras_metodo_wide)
predictores <- readRDS(CONFIG$paths$predictores_seo_geo)
malla_union <- readRDS(CONFIG$paths$malla_union)

cat(sprintf("PA por metodo: %d registros\n", nrow(pa_metodo)))
cat(sprintf("Cuadriculas muestreadas: %d\n", nrow(muestras_wide)))
cat(sprintf("Predictores: %d cuadriculas x %d vars\n", nrow(predictores), ncol(predictores) - 1))

# Validar columnas ID antes de cualquier join
stopifnot(
  "pa_metodo no tiene columna cuadricula_utm_10x10" = "cuadricula_utm_10x10" %in% names(pa_metodo),
  "muestras_wide no tiene columna cuadricula_utm_10x10" = "cuadricula_utm_10x10" %in% names(muestras_wide),
  "predictores no tiene columna CUADRICULA" = "CUADRICULA" %in% names(predictores)
)

# Diagnostico de solapamiento de IDs entre PA y predictores
ids_pa <- unique(pa_metodo$cuadricula_utm_10x10)
ids_pred <- unique(predictores$CUADRICULA)
n_match <- length(intersect(ids_pa, ids_pred))
cat(sprintf("\nDiagnostico IDs: %d en PA, %d en predictores, %d en comun\n",
            length(ids_pa), length(ids_pred), n_match))
if (n_match < length(ids_pa) * 0.8) {
  cat(sprintf("  AVISO: solo %.0f%% de IDs de PA estan en predictores!\n",
              100 * n_match / length(ids_pa)))
  cat(sprintf("  Ejemplo IDs PA: %s\n", paste(head(ids_pa, 5), collapse = ", ")))
  cat(sprintf("  Ejemplo IDs pred: %s\n", paste(head(ids_pred, 5), collapse = ", ")))
}
if (n_match == 0) {
  stop("CRITICO: 0 IDs en comun entre PA y predictores. Revisar normalizacion de IDs.")
}

# --- 2. Unir PA con predictores ---
# Para cada especie-metodo-cuadricula, tenemos presencia=1.
# Las ausencias se definen como cuadriculas muestreadas por ese metodo
# donde la especie NO fue registrada. Esto es clave: una ausencia solo
# tiene sentido ecologico si el metodo fue aplicado en esa cuadricula.

metodos <- unique(pa_metodo$metodo)
cat(sprintf("\nMetodos encontrados: %s\n", paste(metodos, collapse = ", ")))

dir.create(CONFIG$paths$modelado_ready_dir, recursive = TRUE, showWarnings = FALSE)

# Variables predictoras (todo menos CUADRICULA)
vars_pred <- setdiff(names(predictores), "CUADRICULA")

# --- 3. Generar PAxENV por metodo ---
# Se crea una tabla PAxENV independiente por cada metodo. Cada tabla contiene
# solo las cuadriculas donde el metodo fue aplicado, con presencia (1) o
# ausencia (0) para cada especie, junto con todas las variables ambientales.
paxenv_list <- list()

for (met in metodos) {
  cat(sprintf("\n--- Procesando metodo: %s ---\n", met))

  # Cuadriculas muestreadas por este metodo (binario en muestras_wide)
  col_met <- paste0("m_", met)
  if (col_met %in% names(muestras_wide)) {
    cuads_muestreadas <- muestras_wide %>%
      filter(!!sym(col_met) == 1) %>%
      pull(cuadricula_utm_10x10)
  } else {
    # Fallback: si no hay columna de metodo en muestras_wide, usar las
    # cuadriculas con registros directos de este metodo en pa_metodo
    cuads_muestreadas <- pa_metodo %>%
      filter(metodo == met) %>%
      pull(cuadricula_utm_10x10) %>%
      unique()
  }

  cat(sprintf("  Cuadriculas muestreadas: %d\n", length(cuads_muestreadas)))

  # Especies con presencia en este metodo
  especies_met <- pa_metodo %>%
    filter(metodo == met) %>%
    pull(especie_modelo) %>%
    unique()

  cat(sprintf("  Especies: %d\n", length(especies_met)))

  # Construir tabla PA wide: filas = cuadriculas, columnas = especies (0/1)
  pa_wide <- pa_metodo %>%
    filter(metodo == met) %>%
    select(cuadricula_utm_10x10, especie_modelo, presencia) %>%
    pivot_wider(names_from = especie_modelo, values_from = presencia,
                values_fill = 0L)

  # Anadir cuadriculas muestreadas sin presencia de ninguna especie (ausencias puras).
  # Estas cuadriculas fueron visitadas pero no se detecto ninguna de las especies.
  cuads_con_pres <- pa_wide$cuadricula_utm_10x10
  cuads_ausencia <- setdiff(cuads_muestreadas, cuads_con_pres)

  if (length(cuads_ausencia) > 0) {
    ausencias <- tibble(cuadricula_utm_10x10 = cuads_ausencia)
    for (sp in especies_met) {
      ausencias[[sp]] <- 0L
    }
    pa_wide <- bind_rows(pa_wide, ausencias)
  }

  # Unir con predictores ambientales (renombrar CUADRICULA para el join)
  predictores_join <- predictores %>%
    rename(cuadricula_utm_10x10 = CUADRICULA)

  n_pa_pre <- nrow(pa_wide)
  paxenv <- pa_wide %>%
    left_join(predictores_join, by = "cuadricula_utm_10x10")

  # O8: Validacion post-join
  stopifnot(
    "Join PA+predictores perdio filas" = nrow(paxenv) == n_pa_pre
  )
  n_sin_pred <- sum(is.na(paxenv[[vars_pred[1]]]))
  if (n_sin_pred > 0) {
    cat(sprintf("  AVISO: %d cuadriculas sin predictores (%.1f%%)\n",
                n_sin_pred, 100 * n_sin_pred / nrow(paxenv)))
  }

  cat(sprintf("  PAxENV: %d cuadriculas x %d columnas\n", nrow(paxenv), ncol(paxenv)))

  paxenv_list[[met]] <- paxenv

  # Guardar individualmente (un fichero por metodo)
  path_met <- file.path(CONFIG$paths$modelado_ready_dir, paste0("PAxENV_", met, ".rds"))
  saveRDS(paxenv, path_met)
  cat(sprintf("  [OK] Guardado: %s\n", path_met))
}

# --- 4. Guardar PAxENV combinado (todos los metodos) ---
# Tabla larga con columna "metodo" que identifica la fuente de cada registro.
# Util para analisis multi-metodo y comparaciones de detectabilidad.
paxenv_all <- bind_rows(paxenv_list, .id = "metodo") %>%
  distinct(cuadricula_utm_10x10, metodo, .keep_all = TRUE)

saveRDS(paxenv_all, CONFIG$paths$paxenv_all)
cat(sprintf("\n[OK] PAxENV combinado: %s (%d filas)\n", CONFIG$paths$paxenv_all, nrow(paxenv_all)))

# --- 5. Compatibilidad Fase 2+: PAxENV_all_metodos.rds (formato ancho) ---
# Fase 2 (seleccion de variables) y Fase 3 (modelado BRT/ensemble) esperan
# una unica tabla con columnas sp_{especie} y variables predictoras. Se
# combinan todas las presencias de todos los metodos (union de evidencia:
# si una especie fue detectada por CUALQUIER metodo, se marca como presente).
cat("\nGenerando formato ancho compatible con Fase 2+...\n")

# Unir todas las presencias de todos los metodos (prefijo sp_ para columnas de especie)
pa_all_wide <- pa_metodo %>%
  select(cuadricula_utm_10x10, especie_modelo, presencia) %>%
  distinct(cuadricula_utm_10x10, especie_modelo, .keep_all = TRUE) %>%
  pivot_wider(names_from = especie_modelo, values_from = presencia,
              values_fill = 0L, names_prefix = "sp_")

# Todas las cuadriculas con predictores (incluye no muestreadas para prediccion)
all_cuads <- predictores %>%
  rename(cuadricula_utm_10x10 = CUADRICULA) %>%
  select(cuadricula_utm_10x10, all_of(vars_pred))

# Unir: cuadriculas no muestreadas tendran NA en columnas sp_ (se rellenan con 0)
n_all_cuads <- nrow(all_cuads)
pa_compat <- all_cuads %>%
  left_join(pa_all_wide, by = "cuadricula_utm_10x10")
stopifnot(
  "Join all_cuads+PA perdio o duplico filas" = nrow(pa_compat) == n_all_cuads
)
cat(sprintf("  Join all_cuads + PA: %d filas preservadas\n", nrow(pa_compat)))

# Rellenar NAs de especies con 0 (cuadriculas no muestreadas = sin evidencia)
sp_cols <- names(pa_compat)[str_detect(names(pa_compat), "^sp_")]
pa_compat <- pa_compat %>%
  mutate(across(all_of(sp_cols), ~replace_na(., 0L)))

# --- 5b. Anadir informacion de esfuerzo de muestreo ---
# factor_incert: cuantifica la incertidumbre de las ausencias segun esfuerzo.
# Una cuadricula muestreada por 3+ metodos tiene ausencias mas fiables
# (factor = 0.3) que una no muestreada (factor = 1.0). Este factor se usa
# en Fase 3 para generar mapas de incertidumbre que reflejen la calidad
# heterogenea del muestreo en la Peninsula.
# O11: Umbrales de factor_incert leidos de CONFIG (configurable)
umbrales <- CONFIG$incertidumbre$factor_incert_umbrales
esfuerzo <- muestras_wide %>%
  mutate(
    muestreado = as.integer(n_metodos > 0),
    factor_incert = case_when(
      n_metodos == 0 ~ as.numeric(umbrales["0"]),
      n_metodos == 1 ~ as.numeric(umbrales["1"]),
      n_metodos == 2 ~ as.numeric(umbrales["2"]),
      n_metodos >= 3 ~ as.numeric(umbrales["3"])
    )
  )

n_pa_pre_esf <- nrow(pa_compat)
pa_compat <- pa_compat %>%
  left_join(
    esfuerzo %>% select(cuadricula_utm_10x10, starts_with("m_"), n_metodos, muestreado, factor_incert),
    by = "cuadricula_utm_10x10"
  ) %>%
  mutate(across(c(starts_with("m_"), n_metodos, muestreado), ~replace_na(., 0L)),
         factor_incert = replace_na(factor_incert, 1.0))
stopifnot(
  "Join pa_compat+esfuerzo perdio o duplico filas" = nrow(pa_compat) == n_pa_pre_esf
)
cat(sprintf("  Join pa_compat + esfuerzo: %d filas preservadas\n", nrow(pa_compat)))

# Renombrar para compatibilidad con el resto del pipeline (CUADRICULA es el ID estandar)
pa_compat <- pa_compat %>% rename(CUADRICULA = cuadricula_utm_10x10)

# Validacion global: la tabla pa_compat debe tener >= 5000 cuadriculas
validar_n_cuadriculas(pa_compat, min_rows = 5000,
                       context = "pa_compat (formato ancho) en 01g")
cat(sprintf("  Validacion de filas: %d cuadriculas (OK, >= 5000)\n", nrow(pa_compat)))

saveRDS(pa_compat, CONFIG$paths$pa_data)
saveRDS(esfuerzo, CONFIG$paths$esfuerzo)

cat(sprintf("[OK] Formato ancho: %s (%d cuadriculas, %d especies)\n",
            CONFIG$paths$pa_data, nrow(pa_compat), length(sp_cols)))
cat(sprintf("[OK] Esfuerzo: %s\n", CONFIG$paths$esfuerzo))

# --- 6. Resumen final ---
cat("\n=== RESUMEN FINAL ===\n")
cat(sprintf("  Cuadriculas totales: %d\n", nrow(pa_compat)))
cat(sprintf("  Cuadriculas muestreadas: %d\n", sum(pa_compat$muestreado, na.rm = TRUE)))
cat(sprintf("  Especies/complejos: %d\n", length(sp_cols)))
cat(sprintf("  Variables predictoras: %d\n", length(vars_pred)))
cat(sprintf("  Metodos: %s\n", paste(metodos, collapse = ", ")))
for (met in metodos) {
  cat(sprintf("    %s: %d cuadriculas\n", met, nrow(paxenv_list[[met]])))
}
