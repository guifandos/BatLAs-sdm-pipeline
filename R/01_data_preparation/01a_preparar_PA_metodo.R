# ==============================================================================
# 01a_preparar_PA_metodo.R - Preparar PA por metodo y complejos cripticos
# ==============================================================================
#
# PROPOSITO:
#   Este script construye la tabla de Presencia/Ausencia (PA) por metodo de
#   muestreo para cada especie (o complejo criptico) en cada cuadricula UTM
#   10x10 km. Es el primer paso del pipeline de preparacion de datos.
#
#   La PA por metodo es fundamental porque cada tecnica de muestreo tiene un
#   sesgo de deteccion diferente (probabilidad de detectar una especie dado que
#   esta presente). Si mezclaramos todos los metodos, no podriamos distinguir
#   si una ausencia es real o simplemente resultado de no haber usado el metodo
#   adecuado en esa cuadricula.
#
# INPUT:  CONFIG$paths$presencias_raw          - CSV bruto con registros de presencias
#         CONFIG$paths$complejos_taxonomicos    - CSV con complejos de especies cripticas
#
# OUTPUT: CONFIG$paths$presencias_std          - Presencias estandarizadas (RDS)
#         CONFIG$paths$pa_metodo               - PA por metodo en formato largo (RDS)
#         CONFIG$paths$muestras_metodo         - Esfuerzo por cuadricula/metodo (RDS)
#         CONFIG$paths$muestras_metodo_wide    - Esfuerzo en formato ancho (RDS)
#         CONFIG$paths$tabla_cripticos         - Tabla de complejos taxonomicos (RDS)
#         CONFIG$paths$resumen_muestreo        - Resumen sp x metodo (RDS)
#         CONFIG$paths$candidatos_por_metodo   - Especies candidatas a modelizar (RDS)
#
# AUTOR:  Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

# --- BUG 7 FIX: Carga condicional de configuracion ---
# Cuando este script se ejecuta como parte del pipeline completo (run_pipeline.R),
# CONFIG ya esta cargado en el entorno global. Si se ejecuta de forma aislada
# (e.g., durante desarrollo/depuracion), necesitamos cargarlo. Evitamos
# re-sourcing innecesario que podria sobreescribir modificaciones en memoria.
if (!exists("CONFIG")) source("R/00_setup/00_config.R")

source("R/utils/utils_checkpoints.R")

suppressPackageStartupMessages(library(tidyverse))

cat("\n=== 01a: PREPARAR PA POR METODO Y COMPLEJOS ===\n\n")

# ==============================================================================
# 1. CARGAR PRESENCIAS CON AUTO-DETECCION DE SEPARADOR (BUG 3 FIX)
# ==============================================================================
# Los CSVs en Espana usan frecuentemente punto y coma como separador (formato
# europeo con comas decimales), pero algunos CSVs pueden usar coma estandar.
# En lugar de asumir un formato fijo (read_csv vs read_csv2), intentamos ambos.
#
# Estrategia: leer primero con read_csv (separador coma). Si el resultado tiene
# una sola columna, probablemente el separador real es punto y coma, asi que
# reintentamos con read_csv2. Esto evita errores silenciosos donde todo el
# contenido se lee en una unica columna.
# ------------------------------------------------------------------------------

cat("Cargando presencias desde:", CONFIG$paths$presencias_raw, "\n")

