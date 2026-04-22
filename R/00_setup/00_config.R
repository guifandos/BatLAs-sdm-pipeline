# ==============================================================================
# 00_config.R - CONFIGURACION CENTRALIZADA
# ==============================================================================
#
# Archivo unico de configuracion para todo el pipeline de modelizacion
# Atlas de Murcielagos de la Peninsula Iberica (SECEMU)
#
# TODAS las rutas y parametros se definen aqui.
# Para modificar el comportamiento del pipeline, editar SOLO este archivo.
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

CONFIG <- list(

  # ============================================================================
  # RUTAS DE ARCHIVOS
  # ============================================================================
  # Todas las rutas son relativas a la raiz del proyecto.
  # Se organizan en: datos de entrada (brutos), procesados (intermedios),
  # metadatos (versionados) y salidas (JSONs, modelos, mapas).

  paths = list(

    # --- DATOS DE ENTRADA (brutos, NO en Git) ---
    # Estos archivos son proporcionados por el grupo de trabajo y no se
    # modifican durante el pipeline. Incluyen presencias, mallas UTM,
    # variables ambientales (Excel SEO) y geologia (CSVs).

    # Presencias originales: CSV con coordenadas UTM, especie, metodo
    # Se espera una columna 'especie_definitiva' con la asignacion final.
    presencias_raw = "data/raw/presencias/_final_coords_UTM_editada_20260416_v2_MODELOS.xlsx",

    # Directorio de variables ambientales (resoluciones 10x10)
    variables_dir = "data/raw/variables",

    # Shapefiles de malla UTM 10x10 km
    # Peninsula: UTM zona 30 (ETRS89)
    # Baleares: UTM zona 31 (se reproyecta a zona 30 durante carga)
    shapefile_peninsula = "data/raw/shapefiles/Malla10x10_clip.shp",
    shapefile_baleares = "data/raw/shapefiles/Malla10x10_BAL_Clip_nueva.shp",

    # Variables ambientales en Excel (proporcionadas por SEO)
    # EC = Espana Continental, BAL = Baleares, CANA = Canarias (excluidas)
    variables_excel_ec = "data/raw/variables/Variables_EC.xlsx",
    variables_excel_bal = "data/raw/variables/Variables_BAL.xlsx",
    variables_excel_cana = "data/raw/variables/Variables_CANA.xlsx",
    # Diccionario de codigos de variables (nombres cortos -> descriptivos)
    codigos_variables = "data/raw/variables/Codigos_variables.xlsx",

    # Datos suplementarios de presencias (archivos adicionales por especie)
    # 2026-04-17: vaciado para la corrida con la base definitiva. V. murinus queda
    # fuera del pipeline principal (tratamiento exploratorio aparte).
    presencias_suplementarias = NULL,

    # Variables geologicas: Karst (proporciones) y litologia (colores/tipos)
    karst_csv = "data/raw/variables/10x10_Karst_PIBAL.csv",
    lito_csv = "data/raw/variables/10x10_lito_COLOR_PIBAL.csv",

    # --- DATOS PROCESADOS (intermedios, NO en Git) ---
    # Generados por la Fase 0 (preparacion de datos). Son los inputs
    # para las fases de modelado.

    # Fase 0a: Presencias estandarizadas y PA por metodo
    presencias_std = "data/processed/presencias_std.rds",
    pa_metodo = "data/processed/pa_metodo.rds",
    muestras_metodo = "data/processed/muestras_metodo.rds",
    muestras_metodo_wide = "data/processed/muestras_metodo_wide.rds",
    tabla_cripticos = "data/processed/tabla_cripticos.rds",
    resumen_muestreo = "data/processed/resumen_muestreo.rds",
    candidatos_por_metodo = "data/processed/candidatos_por_metodo.rds",

    # Fase 0b: Mallas UTM (sf objects)
    malla_union = "data/processed/malla_union.rds",
    malla_peninsula = "data/processed/malla_peninsula.rds",
    malla_baleares = "data/processed/malla_baleares.rds",

    # Fase 0c-0f: Predictores ambientales + geologicos
    predictores_seo = "data/processed/predictores_SEO.rds",
    geo_features = "data/processed/geo_features.rds",
    predictores_seo_geo = "data/processed/predictores_SEO_GEO.rds",
    predictores_seo_geo_sf = "data/processed/predictores_SEO_GEO_sf.rds",

    # Fase 0g: PAxENV por metodo (listos para modelado)
    # Formato ancho: cuadriculas x (sp_especie + variables)
    modelado_ready_dir = "data/modelado_ready",
    paxenv_all = "data/modelado_ready/PAxENV_por_metodo_all.rds",
    paxenv_acustica = "data/modelado_ready/PAxENV_acustica.rds",
    paxenv_captura = "data/modelado_ready/PAxENV_captura.rds",
    paxenv_cuevas = "data/modelado_ready/PAxENV_cuevas.rds",
    paxenv_otros = "data/modelado_ready/PAxENV_otros.rds",

    # Compatibilidad con Fase 2+: formato ancho unificado (todos los metodos)
    pa_data = "data/processed/PAxENV_all_metodos.rds",
    esfuerzo = "data/processed/esfuerzo_por_metodo.rds",
    grid_predictores = "data/processed/predictores_SEO_GEO.rds",

    # --- METADATOS (versionados en Git) ---
    # CSVs de clasificacion ecologica de especies y variables.
    # especies_gremios: asigna cada especie a un gremio de refugio y alimentacion
    # gremios_refugio/alimentacion: define variables prioritarias por categoria
    especies_gremios = "data/metadata/especies_gremios.csv",
    gremios_refugio = "data/metadata/gremios_refugio.csv",
    gremios_alimentacion = "data/metadata/gremios_alimentacion.csv",
    complejos_taxonomicos = "data/metadata/complejos_taxonomicos.csv",
    diccionario_variables = "data/metadata/diccionario_variables.csv",

    # --- VARIABLES SELECCIONADAS (JSONs por especie) ---
    # Un JSON por especie con: variables finales, eliminadas, metricas, alertas
    variables_json = "output_version_final_20260417/seleccion_variables/variables_json"
  ),

  # --- RUTAS DE SALIDA ---
  # Directorios donde se guardan resultados de modelos, mapas, logs y chequeos.
  # El nombre de carpeta incluye la fecha del run para trazabilidad; adaptar
  # segun convenga en corridas posteriores.
  output = list(
    base = "output_version_final_20260417/modelos",     # Modelos con todos los datos
    seleccion = "output_version_final_20260417/seleccion_variables",  # JSONs y diagnosticos de seleccion
    logs = "output_version_final_20260417/logs",     # Logs de ejecucion
    checks = "output_version_final_20260417/checks", # Chequeos de calidad (QA)
    figs = "output_version_final_20260417/figs"      # Figuras y mapas finales
  ),

  # ============================================================================
  # PARAMETROS DE MODELIZACION
  # ============================================================================
  # Parametros para cada fase del pipeline de modelado. Los valores por defecto
  # son para produccion; se indican alternativas para pruebas rapidas.

  # --- MODELO AMBIENTAL (GLM) ---
  # GLM binomial con las variables seleccionadas en Fase 1.
  # Se usa hold-out (train/test split) + bootstrap para estimar incertidumbre.
  ambiental = list(
    prop_train = 0.70,       # Proporcion de datos para entrenamiento (70/30 split)
    n_bootstrap = 200,       # Iteraciones de bootstrap (produccion: 200; pruebas: 50)
    min_presencias = 30,     # Minimo de presencias para ajustar un modelo
    min_ausencias = 30,      # Minimo de ausencias para balanceo
    seed = 123               # Semilla para reproducibilidad
  ),

  # --- MODELO ESPACIAL (GAM / GLM polinomico) ---
  # Captura autocorrelacion espacial residual usando coordenadas como predictores.
  # Se comparan 3 metodos (glm2, glm3, gam) y se selecciona por AICc.
  espacial = list(
    metodos = c("glm2", "glm3", "gam"),  # Metodos a comparar
    k_gam = 30,             # Grados de libertad maximos para smooth terms en GAM
    k_gam_adaptativo = TRUE, # TRUE: k = min(k_gam, floor(n_pres/4)); FALSE: k fijo
    usar_residuos = FALSE,  # [EXPERIMENTAL — NO USAR EN PRODUCCION]
                            # TRUE activa 03b_bis_espacial_residuos.R, que reconstruye
                            # F_espacial como favorabilidad(p_amb + residuo_esp). En zonas
                            # sin presencias el residuo tiende a 0, por lo que F_esp_res
                            # colapsa a F_amb y la interseccion geometrica sqrt(F_amb*F_esp)
                            # degenera en F_amb, perdiendo por completo la funcion de
                            # mascara geografica. Esto produce favorabilidades altas
                            # espurias en el norte peninsular para especies termofilas
                            # (caso detectado 2026-04-10 con C. isabellinus, R. mehelyi, etc.).
                            # Mantener SIEMPRE en FALSE mientras se use interseccion fuzzy
                            # geometrica en 03c_interseccion_fuzzy.R.
    n_bootstrap = 200,      # Iteraciones de bootstrap (produccion: 200; pruebas: 50)
    seed = 123
  ),

  # --- INTERSECCION FUZZY ---
  # Combina favorabilidad ambiental y espacial.
  # "geometrica" = media geometrica (conservadora, penaliza valores bajos)
  interseccion = list(
    metodo = "geometrica",   # Opciones: "geometrica", "pmin", "compensatoria"
    gamma = 0.5              # Parametro para metodo compensatorio
  ),

  # --- VALIDACION CRUZADA ---
  # Evaluacion fuera de muestra con bloques espaciales (evita autocorrelacion
  # entre train y test). Con n_rep > 1, se repite la particion con diferentes
  # seeds para obtener estimaciones mas estables de AUC/TSS.
  validacion = list(
    k_folds = 5,             # Numero de folds
    metodo_bloques = "kmeans",  # Metodo para crear bloques espaciales
    n_rep = 10,              # Repeticiones de la CV (produccion: 10; pruebas: 1)
    seed = 123
  ),

  # --- INCERTIDUMBRE ---
  # Indice compuesto de incertidumbre basado en tres fuentes:
  #   MESS: extrapolacion ambiental (cuadriculas fuera del rango de training)
  #   Bootstrap: variabilidad de coeficientes del GLM
  #   Esfuerzo: heterogeneidad del muestreo por metodo
  incertidumbre = list(
    usar_mess = TRUE,
    usar_bootstrap = TRUE,
    usar_esfuerzo = TRUE,
    peso_mess = 0.33,        # Peso del componente MESS en indice final
    peso_bootstrap = 0.33,   # Peso del componente bootstrap
    peso_esfuerzo = 0.34,   # Peso del componente esfuerzo (los 3 deben sumar 1)
    pesos_adaptativos = TRUE, # TRUE: calibrar pesos por especie segun varianza de cada componente
    umbral_mess = -10,       # Umbral MESS para clasificar como extrapolacion
    max_metodos = 4,         # Maximo de metodos de muestreo considerados
    # Umbrales de factor_incert (por n_metodos de muestreo)
    factor_incert_umbrales = c(
      "0" = 1.0,   # No muestreada: maxima incertidumbre
      "1" = 0.7,   # Un solo metodo: incertidumbre alta
      "2" = 0.5,   # Dos metodos: incertidumbre media
      "3" = 0.3    # Tres+ metodos: incertidumbre baja
    )
  ),

  # ============================================================================
  # SELECCION DE VARIABLES
  # ============================================================================
  # Parametros para el pipeline de 7 fases de seleccion (02b).
  # Controlan umbrales de correlacion, multicolinealidad, ratio muestral,
  # y validacion predictiva.

  seleccion = list(
    correlation_threshold = 0.8,  # Umbral de correlacion para select07 (Munoz & Real)
    vif_threshold = 10,           # VIF maximo permitido (Dormann et al. 2013)
    ratio_Np = 8,                 # Ratio minimo presencias/parametros (Harrell's rule)
    min_gremio_final = 2,         # Minimo de variables de gremio en modelo final
    min_presencias = 30,          # Minimo de presencias para modelizar
    midsize_max_vars = 5,         # Max variables para modelo simple (30-59 presencias)
    max_vars_abs = 25,            # Tope absoluto de variables independiente de N (parsimonia)
    k_folds_validation = 5,       # Folds para validacion predictiva (fase 7)
    run_validation = TRUE,        # Ejecutar fase 7 (puede desactivarse para rapidez)
    stability_selection = FALSE,  # Desactivado temporalmente para rapidez
    n_boot_stability = 100        # Iteraciones de stability selection (produccion: 100)
  ),

  # ============================================================================
  # VISUALIZACION
  # ============================================================================
  # Parametros para los mapas del atlas (Fase 7).

  mapas = list(
    crs_salida = 25830,      # ETRS89/UTM zona 30N (CRS de salida para mapas)
    paleta_favorabilidad = "batlow",   # Paleta de color para favorabilidad
    paleta_incertidumbre = "lajolla",  # Paleta de color para incertidumbre
    dpi = 300,               # Resolucion de mapas exportados
    ancho_cm = 20,           # Ancho del mapa en cm
    alto_cm = 20,            # Alto del mapa en cm
    n_breaks = 5             # Numero de cortes en la leyenda
  ),

  # ============================================================================
  # ESPECIES Y CONTROL DE EJECUCION
  # ============================================================================
  # Controla que especies se procesan y que fases se ejecutan.

  especies = list(
    # NULL = procesar todas las disponibles en CSV de gremios
    piloto = NULL,  # NULL = todas las especies modelizables
    # Ejemplo para prueba rapida (descomentar):
    # piloto = c("Rhinolophus ferrumequinum", "Myotis myotis"),
    # Especies a excluir explicitamente del pipeline
    excluir = c()
  ),

  # --- FILTRO TEMPORAL ---
  # Si anio_min no es NULL, solo se usan presencias con año >= anio_min.
  # Util para analisis de sensibilidad temporal o para excluir datos historicos.
  datos = list(
    anio_min = NULL            # Sin filtro temporal (todos los datos)
  ),

  # Control de ejecucion: activa/desactiva fases individuales.
  # force_rerun = TRUE recalcula especies ya procesadas.
  # 2026-04-17: corrida completa con base definitiva. PAxENV ya regenerado y
  # validado (29 especies modelables coinciden con expectativa).
  control = list(
    force_rerun = TRUE,    # TRUE: datos cambiaron, re-procesar todo
    ejecutar = list(
      preparacion_datos = FALSE,     # Fase 0: ya ejecutada en paso previo
      seleccion_variables = TRUE,    # Fase 1: seleccion de variables
      modelo_ambiental = TRUE,       # Fase 2: GLM + favorabilidad ambiental
      modelo_espacial = TRUE,        # Fase 3: GAM/GLM espacial
      interseccion = TRUE,           # Fase 4: interseccion fuzzy
      validacion = TRUE,             # Fase 5: validacion cruzada espacial
      incertidumbre = TRUE,          # Fase 6: indice de incertidumbre
      mapas = TRUE,                  # Fase 7: mapas del atlas
      qa_mapas = FALSE               # Subfase 0h: mapas de chequeo (QA)
    ),
    n_cores = 1,           # Numero de nucleos para paralelizacion
    usar_parallel = FALSE  # Activar ejecucion paralela
  ),

  # ============================================================================
  # LOGGING
  # ============================================================================
  # Nivel de detalle del log y destinos de salida.

  logging = list(
    nivel = "INFO",      # Niveles: "DEBUG", "INFO", "WARN", "ERROR"
    archivo = TRUE,      # Guardar log en archivo (output/logs/)
    consola = TRUE       # Imprimir log en consola
  )
)

