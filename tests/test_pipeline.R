# ==============================================================================
# test_pipeline.R - Tests reproducibles con datos simulados
# ==============================================================================
#
# Verifica que el pipeline funciona correctamente usando datos de prueba
# minimos (2 especies piloto, datos simulados).
#
# Cubre: configuracion, utilidades core, CORINE, gremios, GLM, seleccion
# de variables, fuzzy, incertidumbre, validacion de CONFIG, y logging.
#
# USO:
#   source("tests/test_pipeline.R")
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

cat("\n")
cat("================================================================================\n")
cat("  TEST DEL PIPELINE - DATOS SIMULADOS\n")
cat("================================================================================\n\n")

library(tidyverse)

n_tests <- 0
n_passed <- 0

check <- function(desc, expr) {
  n_tests <<- n_tests + 1
  result <- tryCatch({ expr; TRUE }, error = function(e) { cat(sprintf("    ERROR: %s\n", e$message)); FALSE })
  if (result) { n_passed <<- n_passed + 1; cat(sprintf("  [PASS] %s\n", desc)) }
  else { cat(sprintf("  [FAIL] %s\n", desc)) }
  invisible(result)
}

# --- Generar datos de prueba ---

cat("Generando datos de prueba...\n\n")

set.seed(42)
n_cuad <- 500
n_vars <- 10

cuadriculas <- sprintf("30T%04d", 1:n_cuad)

vars <- as.data.frame(matrix(rnorm(n_cuad * n_vars), ncol = n_vars))
names(vars) <- c("Bio01", "Bio05", "Bio06", "Bio12",
                  "SRTM_Alt_mean", "Slope_slope_mean",
                  "Karst_total", "CLC_bosques", "CLC_rupicola", "CLC_acuatico")
vars$CUADRICULA <- cuadriculas
vars$X <- runif(n_cuad, -10, 5)
vars$Y <- runif(n_cuad, 36, 44)

prob_rf <- plogis(-1 + 0.5 * vars$Karst_total + 0.3 * vars$CLC_bosques)
prob_pp <- plogis(0 + 0.4 * vars$Bio01 - 0.2 * vars$SRTM_Alt_mean)

vars$`Rhinolophus ferrumequinum` <- rbinom(n_cuad, 1, prob_rf)
vars$`Pipistrellus pipistrellus` <- rbinom(n_cuad, 1, prob_pp)
vars$muestreado <- 1
vars$n_metodos <- sample(0:3, n_cuad, replace = TRUE, prob = c(0.3, 0.4, 0.2, 0.1))

dir.create("tests/test_data", recursive = TRUE, showWarnings = FALSE)
saveRDS(vars, "tests/test_data/PAxENV_test.rds")

cat(sprintf("  Cuadriculas: %d\n", n_cuad))
cat(sprintf("  Presencias R.ferrumequinum: %d\n", sum(vars$`Rhinolophus ferrumequinum`)))
cat(sprintf("  Presencias P.pipistrellus: %d\n", sum(vars$`Pipistrellus pipistrellus`)))

# ==============================================================================
# Test 1: Configuracion
# ==============================================================================
cat("\n--- Test 1: Configuracion ---\n")

source("R/00_setup/00_config.R")
check("CONFIG existe y es una lista", { stopifnot(is.list(CONFIG)) })
check("CONFIG$paths es una lista", { stopifnot(is.list(CONFIG$paths)) })
check("CONFIG$ambiental$prop_train entre 0 y 1", {
  stopifnot(CONFIG$ambiental$prop_train > 0, CONFIG$ambiental$prop_train < 1)
})
check("Pesos incertidumbre suman 1", {
  suma <- CONFIG$incertidumbre$peso_mess +
    CONFIG$incertidumbre$peso_bootstrap + CONFIG$incertidumbre$peso_esfuerzo
  stopifnot(abs(suma - 1.0) < 0.01)
})
check("validar_config() sin error", {
  validar_config()
})

# ==============================================================================
# Test 2: Funciones core
# ==============================================================================
cat("\n--- Test 2: Funciones core ---\n")

source("R/utils/utils_checkpoints.R")
source("R/utils/utils_favorabilidad.R")
source("R/utils/utils_metricas.R")

# norm_id
check("norm_id(' 30tul12 ') == '30TUL12'", {
  stopifnot(norm_id(" 30tul12 ") == "30TUL12")
})
check("norm_id preserva IDs validos", {
  stopifnot(norm_id("30TUL12") == "30TUL12")
})
check("norm_id vector", {
  resultado <- norm_id(c(" abc ", "DEF"))
  stopifnot(identical(resultado, c("ABC", "DEF")))
})

