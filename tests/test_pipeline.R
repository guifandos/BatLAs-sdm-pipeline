# ==============================================================================
# test_pipeline.R - Tests reproducibles con datos simulados
# ==============================================================================
#
# Verifica que el pipeline funciona correctamente usando datos de prueba
# minimos (2 especies piloto, datos simulados).
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

# --- Generar datos de prueba ---

cat("Generando datos de prueba...\n\n")

set.seed(42)
n_cuad <- 500  # Cuadriculas simuladas
n_vars <- 10   # Variables ambientales

# Simular cuadriculas
cuadriculas <- sprintf("30T%04d", 1:n_cuad)

# Simular variables ambientales
vars <- as.data.frame(matrix(rnorm(n_cuad * n_vars), ncol = n_vars))
names(vars) <- c("Bio01", "Bio05", "Bio06", "Bio12",
                  "SRTM_Alt_mean", "Slope_slope_mean",
                  "Karst_total", "CLC_bosques", "CLC_rupicola", "CLC_acuatico")
vars$CUADRICULA <- cuadriculas
vars$X <- runif(n_cuad, -10, 5)
vars$Y <- runif(n_cuad, 36, 44)

# Simular presencias para 2 especies
prob_rf <- plogis(-1 + 0.5 * vars$Karst_total + 0.3 * vars$CLC_bosques)
prob_pp <- plogis(0 + 0.4 * vars$Bio01 - 0.2 * vars$SRTM_Alt_mean)

vars$`Rhinolophus ferrumequinum` <- rbinom(n_cuad, 1, prob_rf)
vars$`Pipistrellus pipistrellus` <- rbinom(n_cuad, 1, prob_pp)
vars$muestreado <- 1
vars$n_metodos <- sample(0:3, n_cuad, replace = TRUE, prob = c(0.3, 0.4, 0.2, 0.1))

# --- Guardar datos de prueba ---

dir.create("tests/test_data", recursive = TRUE, showWarnings = FALSE)
saveRDS(vars, "tests/test_data/PAxENV_test.rds")

cat(sprintf("  Cuadriculas: %d\n", n_cuad))
cat(sprintf("  Presencias R.ferrumequinum: %d\n", sum(vars$`Rhinolophus ferrumequinum`)))
cat(sprintf("  Presencias P.pipistrellus: %d\n", sum(vars$`Pipistrellus pipistrellus`)))

# --- Test 1: Cargar configuracion ---

cat("\n--- Test 1: Configuracion ---\n")
source("R/00_setup/00_config.R")
cat("  [PASS] CONFIG cargado\n")

# --- Test 2: Funciones core ---

cat("\n--- Test 2: Funciones core ---\n")
source("R/utils/utils_checkpoints.R")
source("R/utils/utils_favorabilidad.R")
source("R/utils/utils_metricas.R")

# Test norm_id
stopifnot(norm_id(" 30tul12 ") == "30TUL12")
cat("  [PASS] norm_id()\n")

# Test favorabilidad
prob <- c(0.1, 0.5, 0.9)
y_train <- c(rep(0, 90), rep(1, 10))
fav <- favorabilidad(prob, y_train)
stopifnot(all(fav >= 0 & fav <= 1))
stopifnot(fav[3] > fav[1])
cat("  [PASS] favorabilidad()\n")

# Test compute_metrics
obs <- c(rep(0, 50), rep(1, 50))
pred <- c(runif(50, 0, 0.4), runif(50, 0.6, 1))
met <- compute_metrics(obs, pred)
stopifnot(met$AUC > 0.5)
stopifnot(met$TSS > 0)
cat(sprintf("  [PASS] compute_metrics() AUC=%.3f TSS=%.3f\n", met$AUC, met$TSS))

# --- Test 3: Funciones CORINE ---

cat("\n--- Test 3: Funciones auxiliares ---\n")
source("R/utils/utils_corine.R")

# Test con datos simulados que tienen columnas CLC_HISTO_
datos_clc <- tibble(
  cuadricula = c("A", "B"),
  CLC_HISTO_311 = c(50, 0),
  CLC_HISTO_312 = c(20, 0),
  CLC_HISTO_111 = c(0, 80),
  CLC_HISTO_511 = c(10, 5)
)
datos_agr <- agrupar_corine(datos_clc)
stopifnot("CLC_bosques" %in% names(datos_agr))
stopifnot(datos_agr$CLC_bosques[1] == 70)  # 50 + 20
stopifnot(datos_agr$CLC_urbano[2] == 80)
cat("  [PASS] agrupar_corine()\n")

# --- Test 4: Gremios desde CSV ---

cat("\n--- Test 4: Sistema de gremios ---\n")
source("R/02_variable_selection/02a_funciones_gremios.R")
gremios <- cargar_gremios()
stopifnot(nrow(gremios$especies) > 0)
stopifnot(nrow(gremios$refugio) > 0)
stopifnot(nrow(gremios$alimentacion) > 0)

vars_rf <- obtener_variables_gremio("Rhinolophus ferrumequinum", gremios)
stopifnot(length(vars_rf) > 0)
stopifnot("Karst_total" %in% vars_rf)
cat(sprintf("  [PASS] Gremios cargados: %d especies, %d categorias refugio\n",
            nrow(gremios$especies), nrow(gremios$refugio)))

# --- Test 5: GLM + Favorabilidad ---

cat("\n--- Test 5: Modelo GLM ---\n")

datos_test <- vars %>%
  filter(muestreado == 1) %>%
  select(PA = `Rhinolophus ferrumequinum`, Bio01, Karst_total, CLC_bosques) %>%
  drop_na()

modelo <- glm(PA ~ Bio01 + Karst_total + CLC_bosques, data = datos_test, family = binomial)
pred_prob <- predict(modelo, type = "response")
pred_fav <- favorabilidad(pred_prob, datos_test$PA)

stopifnot(all(pred_fav >= 0 & pred_fav <= 1))
met <- compute_metrics(datos_test$PA, pred_fav)
cat(sprintf("  [PASS] GLM ajustado - AUC=%.3f\n", met$AUC))

# --- Resumen ---

cat("\n================================================================================\n")
cat("  TODOS LOS TESTS PASARON\n")
cat("================================================================================\n\n")

# Limpiar
file.remove("tests/test_data/PAxENV_test.rds")
cat("[OK] Datos de prueba limpiados\n")
