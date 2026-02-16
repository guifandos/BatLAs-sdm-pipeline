# ==============================================================================
# utils_geologia.R - Agrupacion de Karst, Litologia y features geologicos
# ==============================================================================
#
# Funciones para procesar las capas geologicas del Atlas de Murcielagos Ibericos.
#
# La geologia es critica para murcielagos porque:
#   - El karst (carbonatos solubles) genera cuevas y cavidades, que son los
#     refugios principales para la mayoria de las especies cavernicolas.
#   - La litologia condiciona la disponibilidad de fisuras en roca (refugios
#     para fisuricolas/rupicolas) y afecta indirectamente al paisaje.
#   - La diversidad litologica indica heterogeneidad geologica, que suele
#     correlacionarse con mayor variedad de microhabitats y refugios.
#
# Variables producidas:
#   Karst_principal    - Prop. carbonato continuo + evaporitas (cuevas optimas)
#   Karst_secundario   - Prop. carbonato discontinuo + mixto (cuevas suboptimas)
#   Karst_total        - Suma de ambos (proxy global de cavidades)
#   Lito_karsticas     - Prop. rocas karsticas (calizas, dolomias, margas, yesos)
#   Lito_siliciclasticas - Prop. areniscas, conglomerados, arcillas, lutitas
#   Lito_igneas        - Prop. granitoides y vulcanitas
#   Lito_metamorficas  - Prop. gneises, micaesquistos, serpentinitas
#   Lito_otras         - Prop. depositos cuaternarios, aluviales, etc.
#   Lito_dominante     - Clase litologica dominante (categorica)
#   Lito_dominancia    - % de la clase dominante (0-100; homogeneidad geologica)
#   Lito_diversidad    - Entropia de Shannon de las 5 proporciones litologicas
#                        (0 = monolitologico, ln(5)=1.61 = maxima diversidad)
#   Lito_n_tipos       - Numero de grupos litologicos presentes (1-5)
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

suppressPackageStartupMessages(library(tidyverse))

# ==============================================================================
# AGRUPACION DE KARST
# ==============================================================================
#
# Los codigos Karst_HISTO_ corresponden a la clasificacion del mapa de
# karstificabilidad de la Peninsula Iberica:
#   1, 3 = Carbonato continuo y evaporitas - generan las cavidades mas grandes
#          y desarrolladas (cuevas de gran recorrido, simas profundas). Son los
#          refugios optimos para especies cavernicolas como Rhinolophus,
#          Miniopterus y Myotis de gran tamano.
#   2, 4, 5 = Carbonato discontinuo, conglomerados karsticos y mixtos - generan
#             cavidades menores o menos predecibles, pero aun utiles como
#             refugios secundarios.
# ==============================================================================

agrupar_karst <- function(datos) {
  columnas_karst <- names(datos)[str_detect(names(datos), "^Karst_HISTO_[0-9]")]
  if (length(columnas_karst) == 0) {
    warning("No se encontraron columnas Karst (Karst_HISTO_)")
    return(datos)
  }
  cat("Columnas Karst encontradas:", length(columnas_karst), "\n")
  datos %>%
    mutate(
      # Carbonato continuo + evaporitas: refugios optimos para cavernicolas
      Karst_principal = rowSums(select(., matches("Karst_HISTO_(1|3)")), na.rm = TRUE),
      # Carbonato discontinuo + mixto: refugios suboptimos
      Karst_secundario = rowSums(select(., matches("Karst_HISTO_(2|4|5)")), na.rm = TRUE),
      # Total: proxy global de disponibilidad de cavidades
      Karst_total = Karst_principal + Karst_secundario
    )
}