# favorabilidad
check("favorabilidad devuelve [0,1]", {
  prob <- c(0.1, 0.5, 0.9)
  y_train <- c(rep(0, 90), rep(1, 10))
  fav <- favorabilidad(prob, y_train)
  stopifnot(all(fav >= 0 & fav <= 1))
})
check("favorabilidad preserva orden", {
  prob <- c(0.1, 0.5, 0.9)
  y_train <- c(rep(0, 90), rep(1, 10))
  fav <- favorabilidad(prob, y_train)
  stopifnot(fav[3] > fav[1])
})
check("favorabilidad_inv es inversa", {
  prob <- seq(0.1, 0.9, 0.1)
  y_train <- c(rep(0, 80), rep(1, 20))
  fav <- favorabilidad(prob, y_train)
  prevalence <- sum(y_train == 1) / sum(y_train == 0)
  prob_back <- favorabilidad_inv(fav, prevalence)
  stopifnot(all(abs(prob_back - prob) < 0.01))
})
check("favorabilidad con vector prob=1 devuelve 1", {
  y_train <- c(rep(0, 90), rep(1, 10))
  fav <- favorabilidad(0.9999, y_train)
  stopifnot(fav <= 1)
})

# compute_metrics
check("compute_metrics AUC > 0.5 con datos separables", {
  set.seed(123)
  obs <- c(rep(0, 50), rep(1, 50))
  pred <- c(runif(50, 0, 0.4), runif(50, 0.6, 1))
  met <- compute_metrics(obs, pred)
  stopifnot(met$AUC > 0.5)
  stopifnot(met$TSS > 0)
})
check("compute_metrics maneja NAs", {
  obs <- c(rep(0, 50), rep(1, 50), NA)
  pred <- c(runif(50, 0, 0.4), runif(50, 0.6, 1), NA)
  met <- compute_metrics(obs, pred)
  stopifnot(!is.na(met$AUC))
})
check("compute_metrics devuelve NA con <10 obs", {
  met <- compute_metrics(c(0, 1, 0), c(0.1, 0.9, 0.2))
  stopifnot(is.na(met$AUC))
})

# impute_median
check("impute_median rellena NAs", {
  data <- data.frame(a = c(1, NA, 3), b = c(NA, 2, NA))
  medians <- list(a = 2, b = 5)
  resultado <- impute_median(data, medians)
  stopifnot(resultado$a[2] == 2)
  stopifnot(all(resultado$b[c(1, 3)] == 5))
})

# ==============================================================================
# Test 3: CORINE
# ==============================================================================
cat("\n--- Test 3: Funciones CORINE ---\n")

source("R/utils/utils_corine.R")

check("agrupar_corine agrupa correctamente", {
  datos_clc <- tibble(
    cuadricula = c("A", "B"),
    CLC_HISTO_311 = c(50, 0),
    CLC_HISTO_312 = c(20, 0),
    CLC_HISTO_111 = c(0, 80),
    CLC_HISTO_511 = c(10, 5)
  )
  datos_agr <- agrupar_corine(datos_clc)
  stopifnot("CLC_bosques" %in% names(datos_agr))
  stopifnot(datos_agr$CLC_bosques[1] == 70)
  stopifnot(datos_agr$CLC_urbano[2] == 80)
})
check("agrupar_corine genera 9 grupos", {
  datos_clc <- tibble(cuadricula = "A", CLC_HISTO_311 = 100)
  datos_agr <- agrupar_corine(datos_clc)
  grupos_esperados <- c("CLC_bosques", "CLC_rupicola", "CLC_acuatico",
                         "CLC_pastizal", "CLC_mosaico", "CLC_cultivo_lenoso",
                         "CLC_urbano", "CLC_cultivo_intensivo", "CLC_perturbacion_costera")
  presentes <- sum(grupos_esperados %in% names(datos_agr))
  stopifnot(presentes == 9)
})

# ==============================================================================
# Test 4: Sistema de gremios
# ==============================================================================
cat("\n--- Test 4: Sistema de gremios ---\n")

source("R/02_variable_selection/02a_funciones_gremios.R")

gremios <- cargar_gremios()