# Auto-deteccion de formato: Excel (.xlsx) vs CSV
if (str_detect(CONFIG$paths$presencias_raw, "\\.xlsx$")) {
  # --- EXCEL: usar readxl (encoding UTF-8 nativo) ---
  suppressPackageStartupMessages(library(readxl))
  presencias <- read_excel(CONFIG$paths$presencias_raw)
  cat("  -> Formato Excel detectado\n")
  # Limpiar encoding (Excel suele ser UTF-8 pero por seguridad)
  presencias <- presencias %>%
    mutate(across(where(is.character),
                  ~iconv(., to = "UTF-8", sub = "")))
} else {
  # --- CSV: auto-deteccion de separador (coma vs punto y coma) ---
  presencias <- tryCatch({
    tmp <- read_csv(CONFIG$paths$presencias_raw,
                    locale = locale(encoding = "latin1"),
                    show_col_types = FALSE)
    if (ncol(tmp) <= 1) {
      cat("  -> read_csv produjo 1 columna; reintentando con read_csv2 (sep ';')\n")
      tmp <- read_csv2(CONFIG$paths$presencias_raw,
                       locale = locale(encoding = "latin1"),
                       show_col_types = FALSE)
    }
    tmp
  }, error = function(e) {
    cat("  -> read_csv fallo:", conditionMessage(e), "\n")
    cat("  -> Reintentando con read_csv2 (sep ';')\n")
    read_csv2(CONFIG$paths$presencias_raw,
              locale = locale(encoding = "latin1"),
              show_col_types = FALSE)
  })
  # Limpiar encoding latin1 -> UTF-8
  presencias <- presencias %>%
    mutate(across(where(is.character),
                  ~iconv(., from = "latin1", to = "UTF-8", sub = "")))
}

cat("Registros cargados:", nrow(presencias), "\n")
cat("Columnas:", ncol(presencias), "\n")
cat("Nombres de columnas:", paste(names(presencias), collapse = ", "), "\n\n")


# ==============================================================================
# 2. AUTO-DETECCION DE COLUMNAS CLAVE (BUG 4/5 FIX)
# ==============================================================================
# Diferentes versiones del CSV de presencias pueden tener nombres de columnas
# distintos (e.g., por diferentes fuentes de datos, actualizaciones del formato,
# o exportaciones desde distintos programas). En lugar de fallar silenciosamente
# cuando un nombre no coincide, buscamos entre candidatos conocidos.
#
# Si no encontramos ninguno, el script falla con un mensaje claro indicando
# que columnas se buscaron y cuales existen realmente.
# ------------------------------------------------------------------------------

# --- 2a. Columna de especie ---
# La columna de especie es el nombre cientifico del taxon detectado.
# "especie_definitiva" es el nombre canonico tras revision taxonomica.
candidatos_especie <- c("especie_definitiva", "especie", "ESPECIE",
                        "species", "nombre_cientifico")

col_especie <- NULL
for (cand in candidatos_especie) {
  if (cand %in% names(presencias)) {
    col_especie <- cand
    break
  }
}

if (is.null(col_especie)) {
  stop(sprintf(
    paste0("No se encontro columna de especie.\n",
           "  Candidatos buscados: %s\n",
           "  Columnas disponibles: %s"),
    paste(candidatos_especie, collapse = ", "),
    paste(names(presencias), collapse = ", ")
  ))
}

# Renombrar a nombre canonico si es necesario
if (col_especie != "especie_definitiva") {
  cat("  Columna de especie detectada: '", col_especie,
      "' -> renombrando a 'especie_definitiva'\n")
  presencias <- presencias %>% rename(especie_definitiva = !!sym(col_especie))
} else {
  cat("  Columna de especie: 'especie_definitiva'\n")
}

# --- 2b. Columna de metodologia ---
# La metodologia de muestreo determina el sesgo de deteccion.
# Diferentes nombres reflejan variaciones en la fuente de datos.
candidatos_metodologia <- c("metodologia", "metodo", "METODOLOGIA",
                            "metodo_campo", "metodo_muestreo")

col_metodologia <- NULL
for (cand in candidatos_metodologia) {
  if (cand %in% names(presencias)) {
    col_metodologia <- cand
    break
  }
}

if (is.null(col_metodologia)) {
  stop(sprintf(
    paste0("No se encontro columna de metodologia.\n",
           "  Candidatos buscados: %s\n",
           "  Columnas disponibles: %s"),
    paste(candidatos_metodologia, collapse = ", "),
    paste(names(presencias), collapse = ", ")
  ))
}