# ==============================================================================
# VALIDACION DE CONFIGURACION
# ==============================================================================
# Verifica que la configuracion es consistente antes de ejecutar el pipeline.
# Comprueba: existencia de archivos criticos, validez de parametros numericos,
# y consistencia entre pesos. Se llama desde run_pipeline.R al inicio.

validar_config <- function() {

  errores <- c()

  # --- Verificar archivos de metadatos (siempre necesarios) ---
  archivos_metadata <- c(
    CONFIG$paths$especies_gremios,
    CONFIG$paths$gremios_refugio,
    CONFIG$paths$gremios_alimentacion
  )

  for (ruta in archivos_metadata) {
    if (!file.exists(ruta)) {
      errores <- c(errores, sprintf("Archivo no encontrado: %s", ruta))
    }
  }

  # --- Si preparacion_datos esta activa, verificar entradas brutas ---
  if (isTRUE(CONFIG$control$ejecutar$preparacion_datos)) {
    # Presencias
    if (!file.exists(CONFIG$paths$presencias_raw)) {
      errores <- c(errores, sprintf("Presencias no encontradas: %s", CONFIG$paths$presencias_raw))
    }
    # Shapefiles
    if (!file.exists(CONFIG$paths$shapefile_peninsula)) {
      errores <- c(errores, sprintf("Shapefile peninsula no encontrado: %s", CONFIG$paths$shapefile_peninsula))
    }

    # Archivos Excel de variables ambientales (necesarios para 01c)
    archivos_excel <- c(
      CONFIG$paths$variables_excel_ec,
      CONFIG$paths$variables_excel_bal,
      CONFIG$paths$codigos_variables
    )
    for (ruta in archivos_excel) {
      if (!file.exists(ruta)) {
        errores <- c(errores, sprintf("Excel de variables no encontrado: %s", ruta))
      }
    }

    # CSVs de geologia (necesarios para 01e)
    if (!file.exists(CONFIG$paths$karst_csv)) {
      errores <- c(errores, sprintf("CSV de Karst no encontrado: %s", CONFIG$paths$karst_csv))
    }
    if (!file.exists(CONFIG$paths$lito_csv)) {
      errores <- c(errores, sprintf("CSV de litologia no encontrado: %s", CONFIG$paths$lito_csv))
    }
  }

  # --- Verificar parametros numericos de modelizacion ---
  if (CONFIG$ambiental$prop_train <= 0 || CONFIG$ambiental$prop_train >= 1) {
    errores <- c(errores, "prop_train debe estar entre 0 y 1")
  }

  if (CONFIG$validacion$k_folds < 2) {
    errores <- c(errores, "k_folds debe ser >= 2")
  }

  # --- Verificar parametros de seleccion son numeros positivos ---
  seleccion_params <- list(
    correlation_threshold = CONFIG$seleccion$correlation_threshold,
    vif_threshold = CONFIG$seleccion$vif_threshold,
    ratio_Np = CONFIG$seleccion$ratio_Np,
    min_gremio_final = CONFIG$seleccion$min_gremio_final,
    min_presencias = CONFIG$seleccion$min_presencias,
    midsize_max_vars = CONFIG$seleccion$midsize_max_vars,
    k_folds_validation = CONFIG$seleccion$k_folds_validation
  )
  for (param_name in names(seleccion_params)) {
    val <- seleccion_params[[param_name]]
    if (!is.numeric(val) || length(val) != 1 || val <= 0) {
      errores <- c(errores, sprintf("seleccion$%s debe ser un numero positivo (actual: %s)",
                                    param_name, deparse(val)))
    }
  }

  # Correlation threshold debe estar entre 0 y 1
  if (is.numeric(CONFIG$seleccion$correlation_threshold) &&
      (CONFIG$seleccion$correlation_threshold <= 0 || CONFIG$seleccion$correlation_threshold > 1)) {
    errores <- c(errores, "seleccion$correlation_threshold debe estar entre 0 y 1")
  }

  # --- Verificar pesos de incertidumbre suman 1 ---
  suma_pesos <- CONFIG$incertidumbre$peso_mess +
    CONFIG$incertidumbre$peso_bootstrap +
    CONFIG$incertidumbre$peso_esfuerzo

  if (abs(suma_pesos - 1.0) > 0.01) {
    errores <- c(errores, sprintf("Pesos de incertidumbre no suman 1: %.2f", suma_pesos))
  }

  # --- Reportar errores o confirmar ---
  if (length(errores) > 0) {
    cat("\nERRORES DE CONFIGURACION:\n")
    for (err in errores) {
      cat(sprintf("   - %s\n", err))
    }
    stop("Configuracion invalida")
  }

  cat("[OK] Configuracion validada correctamente\n")
}