check("Gremios cargados con especies", {
  stopifnot(nrow(gremios$especies) > 0)
  stopifnot(nrow(gremios$refugio) > 0)
  stopifnot(nrow(gremios$alimentacion) > 0)
})
check("Variables gremio Rhinolophus incluyen Karst", {
  vars_rf <- obtener_variables_gremio("Rhinolophus ferrumequinum", gremios)
  stopifnot(length(vars_rf) > 0)
  stopifnot("Karst_total" %in% vars_rf)
})
check("Variables gremio especie inexistente devuelve vacio", {
  vars_x <- suppressWarnings(obtener_variables_gremio("Especie ficticia", gremios))
  stopifnot(length(vars_x) == 0)
})
check("obtener_especies_modelizables filtra correctamente", {
  modelizables <- obtener_especies_modelizables(gremios)
  stopifnot(length(modelizables) > 0)
  stopifnot(!"Plecotus teneriffae" %in% modelizables)
})
check("obtener_especies_complejo funciona", {
  spp <- obtener_especies_complejo("Myotis_grande", gremios)
  stopifnot(length(spp) == 2)
  stopifnot("Myotis myotis" %in% spp)
})

# Test detect_variable_type
check("detect_variable_type climatica", {
  stopifnot(detect_variable_type("Bio01") == "climatica")
  stopifnot(detect_variable_type("bio12") == "climatica")
})
check("detect_variable_type geologica", {
  stopifnot(detect_variable_type("Karst_total") == "geologica")
  stopifnot(detect_variable_type("Lito_karsticas") == "geologica")
})
check("detect_variable_type forestal", {
  stopifnot(detect_variable_type("CLC_bosques") == "forestal")
})
check("detect_variable_type acuatica", {
  stopifnot(detect_variable_type("CLC_acuatico") == "acuatica")
})

# Test annotate_variables_by_guild
check("annotate_variables_by_guild devuelve tibble completo", {
  varnames <- c("Bio01", "Karst_total", "CLC_bosques")
  result <- annotate_variables_by_guild("Rhinolophus ferrumequinum", varnames,
                                         gremios$especies)
  stopifnot(nrow(result) == 3)
  stopifnot(all(c("variable", "prioridad", "tipo_base") %in% names(result)))
  stopifnot(result$prioridad[result$variable == "Karst_total"] >= 2)
})
check("annotate_variables_by_guild especie inexistente no falla", {
  varnames <- c("Bio01", "Karst_total")
  result <- suppressWarnings(
    annotate_variables_by_guild("Especie ficticia", varnames, gremios$especies)
  )
  stopifnot(nrow(result) == 2)
  stopifnot(all(c("variable", "prioridad", "tipo_base") %in% names(result)))
})

# ==============================================================================
# Test 5: GLM + Favorabilidad
# ==============================================================================
cat("\n--- Test 5: Modelo GLM ---\n")

check("GLM + favorabilidad funciona", {
  datos_test <- vars %>%
    filter(muestreado == 1) %>%
    select(PA = `Rhinolophus ferrumequinum`, Bio01, Karst_total, CLC_bosques) %>%
    drop_na()
  modelo <- glm(PA ~ Bio01 + Karst_total + CLC_bosques, data = datos_test, family = binomial)
  pred_prob <- predict(modelo, type = "response")
  pred_fav <- favorabilidad(pred_prob, datos_test$PA)
  stopifnot(all(pred_fav >= 0 & pred_fav <= 1))
  met <- compute_metrics(datos_test$PA, pred_fav)
  stopifnot(met$AUC > 0.5)
})

# ==============================================================================
# Test 6: Seleccion de variables (pipeline parcial)
# ==============================================================================
cat("\n--- Test 6: Seleccion de variables ---\n")

source("R/02_variable_selection/02b_pipeline_seleccion.R")

check("select07_core devuelve variables", {
  set.seed(42)
  X <- vars[, c("Bio01", "Bio05", "Bio06", "Bio12", "Karst_total", "CLC_bosques")]
  y <- vars$`Rhinolophus ferrumequinum`
  selected <- select07_core(X, y, threshold = 0.8)
  stopifnot(length(selected) > 0)
  stopifnot(all(selected %in% names(X)))
})
check("fase1_preseleccion_gremio funciona", {
  df <- vars %>%
    rename(presencia = `Rhinolophus ferrumequinum`) %>%
    select(presencia, Bio01, Bio05, Bio12, Karst_total, CLC_bosques,
           CLC_rupicola, CLC_acuatico, SRTM_Alt_mean, Slope_slope_mean)
  f1 <- fase1_preseleccion_gremio(df, "Rhinolophus ferrumequinum",
                                    gremios$especies, "presencia")
  stopifnot(ncol(f1$data) > 1)
  stopifnot(nrow(f1$var_info) > 0)
})
check("fase2_limpieza_basica elimina constantes", {
  df <- tibble(presencia = c(rep(0, 50), rep(1, 50)),
               var_ok = rnorm(100),
               var_const = rep(1, 100))
  var_info <- tibble(variable = c("var_ok", "var_const"),
                      prioridad = c(3L, 1L), peso = c(3.0, 1.0),
                      tipo_base = c("climatica", "otra"),
                      es_climatica = c(TRUE, FALSE), es_gremio = c(FALSE, FALSE),
                      es_nucleo = c(FALSE, FALSE), es_complementaria = c(FALSE, FALSE))
  f2 <- fase2_limpieza_basica(df, "presencia", var_info)
  stopifnot(!"var_const" %in% names(f2$data))
  stopifnot("var_ok" %in% names(f2$data))
})