# Renombrar a nombre canonico si es necesario
if (col_metodologia != "metodologia") {
  cat("  Columna de metodologia detectada: '", col_metodologia,
      "' -> renombrando a 'metodologia'\n")
  presencias <- presencias %>% rename(metodologia = !!sym(col_metodologia))
} else {
  cat("  Columna de metodologia: 'metodologia'\n")
}

# --- 2c. Columna de cuadricula UTM ---
# La cuadricula UTM 10x10 km es la unidad espacial de analisis.
# Diferentes formatos usan distintos nombres para esta columna.
candidatos_cuadricula <- c("cuadricula_utm_10x10", "CUADRICULA",
                           "cuadricula", "UTM_10x10KM")

col_cuadricula <- NULL
for (cand in candidatos_cuadricula) {
  if (cand %in% names(presencias)) {
    col_cuadricula <- cand
    break
  }
}

if (is.null(col_cuadricula)) {
  stop(sprintf(
    paste0("No se encontro columna de cuadricula UTM.\n",
           "  Candidatos buscados: %s\n",
           "  Columnas disponibles: %s"),
    paste(candidatos_cuadricula, collapse = ", "),
    paste(names(presencias), collapse = ", ")
  ))
}

# Renombrar a nombre canonico si es necesario
if (col_cuadricula != "cuadricula_utm_10x10") {
  cat("  Columna de cuadricula detectada: '", col_cuadricula,
      "' -> renombrando a 'cuadricula_utm_10x10'\n")
  presencias <- presencias %>%
    rename(cuadricula_utm_10x10 = !!sym(col_cuadricula))
} else {
  cat("  Columna de cuadricula: 'cuadricula_utm_10x10'\n")
}

cat("\n")


# ==============================================================================
# 3. NORMALIZAR IDs DE CUADRICULA
# ==============================================================================
# Los codigos UTM pueden tener espacios, minusculas, o formatos inconsistentes
# entre fuentes de datos. norm_id() (de utils_checkpoints.R) estandariza:
#   - Elimina espacios en blanco
#   - Convierte a mayusculas
#   - Aplica str_squish (multiples espacios -> uno)
# Esto es critico para que los joins con la malla (shapefile) y los predictores
# funcionen correctamente.
# ------------------------------------------------------------------------------

presencias$cuadricula_utm_10x10 <- norm_id(presencias$cuadricula_utm_10x10)

# Diagnostico de normalizacion
n_cuads_unicas <- n_distinct(presencias$cuadricula_utm_10x10)
cat(sprintf("IDs de cuadricula normalizados (mayusculas, sin espacios): %d IDs unicos\n", n_cuads_unicas))
cat(sprintf("  Ejemplo IDs: %s\n\n",
            paste(head(unique(presencias$cuadricula_utm_10x10), 5), collapse = ", ")))


# ==============================================================================
# 4. FILTRAR CANARIAS (zona UTM 28R)
# ==============================================================================
# Las Islas Canarias pertenecen a la region biogeografica Macaronesica, con una
# fauna de murcielagos muy diferente a la ibero-balear (region Mediterranea y
# Atlantica). Las Canarias:
#   - Tienen especies endemicas no presentes en la Peninsula (e.g., Plecotus teneriffae)
#   - Carecen de muchas especies peninsulares comunes
#   - Estan en la zona UTM 28R, incompatible con el CRS del proyecto (ETRS89/UTM 30N)
#   - Tienen variables ambientales con rangos muy diferentes (clima subtropical)
#
# Por todo ello, incluir Canarias en los modelos peninsulares introduciria
# artefactos graves en las predicciones. Se excluyen filtrando cuadriculas que
# comienzan con "28R".
# ------------------------------------------------------------------------------

n_antes <- nrow(presencias)
presencias <- presencias %>%
  filter(!str_detect(cuadricula_utm_10x10, "^28R"))