# ==============================================================================
# AGRUPACION DE LITOLOGIA
# ==============================================================================
#
# Los codigos lito_HISTO_ corresponden a los codigos del mapa litologico
# 1:200.000 del IGME. Se agrupan en 5 categorias ecologicamente relevantes:
#
# 1. Karsticas (codigos 2,4,6,10,12,33-37): Calizas, dolomias, margas, yesos.
#    Estas rocas se disuelven formando cavidades, sumideros y surgencias.
#    Son el sustrato fundamental para los refugios de murcielagos cavernicolas.
#
# 2. Siliciclasticas (codigos 1,5,14,16,17,20,21,24-27,30,31,39): Areniscas,
#    conglomerados, arcillas, lutitas, pizarras, cuarcitas. Rocas sedimentarias
#    detriticas y metamorficas de bajo grado. Forman paisajes con fisuras y
#    grietas utiles para especies fisuricolas, pero sin cavidades grandes.
#
# 3. Igneas (codigos 43,44,46,50,52-58): Granitoides y vulcanitas. Los
#    paisajes graniticos forman berrocales con bloques y fisuras. Las
#    vulcanitas pueden tener tubos de lava (refugios en Canarias).
#
# 4. Metamorficas (codigos 60,67,79-81,83-86): Gneises, micaesquistos,
#    serpentinitas. Generalmente pocas cavidades, pero la foliacion crea
#    fisuras en cantiles y barrancos.
#
# 5. Otras (codigos 92,94,95,97,98,112,...): Depositos cuaternarios,
#    aluviales, coluviales, dunas, etc. Poco relevantes como refugios
#    directos, pero indican zonas llanas o deposicionales.
# ==============================================================================

agrupar_litologia <- function(datos) {
  columnas_lito <- names(datos)[str_detect(names(datos), "^lito_HISTO_[0-9]")]
  if (length(columnas_lito) == 0) {
    warning("No se encontraron columnas litologia (lito_HISTO_)")
    return(datos)
  }
  cat("Columnas litologia encontradas:", length(columnas_lito), "\n")
  datos %>%
    mutate(
      # Calizas, dolomias, margas, yesos: substrato de cavidades karsticas
      Lito_karsticas = rowSums(select(., matches("lito_HISTO_(2|4|6|10|12|33|34|35|36|37)")), na.rm = TRUE),
      # Areniscas, conglomerados, arcillas, lutitas, pizarras, cuarcitas
      Lito_siliciclasticas = rowSums(select(., matches("lito_HISTO_(1|5|14|16|17|20|21|24|25|26|27|30|31|39)")), na.rm = TRUE),
      # Granitoides, vulcanitas
      Lito_igneas = rowSums(select(., matches("lito_HISTO_(43|44|46|50|52|53|54|55|56|57|58)")), na.rm = TRUE),
      # Gneises, micaesquistos, serpentinitas
      Lito_metamorficas = rowSums(select(., matches("lito_HISTO_(60|67|79|80|81|83|84|85|86)")), na.rm = TRUE),
      # Cuaternario, aluvial, coluvial, dunas, etc.
      Lito_otras = rowSums(select(., matches("lito_HISTO_(92|94|95|97|98|112|121|124|126|130|131|133|151|154|172|189|206|207|208|211|212|213|218|219|227|231|250)")), na.rm = TRUE)
    )
}

# ==============================================================================
# APLICAR AGRUPACIONES (wrapper de conveniencia)
# ==============================================================================

aplicar_agrupaciones_geologicas <- function(datos) {
  cat("=== AGRUPANDO VARIABLES GEOLOGICAS ===\n\n")
  datos <- agrupar_karst(datos)
  datos <- agrupar_litologia(datos)
  cat("[OK] Agrupaciones geologicas completadas\n\n")
  return(datos)
}

# ==============================================================================
# RESUMEN GEOLOGICO
# ==============================================================================

mostrar_resumen_geologico <- function(datos) {
  cat("=== RESUMEN DE VARIABLES GEOLOGICAS ===\n\n")
  if (any(str_detect(names(datos), "^Karst_"))) {
    cat("KARST:\n")
    datos %>%
      select(matches("^Karst_(principal|secundario|total)")) %>%
      summarise(across(everything(),
                       list(media = ~mean(., na.rm = TRUE),
                            max = ~max(., na.rm = TRUE),
                            n_presencia = ~sum(. > 0, na.rm = TRUE)),
                       .names = "{.col}_{.fn}")) %>%
      pivot_longer(everything(),
                   names_to = c("variable", "estadistico"),
                   names_pattern = "(.+)_(.+)") %>%
      pivot_wider(names_from = estadistico, values_from = value) %>%
      print()
    cat("\n")
  }
  if (any(str_detect(names(datos), "^Lito_"))) {
    cat("LITOLOGIA:\n")
    datos %>%
      select(matches("^Lito_(karsticas|siliciclasticas|igneas|metamorficas|otras)$")) %>%
      summarise(across(everything(),
                       list(media = ~mean(., na.rm = TRUE),
                            max = ~max(., na.rm = TRUE),
                            n_presencia = ~sum(. > 0, na.rm = TRUE)),
                       .names = "{.col}_{.fn}")) %>%
      pivot_longer(everything(),
                   names_to = c("variable", "estadistico"),
                   names_pattern = "(.+)_(.+)") %>%
      pivot_wider(names_from = estadistico, values_from = value) %>%
      print()
    cat("\n")
  }
}