# ==============================================================================
# IMPRIMIR CONFIGURACION
# ==============================================================================

print_config <- function() {
  cat("\n")
  cat("================================================================================\n")
  cat("  CONFIGURACION DEL PIPELINE - ATLAS MURCIELAGOS SECEMU\n")
  cat("================================================================================\n\n")

  cat("RUTAS:\n")
  cat(sprintf("  - PA data: %s\n", CONFIG$paths$pa_data))
  cat(sprintf("  - PAxENV dir: %s\n", CONFIG$paths$modelado_ready_dir))
  cat(sprintf("  - Grid: %s\n", CONFIG$paths$grid_predictores))
  cat(sprintf("  - Output: %s\n", CONFIG$output$base))

  cat("\nMODELIZACION:\n")
  cat(sprintf("  - Bootstrap: %d iteraciones\n", CONFIG$ambiental$n_bootstrap))
  cat(sprintf("  - Hold-out: %.0f%% train / %.0f%% test\n",
              CONFIG$ambiental$prop_train * 100,
              (1 - CONFIG$ambiental$prop_train) * 100))
  cat(sprintf("  - CV folds: %d (metodo: %s)\n",
              CONFIG$validacion$k_folds,
              CONFIG$validacion$metodo_bloques))

  cat("\nFASES A EJECUTAR:\n")
  fases <- CONFIG$control$ejecutar
  for (fase in names(fases)) {
    status <- if (fases[[fase]]) "[SI]" else "[NO]"
    cat(sprintf("  %s %s\n", status, fase))
  }

  if (!is.null(CONFIG$especies$piloto)) {
    cat(sprintf("\nESPECIES PILOTO: %d especies\n", length(CONFIG$especies$piloto)))
  } else {
    cat("\nESPECIES: Todas las disponibles\n")
  }

  cat("\n================================================================================\n\n")
}