n_eliminados <- n_antes - nrow(presencias)
cat("Registros tras filtrar Canarias:", nrow(presencias),
    "(eliminados:", n_eliminados, ")\n\n")


# ==============================================================================
# 4b. FILTRO TEMPORAL (si CONFIG$datos$anio_min no es NULL)
# ==============================================================================
# Permite restringir el analisis a datos recientes (e.g., >= 2014).
# La columna 'año' debe existir en los datos crudos.
# ------------------------------------------------------------------------------

if (!is.null(CONFIG$datos$anio_min)) {

  # Auto-deteccion de columna de año
  candidatos_anio <- c("año", "anio", "year", "ano")
  col_anio <- NULL
  for (cand in candidatos_anio) {
    if (cand %in% names(presencias)) {
      col_anio <- cand
      break
    }
  }

  if (is.null(col_anio)) {
    # Intentar extraer de columna fecha
    candidatos_fecha <- c("fecha", "date", "FECHA")
    col_fecha <- NULL
    for (cand in candidatos_fecha) {
      if (cand %in% names(presencias)) {
        col_fecha <- cand
        break
      }
    }
    if (!is.null(col_fecha)) {
      cat("  Columna 'año' no encontrada; extrayendo de '", col_fecha, "'\n")
      presencias$año <- as.integer(format(presencias[[col_fecha]], "%Y"))
      col_anio <- "año"
    } else {
      stop("Filtro temporal activo pero no se encontro columna de año ni fecha.")
    }
  }

  n_antes_anio <- nrow(presencias)
  n_sin_anio <- sum(is.na(presencias[[col_anio]]))

  presencias <- presencias %>%
    filter(!is.na(.data[[col_anio]]),
           .data[[col_anio]] >= CONFIG$datos$anio_min)

  n_filtrados <- n_antes_anio - nrow(presencias)
  cat(sprintf("FILTRO TEMPORAL: año >= %d\n", CONFIG$datos$anio_min))
  cat(sprintf("  Registros antes: %d (sin año: %d)\n", n_antes_anio, n_sin_anio))
  cat(sprintf("  Registros eliminados: %d\n", n_filtrados))
  cat(sprintf("  Registros restantes: %d\n\n", nrow(presencias)))
}


# ==============================================================================
# 5. CLASIFICAR METODOLOGIAS DE MUESTREO
# ==============================================================================
# Las metodologias de campo se agrupan en 4 categorias principales porque el
# sesgo de deteccion difiere fundamentalmente entre ellas:
#
#   ACUSTICA: Detectores de ultrasonidos (Anabat, Batcorder, SM2, etc.)
#     - Detecta especies en vuelo, sesgada hacia especies con ecolocacion potente
#     - No detecta bien especies de vuelo lento/gleaner (Rhinolophus, Plecotus)
#     - Cobertura espacial amplia pero variable segun dispositivo/noche
#
#   CAPTURA: Redes de niebla, trampas arpa, capturas manuales
#     - Detecta bien especies de vuelo lento que pasan desapercibidas acusticamente
#     - Sesgada hacia especies que vuelan a baja altura y cerca de vegetacion
#     - Permite identificacion morfologica precisa (critico para complejos cripticos)
#
#   CUEVAS: Prospeccion de refugios (cuevas, minas, colonias, hibernaculos)
#     - Detecta bien especies cavernicolas y trogloxenas
#     - Muy sesgada hacia especies gregarias que forman colonias visibles
#     - No detecta especies fisurricolas o arboricolas
#
#   OTROS: Atropellos, hallazgos casuales, citas bibliograficas, etc.
#     - Datos oportunistas sin protocolo estandarizado
#     - Se incluyen porque aportan presencias valiosas, pero no definen ausencias
#       fiables (la ausencia de hallazgo casual no indica ausencia real)
#
# La clasificacion se basa en coincidencia de patrones (regex) en texto libre del
# campo de metodologia original, lo que permite absorber variaciones de escritura.
# ------------------------------------------------------------------------------