# ==============================================================================
# BUILD GEO FEATURES (funcion principal de la pipeline)
# ==============================================================================
#
# Construye todas las variables geologicas derivadas a partir de los datos
# brutos de Karst y Litologia. Esta funcion es llamada desde 01e_geologia.R.
#
# Flujo:
#   1. Agrupar columnas Karst_HISTO_ -> Karst_principal, secundario, total
#   2. Agrupar columnas lito_HISTO_ -> 5 grupos litologicos
#   3. Join por cuadricula
#   4. Calcular litologia dominante y % de dominancia
#   5. Calcular entropia de Shannon (diversidad litologica)
#   6. Contar numero de tipos litologicos presentes
#
# La diversidad litologica (Shannon) y el numero de tipos son importantes
# porque las cuadriculas con mayor heterogeneidad geologica tienden a
# ofrecer mas variedad de microhabitats (cuevas en caliza, fisuras en
# granito, cantiles en metamorficas, etc.), lo que beneficia a comunidades
# mas ricas de murcielagos.
# ==============================================================================

#' Build geological features from raw Karst and Lito dataframes
#'
#' @param karst_raw Data frame with Karst_HISTO_ columns and an ID column
#' @param lito_raw Data frame with lito_HISTO_ columns and an ID column
#' @param key Name of the ID column to join on
#' @return Data frame with grouped geological features including diversity metrics
build_geo_features <- function(karst_raw, lito_raw, key = "CUADRICULA") {

  # --- Paso 1: Agrupar columnas Karst en 3 variables resumen ---
  karst_grouped <- agrupar_karst(karst_raw) %>%
    select(all_of(key), Karst_principal, Karst_secundario, Karst_total)

  # --- Paso 2: Agrupar columnas Litologia en 5 grupos ---
  lito_grouped <- agrupar_litologia(lito_raw) %>%
    select(all_of(key), Lito_karsticas, Lito_siliciclasticas, Lito_igneas,
           Lito_metamorficas, Lito_otras)

  # --- Paso 3: Join por cuadricula ---
  # Validar que ambas tablas usan la misma columna ID
  if (!key %in% names(karst_grouped)) {
    stop(sprintf("build_geo_features: columna '%s' no encontrada en karst. Columnas: %s",
                 key, paste(names(karst_grouped), collapse = ", ")))
  }
  if (!key %in% names(lito_grouped)) {
    stop(sprintf("build_geo_features: columna '%s' no encontrada en lito. Columnas: %s",
                 key, paste(names(lito_grouped), collapse = ", ")))
  }
  n_karst_pre <- nrow(karst_grouped)
  geo <- karst_grouped %>%
    left_join(lito_grouped, by = key)
  stopifnot(
    "Join karst+lito perdio o duplico filas" = nrow(geo) == n_karst_pre
  )

  # --- Paso 4: Litologia dominante y dominancia ---
  # Lito_dominante: clase litologica con mayor proporcion en la cuadricula.
  #   Util como variable categorica para estratificar analisis.
  # Lito_dominancia: % que representa la clase dominante sobre el total.
  #   Valores altos (>80%) indican substrato homogeneo; valores bajos (<40%)
  #   indican mezcla litologica.
  geo <- geo %>%
    mutate(
      Lito_dominante = case_when(
        Lito_karsticas >= pmax(Lito_siliciclasticas, Lito_igneas, Lito_metamorficas, Lito_otras, na.rm = TRUE) ~ "Karsticas",
        Lito_siliciclasticas >= pmax(Lito_karsticas, Lito_igneas, Lito_metamorficas, Lito_otras, na.rm = TRUE) ~ "Siliciclasticas",
        Lito_igneas >= pmax(Lito_karsticas, Lito_siliciclasticas, Lito_metamorficas, Lito_otras, na.rm = TRUE) ~ "Igneas",
        Lito_metamorficas >= pmax(Lito_karsticas, Lito_siliciclasticas, Lito_igneas, Lito_otras, na.rm = TRUE) ~ "Metamorficas",
        TRUE ~ "Mixta"
      ),
      Lito_dominancia = pmax(Lito_karsticas, Lito_siliciclasticas, Lito_igneas,
                             Lito_metamorficas, Lito_otras, na.rm = TRUE) /
        (Lito_karsticas + Lito_siliciclasticas + Lito_igneas +
           Lito_metamorficas + Lito_otras + 1e-10) * 100
    )

  # --- Paso 5: Diversidad litologica (Shannon entropy) ---
  # H = -sum(p_i * ln(p_i)) para cada grupo litologico con p_i > 0
  #
  # Rango teorico: 0 (una sola litologia) a ln(5) ~ 1.61 (5 grupos iguales).
  # En la practica, valores altos de Shannon indican cuadriculas con mezcla
  # de substratos, lo que suele implicar mayor variedad geomorfologica
  # (valles, sierras, contactos litologicos) y por tanto mas tipos de
  # refugios para murcielagos.
  #
  # --- Paso 6: Numero de tipos litologicos presentes ---
  # Lito_n_tipos: conteo simple de cuantos de los 5 grupos tienen proporcion > 0.
  # Complementa la entropia con una medida mas intuitiva de heterogeneidad.
  # Rango: 1-5.

  # Nombres de las 5 columnas litologicas
  lito_cols <- c("Lito_karsticas", "Lito_siliciclasticas", "Lito_igneas",
                 "Lito_metamorficas", "Lito_otras")

  # Calcular proporciones, Shannon y n_tipos fila a fila
  # Usamos rowwise() para garantizar calculo correcto por cuadricula
  geo <- geo %>%
    rowwise() %>%
    mutate(
      # Suma total de las 5 proporciones litologicas en esta cuadricula
      .lito_total = sum(c_across(all_of(lito_cols)), na.rm = TRUE),

      # Proporciones relativas (p_i) de cada grupo
      .p_karst = ifelse(.lito_total > 0, Lito_karsticas / .lito_total, 0),
      .p_silic = ifelse(.lito_total > 0, Lito_siliciclasticas / .lito_total, 0),
      .p_ignea = ifelse(.lito_total > 0, Lito_igneas / .lito_total, 0),
      .p_metam = ifelse(.lito_total > 0, Lito_metamorficas / .lito_total, 0),
      .p_otras = ifelse(.lito_total > 0, Lito_otras / .lito_total, 0),

      # Shannon entropy: H = -sum(p_i * ln(p_i)) para p_i > 0
      Lito_diversidad = -sum(
        ifelse(.p_karst > 0, .p_karst * log(.p_karst), 0),
        ifelse(.p_silic > 0, .p_silic * log(.p_silic), 0),
        ifelse(.p_ignea > 0, .p_ignea * log(.p_ignea), 0),
        ifelse(.p_metam > 0, .p_metam * log(.p_metam), 0),
        ifelse(.p_otras > 0, .p_otras * log(.p_otras), 0),
        na.rm = TRUE
      ),

      # Numero de tipos litologicos presentes (proporcion > 0)
      Lito_n_tipos = sum(
        c(.p_karst > 0, .p_silic > 0, .p_ignea > 0,
          .p_metam > 0, .p_otras > 0),
        na.rm = TRUE
      )
    ) %>%
    ungroup() %>%
    # Eliminar columnas auxiliares de proporciones
    select(-starts_with(".p_"), -.lito_total)

  cat(sprintf("[OK] Geo features construidos: %d filas, %d columnas\n", nrow(geo), ncol(geo)))
  cat(sprintf("     Variables: %s\n", paste(setdiff(names(geo), key), collapse = ", ")))
  return(geo)
}

message("[OK] Funciones geologia cargadas")