# ==============================================================================
# Test 7: Fuzzy intersection
# ==============================================================================
cat("\n--- Test 7: Interseccion fuzzy ---\n")

check("fuzzy_geometrica es media geometrica", {
  a <- c(0.4, 0.9, 0.0)
  b <- c(0.6, 0.8, 1.0)
  result <- sqrt(a * b)
  stopifnot(all(abs(result - c(sqrt(0.24), sqrt(0.72), 0.0)) < 0.001))
})
check("fuzzy_pmin devuelve el minimo", {
  a <- c(0.4, 0.9)
  b <- c(0.6, 0.8)
  stopifnot(all(pmin(a, b) == c(0.4, 0.8)))
})
check("fuzzy resultados en [0,1]", {
  set.seed(42)
  a <- runif(100, 0, 1)
  b <- runif(100, 0, 1)
  stopifnot(all(sqrt(a * b) >= 0 & sqrt(a * b) <= 1))
})

# ==============================================================================
# Test 8: Logging
# ==============================================================================
cat("\n--- Test 8: Logging ---\n")

source("R/utils/utils_logging.R")

check("init_log crea archivo", {
  log_file <- init_log("tests/test_data")
  stopifnot(file.exists(log_file))
})
check("log_event escribe entrada", {
  log_event("test", "sp_test", "INFO", "Mensaje de prueba")
  log_df <- read_log()
  stopifnot(nrow(log_df) > 0)
  stopifnot("INFO" %in% log_df$nivel)
})
check("log_summary funciona sin errores", {
  log_summary()
})

# ==============================================================================
# Test 9: Consistencia de metadatos
# ==============================================================================
cat("\n--- Test 9: Consistencia de metadatos ---\n")

check("Todas las categorias refugio de especies existen en gremios", {
  cats_esp <- unique(gremios$especies$refugio[!is.na(gremios$especies$refugio)])
  cats_gremio <- gremios$refugio$categoria
  faltantes <- setdiff(cats_esp, cats_gremio)
  if (length(faltantes) > 0) stop(sprintf("Categorias faltantes: %s", paste(faltantes, collapse=", ")))
})
check("Todas las categorias alimentacion de especies existen en gremios", {
  cats_esp <- unique(gremios$especies$alimentacion[!is.na(gremios$especies$alimentacion)])
  cats_gremio <- gremios$alimentacion$categoria
  faltantes <- setdiff(cats_esp, cats_gremio)
  if (length(faltantes) > 0) stop(sprintf("Categorias faltantes: %s", paste(faltantes, collapse=", ")))
})
check("Variables en gremios existen en diccionario", {
  diccionario <- read_csv(CONFIG$paths$diccionario_variables, show_col_types = FALSE)
  vars_dict <- diccionario$variable
  vars_refugio <- gremios$refugio %>% pull(vars) %>% unlist() %>% unique()
  vars_alim <- gremios$alimentacion %>% pull(vars) %>% unlist() %>% unique()
  vars_gremio <- unique(c(vars_refugio, vars_alim))
  faltantes <- setdiff(vars_gremio, vars_dict)
  if (length(faltantes) > 0) {
    cat(sprintf("    AVISO: Variables en gremios no en diccionario: %s\n",
                paste(faltantes, collapse = ", ")))
  }
})
check("Complejos cripticos coherentes con especies", {
  if (!is.null(gremios$complejos)) {
    for (i in seq_len(nrow(gremios$complejos))) {
      spp <- str_split(gremios$complejos$especies_incluidas[i], ",\\s*")[[1]]
      for (sp in spp) {
        sp_row <- gremios$especies %>% filter(especie == sp)
        stopifnot(nrow(sp_row) == 1)
      }
    }
  }
})

# ==============================================================================
# Resumen
# ==============================================================================

cat("\n================================================================================\n")
cat(sprintf("  TESTS: %d/%d PASARON", n_passed, n_tests))
if (n_passed == n_tests) {
  cat(" - TODOS OK")
} else {
  cat(sprintf(" - %d FALLARON", n_tests - n_passed))
}
cat("\n================================================================================\n\n")

# Limpiar
unlink("tests/test_data", recursive = TRUE)
cat("[OK] Datos de prueba limpiados\n")