presencias <- presencias %>%
  mutate(
    metodo = case_when(
      str_detect(tolower(metodologia),
                 "acust|ultrasound|bat.?detect|batcorder|sm2|anabat|grabador") ~ "acustica",
      str_detect(tolower(metodologia),
                 "captur|red|mist.?net|trampa|harp") ~ "captura",
      str_detect(tolower(metodologia),
                 "cueva|refugio|colonia|hibern|cave|roost|mina") ~ "cuevas",
      TRUE ~ "otros"
    )
  )

cat("Metodologias clasificadas:\n")
print(table(presencias$metodo, useNA = "ifany"))
cat("\n")


# ==============================================================================
# 6. COMPLEJOS CRIPTICOS (ESPECIES INDISTINGUIBLES)
# ==============================================================================
# Muchas especies de murcielagos son indistinguibles con determinados metodos:
#
#   - Myotis myotis / M. blythii: Frecuencia modulada (FM) identica en
#     ecolocacion. Solo separables por morfometria craneal detallada.
#
#   - Myotis escalerai / M. crypticus: Especie criptica descrita recientemente
#     (Juste et al. 2019). Morfologia casi identica, requiere genetica.
#
#   - Plecotus auritus / P. austriacus / P. macrobullaris: Emiten ecolocacion
#     de muy baja intensidad (FM whispering bats). Separacion fiable solo con
#     morfometria craneal o genetica.
#
# Para evitar asignar distribuciones erroneas a especies individuales cuando la
# identificacion no es fiable, las agrupamos en complejos. Esto es
# conservador pero honesto: mejor modelar "Myotis_grande" que atribuir
# registros incorrectamente a M. myotis o M. blythii.
#
# Los complejos se leen desde un CSV de metadatos que puede actualizarse cuando
# mejore el conocimiento taxonomico o se apliquen nuevas tecnicas de ID.
# ------------------------------------------------------------------------------

if (file.exists(CONFIG$paths$complejos_taxonomicos)) {
  complejos_csv <- read_csv(CONFIG$paths$complejos_taxonomicos,
                            show_col_types = FALSE)

  # Expandir el CSV: cada fila tiene un complejo con N especies separadas por coma.
  # Lo convertimos a formato largo (una fila por especie -> complejo)
  cripticos <- complejos_csv %>%
    mutate(especies = str_split(especies_incluidas, ",\\s*")) %>%
    select(complejo, especies) %>%
    unnest(especies) %>%
    rename(sp_original = especies, sp_complejo = complejo)

  cat("Complejos cripticos cargados:", nrow(complejos_csv), "complejos\n")
  cat("  Especies afectadas:", nrow(cripticos), "\n\n")
} else {
  # Si no existe el archivo, continuamos sin complejos (todas las especies
  # mantienen su nombre original). Esto permite ejecutar el pipeline en
  # entornos donde no se dispone del CSV de metadatos.
  cat("AVISO: No se encontro archivo de complejos taxonomicos\n")
  cat("  Ruta esperada:", CONFIG$paths$complejos_taxonomicos, "\n")
  cat("  Se procedera sin agrupar complejos cripticos.\n\n")
  cripticos <- tibble(sp_original = character(), sp_complejo = character())
}

# Aplicar complejos: crear columna especie_modelo
# Si una especie pertenece a un complejo criptico, su nombre se reemplaza
# por el nombre del complejo (e.g., "Myotis myotis" -> "Myotis_grande").
# Las especies no incluidas en ningun complejo mantienen su nombre original.
presencias <- presencias %>%
  mutate(
    especie_modelo = if_else(
      especie_definitiva %in% cripticos$sp_original,
      cripticos$sp_complejo[match(especie_definitiva, cripticos$sp_original)],
      especie_definitiva
    )
  )