# ==============================================================================
# VALIDACION DE METADATOS ECOLOGICOS
# ==============================================================================
# Verifica la coherencia interna de los CSVs de metadatos (gremios, complejos,
# diccionario) ANTES de ejecutar cualquier fase. Detecta errores que de otro
# modo producirian modelos silenciosamente incorrectos.
#
# Se llama desde run_pipeline.R y desde la vineta 00_inicio_rapido.R.
# ==============================================================================

validar_metadata <- function(strict = TRUE) {

  errores <- c()
  avisos  <- c()

  cat("\n--- Validando metadatos ecologicos ---\n")

  # --- 1. Cargar CSVs ---
  if (!file.exists(CONFIG$paths$especies_gremios)) {
    stop(sprintf("No se encuentra especies_gremios: %s", CONFIG$paths$especies_gremios))
  }
  if (!file.exists(CONFIG$paths$gremios_refugio)) {
    stop(sprintf("No se encuentra gremios_refugio: %s", CONFIG$paths$gremios_refugio))
  }
  if (!file.exists(CONFIG$paths$gremios_alimentacion)) {
    stop(sprintf("No se encuentra gremios_alimentacion: %s", CONFIG$paths$gremios_alimentacion))
  }

  esp_tbl  <- read.csv(CONFIG$paths$especies_gremios, stringsAsFactors = FALSE)
  ref_tbl  <- read.csv(CONFIG$paths$gremios_refugio, stringsAsFactors = FALSE)
  alim_tbl <- read.csv(CONFIG$paths$gremios_alimentacion, stringsAsFactors = FALSE)

  # --- 2. Columnas requeridas ---
  cols_esp <- c("especie", "refugio", "alimentacion", "modelar")
  faltantes <- setdiff(cols_esp, names(esp_tbl))
  if (length(faltantes) > 0) {
    errores <- c(errores, sprintf(
      "especies_gremios.csv le faltan columnas: %s", paste(faltantes, collapse = ", ")))
  }

  if (!"categoria" %in% names(ref_tbl)) {
    errores <- c(errores, "gremios_refugio.csv no tiene columna 'categoria'")
  }
  if (!"categoria" %in% names(alim_tbl)) {
    errores <- c(errores, "gremios_alimentacion.csv no tiene columna 'categoria'")
  }

  # --- 3. Categorias de gremio validas ---
  cats_refugio_validas <- ref_tbl$categoria
  cats_alim_validas    <- alim_tbl$categoria

  cats_refugio_usadas <- unique(esp_tbl$refugio[!is.na(esp_tbl$refugio)])
  cats_alim_usadas    <- unique(esp_tbl$alimentacion[!is.na(esp_tbl$alimentacion)])

  bad_ref <- setdiff(cats_refugio_usadas, cats_refugio_validas)
  if (length(bad_ref) > 0) {
    errores <- c(errores, sprintf(
      "Categorias de refugio en especies_gremios.csv no definidas en gremios_refugio.csv: %s\n  Validas: %s",
      paste(bad_ref, collapse = ", "), paste(cats_refugio_validas, collapse = ", ")))
  }

  bad_alim <- setdiff(cats_alim_usadas, cats_alim_validas)
  if (length(bad_alim) > 0) {
    errores <- c(errores, sprintf(
      "Categorias de alimentacion en especies_gremios.csv no definidas en gremios_alimentacion.csv: %s\n  Validas: %s",
      paste(bad_alim, collapse = ", "), paste(cats_alim_validas, collapse = ", ")))
  }

  # --- 4. Espacios trailing / encoding en nombres de especie ---
  nombres_raw <- esp_tbl$especie
  nombres_trim <- trimws(nombres_raw)
  con_espacios <- nombres_raw[nombres_raw != nombres_trim]
  if (length(con_espacios) > 0) {
    errores <- c(errores, sprintf(
      "Especies con espacios trailing/leading en especies_gremios.csv: '%s'",
      paste(con_espacios, collapse = "', '")))
  }

  # --- 5. Especies duplicadas ---
  dupl <- nombres_trim[duplicated(nombres_trim)]
  if (length(dupl) > 0) {
    errores <- c(errores, sprintf(
      "Especies duplicadas en especies_gremios.csv: %s", paste(dupl, collapse = ", ")))
  }

  # --- 6. Complejos taxonomicos ---
  if (file.exists(CONFIG$paths$complejos_taxonomicos)) {
    comp_tbl <- read.csv(CONFIG$paths$complejos_taxonomicos, stringsAsFactors = FALSE)

    # 6a. Todas las especies de complejos deben existir en especies_gremios
    all_sp_in_complex <- unique(trimws(unlist(strsplit(comp_tbl$especies_incluidas, ",\\s*"))))
    missing_from_main <- setdiff(all_sp_in_complex, nombres_trim)
    if (length(missing_from_main) > 0) {
      errores <- c(errores, sprintf(
        "Especies en complejos_taxonomicos.csv no encontradas en especies_gremios.csv: %s",
        paste(missing_from_main, collapse = ", ")))
    }

    # 6b. Ninguna especie en mas de un complejo
    sp_to_comp <- data.frame(
      especie = trimws(unlist(strsplit(comp_tbl$especies_incluidas, ",\\s*"))),
      complejo = rep(comp_tbl$complejo, lengths(strsplit(comp_tbl$especies_incluidas, ",\\s*"))),
      stringsAsFactors = FALSE
    )
    sp_counts <- table(sp_to_comp$especie)
    duplicados <- names(sp_counts[sp_counts > 1])
    if (length(duplicados) > 0) {
      for (sp in duplicados) {
        comps <- sp_to_comp$complejo[sp_to_comp$especie == sp]
        errores <- c(errores, sprintf(
          "Especie '%s' aparece en multiples complejos: %s", sp, paste(comps, collapse = ", ")))
      }
    }

    # 6c. n_especies coincide con el conteo real
    for (i in seq_len(nrow(comp_tbl))) {
      spp <- trimws(unlist(strsplit(comp_tbl$especies_incluidas[i], ",\\s*")))
      if ("n_especies" %in% names(comp_tbl) && !is.na(comp_tbl$n_especies[i])) {
        if (length(spp) != comp_tbl$n_especies[i]) {
          avisos <- c(avisos, sprintf(
            "Complejo '%s': n_especies=%d pero hay %d especies listadas",
            comp_tbl$complejo[i], comp_tbl$n_especies[i], length(spp)))
        }
      }
    }

    # 6d. Nombres de complejos no colisionan con nombres de especies reales
    collision <- intersect(comp_tbl$complejo, nombres_trim)
    if (length(collision) > 0) {
      errores <- c(errores, sprintf(
        "Nombres de complejos colisionan con nombres de especies reales: %s",
        paste(collision, collapse = ", ")))
    }

    # 6e. Marcador 'complejo' en especies_gremios.csv es coherente
    if ("complejo" %in% names(esp_tbl)) {
      for (i in seq_len(nrow(comp_tbl))) {
        spp <- trimws(unlist(strsplit(comp_tbl$especies_incluidas[i], ",\\s*")))
        comp_name <- comp_tbl$complejo[i]
        for (sp in spp) {
          sp_row <- esp_tbl[esp_tbl$especie == sp, ]
          if (nrow(sp_row) > 0) {
            marcador <- sp_row$complejo[1]
            if (is.na(marcador) || marcador == "") {
              avisos <- c(avisos, sprintf(
                "Especie '%s' esta en complejo '%s' pero no tiene marcador en especies_gremios.csv",
                sp, comp_name))
            } else if (marcador != comp_name) {
              errores <- c(errores, sprintf(
                "Especie '%s': marcador complejo='%s' pero pertenece a '%s' en complejos_taxonomicos.csv",
                sp, marcador, comp_name))
            }
          }
        }
      }
    }
  }

  # --- 7. Especies con modelar=TRUE pero sin refugio o alimentacion ---
  modelables <- esp_tbl[esp_tbl$modelar == TRUE, ]
  sin_refugio <- modelables$especie[is.na(modelables$refugio) | modelables$refugio == ""]
  sin_alim    <- modelables$especie[is.na(modelables$alimentacion) | modelables$alimentacion == ""]
  if (length(sin_refugio) > 0) {
    errores <- c(errores, sprintf(
      "Especies con modelar=TRUE pero sin refugio: %s", paste(sin_refugio, collapse = ", ")))
  }
  if (length(sin_alim) > 0) {
    errores <- c(errores, sprintf(
      "Especies con modelar=TRUE pero sin alimentacion: %s", paste(sin_alim, collapse = ", ")))
  }

  # --- Reportar avisos ---
  if (length(avisos) > 0) {
    cat("\n  AVISOS:\n")
    for (a in avisos) cat(sprintf("    [!] %s\n", a))
  }

  # --- Reportar errores ---
  if (length(errores) > 0) {
    cat("\n  ERRORES DE METADATOS:\n")
    for (err in errores) cat(sprintf("    [X] %s\n", err))
    if (strict) {
      stop(sprintf("Validacion de metadatos fallida: %d errores. Corregir CSVs antes de continuar.",
                    length(errores)))
    } else {
      warning(sprintf("Validacion de metadatos: %d errores (modo no-estricto, continuando)",
                      length(errores)))
    }
  } else {
    cat("  [OK] Metadatos validados correctamente\n")
  }

  invisible(list(errores = errores, avisos = avisos))
}

message("[OK] Configuracion cargada: CONFIG")