# Validar que match() no introdujo NAs silenciosos
n_na_modelo <- sum(is.na(presencias$especie_modelo))
if (n_na_modelo > 0) {
  warning(sprintf("ATENCION: %d registros con especie_modelo=NA tras aplicar cripticos. Revisar coincidencia de nombres.", n_na_modelo))
  # Mostrar nombres que no coincidieron
  problematicos <- presencias %>% filter(is.na(especie_modelo)) %>%
    pull(especie_definitiva) %>% unique()
  cat(sprintf("  Especies problematicas: %s\n", paste(head(problematicos, 10), collapse = ", ")))
}

n_complejos_aplicados <- sum(presencias$especie_definitiva != presencias$especie_modelo,
                              na.rm = TRUE)
cat("Registros reasignados a complejos cripticos:", n_complejos_aplicados, "\n")
cat("Especies/complejos unicos tras reasignacion:",
    n_distinct(presencias$especie_modelo, na.rm = TRUE), "\n\n")


# ==============================================================================
# 7. TABLA DE PA POR METODO (FORMATO LARGO)
# ==============================================================================
# Construimos la tabla central de Presencia/Ausencia por metodo.
# Formato: cuadricula x especie x metodo -> presencia (1).
#
# POR QUE PA por metodo y no PA global:
#   El esfuerzo de muestreo varia espacialmente Y por metodo. Una cuadricula
#   muestreada solo con acustica no tiene informacion sobre especies que solo
#   se detectan en cuevas. Si trataramos la ausencia acustica como ausencia
#   real para una especie cavernicola, introduciríamos falsos negativos masivos.
#
#   Al crear PA por metodo, las ausencias (0) solo se asignan en cuadriculas
#   donde SI se muestreo con ese metodo especifico (paso que se realiza en 01g).
#   Esto es el fundamento del marco de modelado method-specific que usamos.
#
# Nota: filtramos NAs para evitar registros incompletos (e.g., sin especie
# identificada o sin cuadricula asignada).
# ------------------------------------------------------------------------------

pa_metodo <- presencias %>%
  filter(!is.na(especie_modelo),
         !is.na(cuadricula_utm_10x10),
         !is.na(metodo)) %>%
  select(cuadricula_utm_10x10, especie_modelo, metodo) %>%
  distinct() %>%
  mutate(presencia = 1L)

cat("Tabla PA por metodo:", nrow(pa_metodo), "registros\n")
cat("  Especies/complejos unicos:", n_distinct(pa_metodo$especie_modelo), "\n")
cat("  Cuadriculas unicas:", n_distinct(pa_metodo$cuadricula_utm_10x10), "\n")
cat("  Metodos:", paste(sort(unique(pa_metodo$metodo)), collapse = ", "), "\n\n")


# ==============================================================================
# 8. TABLA DE ESFUERZO DE MUESTREO POR METODO
# ==============================================================================
# El esfuerzo de muestreo (que cuadriculas se muestrearon con que metodo)
# es esencial para:
#   1. Asignar ausencias reales (0) solo donde se muestreo con ese metodo
#   2. Calcular indices de completitud del inventario
#   3. Ponderar la incertidumbre de los modelos (mas esfuerzo = mas confianza)
#
# muestras_metodo: formato largo (cuadricula x metodo -> n_registros)
# muestras_metodo_wide: formato ancho (cuadricula x m_acustica/m_captura/...)
#   con indicador binario (1 = muestreado) y n_metodos total
# ------------------------------------------------------------------------------

muestras_metodo <- presencias %>%
  filter(!is.na(cuadricula_utm_10x10), !is.na(metodo)) %>%
  group_by(cuadricula_utm_10x10, metodo) %>%
  summarise(n_registros = n(), .groups = "drop")

muestras_metodo_wide <- muestras_metodo %>%
  mutate(muestreado = 1L) %>%
  select(-n_registros) %>%
  pivot_wider(names_from = metodo, values_from = muestreado,
              names_prefix = "m_", values_fill = 0L) %>%
  mutate(n_metodos = rowSums(select(., starts_with("m_"))))

cat("Esfuerzo de muestreo:\n")
cat("  Cuadriculas con al menos 1 metodo:", nrow(muestras_metodo_wide), "\n")
cat("  Distribucion de n_metodos:\n")
print(table(muestras_metodo_wide$n_metodos))
cat("\n")


# ==============================================================================
# 9. RESUMEN DE MUESTREO Y CANDIDATOS A MODELIZAR
# ==============================================================================
# El resumen cruza especie x metodo para saber cuantos registros y cuadriculas
# tiene cada especie por metodo. Esto permite:
#   - Evaluar que especies son modelizables con cada metodo
#   - Identificar sesgos de muestreo (e.g., especie bien cubierta acusticamente
#     pero sin datos de captura)
#
# Candidatos: especies con suficientes presencias (>= min_presencias, definido
# en CONFIG) para construir un modelo estadistico robusto. El umbral minimo
# evita modelos sobreajustados con pocos puntos de presencia.
# ------------------------------------------------------------------------------

resumen_muestreo <- presencias %>%
  group_by(especie_modelo, metodo) %>%
  summarise(
    n_registros = n(),
    n_cuadriculas = n_distinct(cuadricula_utm_10x10),
    .groups = "drop"
  )

candidatos_por_metodo <- resumen_muestreo %>%
  filter(n_cuadriculas >= CONFIG$seleccion$min_presencias) %>%
  select(especie_modelo, metodo, n_cuadriculas)

cat("Candidatos a modelizar por metodo (min_presencias >=",
    CONFIG$seleccion$min_presencias, "):\n")
print(table(candidatos_por_metodo$metodo))
cat("\nEspecies candidatas unicas:",
    n_distinct(candidatos_por_metodo$especie_modelo), "\n\n")


# ==============================================================================
# 10. GUARDAR RESULTADOS
# ==============================================================================
# Se guardan todos los outputs como RDS (formato nativo de R, eficiente y
# preserva tipos de datos). Cada archivo se usa en pasos posteriores:
#   - presencias_std     -> referencia para QA y trazabilidad
#   - pa_metodo          -> paso 01g (creacion de PAxENV por metodo)
#   - muestras_metodo*   -> paso 01g (asignacion de ausencias)
#   - tabla_cripticos    -> pasos 02+ (interpretacion de resultados)
#   - resumen_muestreo   -> QA y diagnosticos
#   - candidatos_metodo  -> paso 02+ (filtrado de especies a modelizar)
# ------------------------------------------------------------------------------

saveRDS(presencias, CONFIG$paths$presencias_std)
saveRDS(pa_metodo, CONFIG$paths$pa_metodo)
saveRDS(muestras_metodo, CONFIG$paths$muestras_metodo)
saveRDS(muestras_metodo_wide, CONFIG$paths$muestras_metodo_wide)
saveRDS(cripticos, CONFIG$paths$tabla_cripticos)
saveRDS(resumen_muestreo, CONFIG$paths$resumen_muestreo)
saveRDS(candidatos_por_metodo, CONFIG$paths$candidatos_por_metodo)

cat("[OK] Archivos generados:\n")
cat("  -", CONFIG$paths$presencias_std, "\n")
cat("  -", CONFIG$paths$pa_metodo, "\n")
cat("  -", CONFIG$paths$muestras_metodo, "\n")
cat("  -", CONFIG$paths$muestras_metodo_wide, "\n")
cat("  -", CONFIG$paths$tabla_cripticos, "\n")
cat("  -", CONFIG$paths$resumen_muestreo, "\n")
cat("  -", CONFIG$paths$candidatos_por_metodo, "\n\n")

cat("=== 01a COMPLETADO ===\n\n")
