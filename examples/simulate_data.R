# ==============================================================================
# simulate_data.R — Generate simulated data for pipeline demonstration
# ==============================================================================
#
# Creates synthetic bat occurrence and environmental data that mimics the
# structure of the real dataset, allowing the full SDM pipeline to run
# end-to-end without access to the actual survey data.
#
# OUTPUT:
#   data/simulated/PAxENV_simulated.rds    — PA + env. variables per UTM cell
#   data/simulated/grid_simulated.rds      — Predictor grid (same structure)
#   data/simulated/esfuerzo_simulated.rds  — Sampling effort per cell
#   data/simulated/especies_gremios_sim.csv — Guild assignments for 3 species
#
# The simulated data reproduces:
#   - ~5400 UTM 10x10 km cells across the Iberian Peninsula
#   - ~40 environmental variables with realistic correlations
#   - 3 synthetic species with different ecologies:
#       1. Cavebat simulated   — cavernicolous / forest (common)
#       2. Treebat simulated   — arboreal / forest (medium)
#       3. Generalbat simulated — generalist / generalist (very common)
#   - Presence/absence from 4 survey methods with unequal effort
#
# USAGE:
#   source("examples/simulate_data.R")
#
# ==============================================================================

set.seed(42)

suppressPackageStartupMessages({
  library(tidyverse)
})

cat("\n")
cat("================================================================\n")
cat("  GENERATING SIMULATED DATA FOR PIPELINE DEMONSTRATION\n")
cat("================================================================\n\n")

# ==============================================================================
# 1. SIMULATE UTM GRID (~5400 cells)
# ==============================================================================
# We create a regular grid of UTM coordinates covering the approximate extent
# of the Iberian Peninsula (UTM zone 30N, ETRS89 / EPSG:25830).
# Real coordinates range roughly: X [80000, 830000], Y [3950000, 4850000]

cat("--- Step 1: Generating UTM grid ---\n")

# Grid spacing: 10 km = 10000 m
x_seq <- seq(100000, 800000, by = 10000)
y_seq <- seq(3980000, 4800000, by = 10000)
grid_full <- expand.grid(X_UTM = x_seq, Y_UTM = y_seq)

# Mask to approximate Iberian Peninsula shape (rough polygon filter)
# This removes ocean/Africa cells for a realistic cell count
grid_full$keep <- with(grid_full, {
  # Crude Iberian bounds: wider in the south, narrower in the north
  lat_norm <- (Y_UTM - 3980000) / (4800000 - 3980000)  # 0=south, 1=north
  x_center <- 450000
  x_width <- 350000 - lat_norm * 100000  # narrower toward Pyrenees
  abs(X_UTM - x_center) < x_width &
    # Remove SE corner (Mediterranean Sea approx)
    !(X_UTM > 600000 & Y_UTM < 4100000) &
    # Remove NW corner (Atlantic)
    !(X_UTM < 150000 & Y_UTM > 4600000)
})

grid <- grid_full[grid_full$keep, c("X_UTM", "Y_UTM")]
rownames(grid) <- NULL

# Generate cell IDs in UTM format (e.g., "30TUN65")
grid$CUADRICULA <- paste0("SIM", sprintf("%05d", seq_len(nrow(grid))))
n_cells <- nrow(grid)

cat(sprintf("  Grid cells: %d (target: ~5400)\n", n_cells))

# ==============================================================================
# 2. SIMULATE ENVIRONMENTAL VARIABLES (~40 variables)
# ==============================================================================
# We generate correlated blocks of variables to mimic real environmental data:
#   - Climatic block (Bio01, Bio05, Bio06, Bio12): correlated with latitude
#   - Topographic block (altitude, slope): correlated with each other
#   - Geological block (karst, lithology): partly independent
#   - Land cover block (CORINE categories): compositional (sum to ~100%)

cat("--- Step 2: Generating environmental variables ---\n")

# Helper: generate correlated noise
cor_noise <- function(n, base, sd_val = 1, cor_strength = 0.7) {
  base * cor_strength + rnorm(n, 0, sd_val) * (1 - cor_strength)
}

# --- Latitude / longitude gradients ---
lat_norm <- (grid$Y_UTM - min(grid$Y_UTM)) / diff(range(grid$Y_UTM))
lon_norm <- (grid$X_UTM - min(grid$X_UTM)) / diff(range(grid$X_UTM))

# --- Climatic variables (correlated with latitude) ---
# Bio01: Mean annual temperature (°C x 10), decreases with latitude
grid$Bio01 <- round(180 - lat_norm * 80 + rnorm(n_cells, 0, 15))
# Bio05: Max temperature warmest month, correlated with Bio01
grid$Bio05 <- round(grid$Bio01 * 1.8 + 50 + rnorm(n_cells, 0, 20))
# Bio06: Min temperature coldest month, lower in north
grid$Bio06 <- round(grid$Bio01 * 0.5 - 30 + rnorm(n_cells, 0, 15))
# Bio12: Annual precipitation (mm), higher in NW
grid$Bio12 <- round(400 + (1 - lat_norm) * 200 + (1 - lon_norm) * 400 +
                      rnorm(n_cells, 0, 100))
grid$Bio12 <- pmax(grid$Bio12, 100)

# --- Topographic variables ---
# Altitude: higher in center (simulating Central Plateau + Cordilleras)
dist_center <- sqrt((grid$X_UTM - 450000)^2 + (grid$Y_UTM - 4400000)^2) / 300000
grid$SRTM_Alt_mean <- round(pmax(0, 600 + 400 * (1 - dist_center) +
                                   rnorm(n_cells, 0, 200)))
grid$Slope_slope_mean <- round(pmax(0, grid$SRTM_Alt_mean * 0.02 +
                                      rnorm(n_cells, 0, 3)), 1)

# --- Geological variables ---
# Karst: concentrated in eastern/southern limestone areas
karst_tendency <- pmax(0, lon_norm * 0.4 + (1 - lat_norm) * 0.2 +
                         rnorm(n_cells, 0, 0.15))
grid$Karst_principal <- round(pmin(100, pmax(0, karst_tendency * 60)), 1)
grid$Karst_secundario <- round(pmin(100, pmax(0, karst_tendency * 30 +
                                                rnorm(n_cells, 0, 8))), 1)
grid$Karst_total <- pmin(100, grid$Karst_principal + grid$Karst_secundario)

# Lithology proportions (sum roughly to 100)
raw_lito <- matrix(pmax(0, rnorm(n_cells * 5, 20, 15)), ncol = 5)
raw_lito <- raw_lito / rowSums(raw_lito) * 100
grid$Lito_karsticas <- round(raw_lito[, 1] + karst_tendency * 20, 1)
grid$Lito_siliciclasticas <- round(raw_lito[, 2], 1)
grid$Lito_igneas <- round(raw_lito[, 3], 1)
grid$Lito_metamorficas <- round(raw_lito[, 4], 1)
grid$Lito_diversidad <- round(
  -rowSums(sapply(data.frame(raw_lito / 100), function(p) {
    p <- pmax(p, 1e-6)
    p * log(p)
  })), 2)

# --- Land cover variables (CORINE-derived, compositional) ---
# Forest: more in north/northwest
forest_base <- pmin(100, pmax(0,
  30 + lat_norm * 20 + (1 - lon_norm) * 15 + rnorm(n_cells, 0, 12)))
grid$CLC_bosques <- round(forest_base, 1)
grid$CLC_rupicola <- round(pmax(0, grid$Slope_slope_mean * 0.5 +
                                  rnorm(n_cells, 0, 3)), 1)
grid$CLC_acuatico <- round(pmax(0, 5 + rnorm(n_cells, 0, 4)), 1)
grid$CLC_pastizal <- round(pmax(0, 15 + lat_norm * 10 + rnorm(n_cells, 0, 8)), 1)
grid$CLC_mosaico <- round(pmax(0, 12 + rnorm(n_cells, 0, 6)), 1)
grid$CLC_cultivo_lenoso <- round(pmax(0, 10 + (1 - lat_norm) * 15 +
                                        rnorm(n_cells, 0, 6)), 1)
grid$CLC_urbano <- round(pmax(0, 3 + rnorm(n_cells, 0, 3)), 1)
grid$CLC_cultivo_intensivo <- round(pmax(0, 15 + (1 - lat_norm) * 10 +
                                           rnorm(n_cells, 0, 8)), 1)
grid$CLC_perturbacion_costera <- round(pmax(0, 2 + rnorm(n_cells, 0, 2)), 1)

# --- Additional variables (forest detail, water, Shannon) ---
grid$C_forest_total <- grid$CLC_bosques
grid$C_forest_cadu <- round(pmax(0, grid$CLC_bosques * 0.5 + rnorm(n_cells, 0, 5)), 1)
grid$Haya_ab <- round(pmax(0, lat_norm * 8 + rnorm(n_cells, 0, 3)), 1)
grid$Roble_ab <- round(pmax(0, lat_norm * 10 + (1 - lon_norm) * 5 +
                               rnorm(n_cells, 0, 4)), 1)
grid$Shannon <- round(1.5 + rnorm(n_cells, 0, 0.4), 2)
grid$Comple_veg <- round(pmax(0, 40 + rnorm(n_cells, 0, 12)), 1)
grid$Dens_pob_rec <- round(pmax(0, 50 + rnorm(n_cells, 0, 40)), 1)
grid$Roquedos <- round(pmax(0, grid$CLC_rupicola * 0.8 + rnorm(n_cells, 0, 2)), 1)
grid$Alt_rec <- grid$SRTM_Alt_mean
grid$Slop_rec <- grid$Slope_slope_mean
grid$Masas_agua <- round(pmax(0, grid$CLC_acuatico * 0.6 + rnorm(n_cells, 0, 2)), 1)
grid$Riberas_arb <- round(pmax(0, grid$CLC_acuatico * 0.3 + rnorm(n_cells, 0, 1.5)), 1)
grid$C_amb_acuat <- grid$CLC_acuatico
grid$Olivar <- round(pmax(0, (1 - lat_norm) * 15 + rnorm(n_cells, 0, 5)), 1)
grid$Mosaico_agri <- grid$CLC_mosaico
grid$Cul_herb <- round(pmax(0, grid$CLC_cultivo_intensivo * 0.6 +
                               rnorm(n_cells, 0, 4)), 1)
grid$Herb_ralos <- round(pmax(0, 10 + rnorm(n_cells, 0, 5)), 1)
grid$Herb_altos <- round(pmax(0, 8 + rnorm(n_cells, 0, 4)), 1)

cat(sprintf("  Environmental variables: %d\n",
            ncol(grid) - 3))  # minus CUADRICULA, X_UTM, Y_UTM

# ==============================================================================
# 3. SIMULATE SPECIES OCCURRENCES
# ==============================================================================
# Three synthetic species with different ecological niches:
#
# Species 1: "Cavebat simulated" — cavernicolous forest species
#   Presence driven by: karst, forest cover, medium altitude
#   Prevalence: ~25% (moderate)
#
# Species 2: "Treebat simulated" — arboreal forest species
#   Presence driven by: deciduous forest, higher rainfall, low altitude
#   Prevalence: ~15% (less common)
#
# Species 3: "Generalbat simulated" — generalist species
#   Presence driven by: landscape diversity, moderate temperature
#   Prevalence: ~45% (very common)

cat("--- Step 3: Simulating species occurrences ---\n")

# Standardize predictors for logistic model
std <- function(x) (x - mean(x, na.rm = TRUE)) / sd(x, na.rm = TRUE)

# Species 1: Cavebat (cavernicolous, forest-feeder)
logit_1 <- -1.0 +
  0.8 * std(grid$Karst_total) +
  0.5 * std(grid$Lito_karsticas) +
  0.4 * std(grid$CLC_bosques) +
  -0.3 * std(grid$CLC_urbano) +
  0.2 * std(grid$Bio01)  # slightly thermophilic
prob_1 <- plogis(logit_1)
pa_1 <- rbinom(n_cells, 1, prob_1)

# Species 2: Treebat (arboreal, forest-feeder)
logit_2 <- -1.5 +
  0.7 * std(grid$C_forest_cadu) +
  0.4 * std(grid$Roble_ab) +
  0.3 * std(grid$Bio12) +         # prefers wetter areas
  -0.5 * std(grid$CLC_cultivo_intensivo) +
  -0.3 * std(grid$SRTM_Alt_mean)  # lowland preference
prob_2 <- plogis(logit_2)
pa_2 <- rbinom(n_cells, 1, prob_2)

# Species 3: Generalbat (generalist)
logit_3 <- 0.2 +
  0.5 * std(grid$Shannon) +
  0.3 * std(grid$Comple_veg) +
  -0.4 * std(grid$SRTM_Alt_mean) +
  0.2 * std(grid$Bio01) +
  -0.2 * std(grid$CLC_perturbacion_costera)
prob_3 <- plogis(logit_3)
pa_3 <- rbinom(n_cells, 1, prob_3)

cat(sprintf("  Cavebat simulated:    %d presences / %d cells (%.0f%%)\n",
            sum(pa_1), n_cells, mean(pa_1) * 100))
cat(sprintf("  Treebat simulated:    %d presences / %d cells (%.0f%%)\n",
            sum(pa_2), n_cells, mean(pa_2) * 100))
cat(sprintf("  Generalbat simulated: %d presences / %d cells (%.0f%%)\n",
            sum(pa_3), n_cells, mean(pa_3) * 100))

# ==============================================================================
# 4. SIMULATE SAMPLING EFFORT
# ==============================================================================
# Four survey methods with unequal spatial coverage:
#   - acustica (acoustic): covers ~60% of cells with presences
#   - captura (mist-netting): covers ~30% of cells
#   - cuevas (roost surveys): covers ~20% of cells, biased toward karst
#   - otros (opportunistic): covers ~40% of cells

cat("--- Step 4: Simulating sampling effort ---\n")

# Which cells have been surveyed by each method?
# Acoustic: widespread but patchy
grid$m_acustica <- as.integer(runif(n_cells) < 0.6)
# Mist-netting: less common, slightly biased to forested areas
grid$m_captura <- as.integer(runif(n_cells) < (0.2 + 0.2 * std(grid$CLC_bosques) / 4))
grid$m_captura <- pmax(0, pmin(1, grid$m_captura))
# Roost surveys: biased toward karst regions
grid$m_cuevas <- as.integer(runif(n_cells) < (0.1 + 0.2 * pmin(1, grid$Karst_total / 50)))
# Opportunistic: moderate coverage
grid$m_otros <- as.integer(runif(n_cells) < 0.4)

# A cell is "sampled" if at least one method has covered it
grid$n_metodos <- grid$m_acustica + grid$m_captura + grid$m_cuevas + grid$m_otros
grid$muestreado <- as.integer(grid$n_metodos > 0)

cat(sprintf("  Cells surveyed: %d / %d (%.0f%%)\n",
            sum(grid$muestreado), n_cells, mean(grid$muestreado) * 100))
cat(sprintf("  Methods coverage: acoustic=%.0f%% netting=%.0f%% roost=%.0f%% other=%.0f%%\n",
            mean(grid$m_acustica) * 100, mean(grid$m_captura) * 100,
            mean(grid$m_cuevas) * 100, mean(grid$m_otros) * 100))

# For unsampled cells, set PA to NA (unknown)
pa_1_obs <- ifelse(grid$muestreado == 1, pa_1, NA)
pa_2_obs <- ifelse(grid$muestreado == 1, pa_2, NA)
pa_3_obs <- ifelse(grid$muestreado == 1, pa_3, NA)

# ==============================================================================
# 5. ASSEMBLE PAxENV DATA FRAME
# ==============================================================================
# This mimics the structure of data/processed/PAxENV_all_metodos.rds
# Columns: CUADRICULA, X_UTM, Y_UTM, sp_<species>, <variables>, m_<method>,
#           n_metodos, muestreado

cat("--- Step 5: Assembling PAxENV data frame ---\n")

# Add PA columns with the pipeline's sp_ prefix convention
grid$`sp_Cavebat simulated` <- pa_1_obs
grid$`sp_Treebat simulated` <- pa_2_obs
grid$`sp_Generalbat simulated` <- pa_3_obs

# Save PAxENV
dir.create("data/simulated", recursive = TRUE, showWarnings = FALSE)
saveRDS(grid, "data/simulated/PAxENV_simulated.rds")
cat(sprintf("  Saved: data/simulated/PAxENV_simulated.rds (%d rows x %d cols)\n",
            nrow(grid), ncol(grid)))

# ==============================================================================
# 6. SAVE GRID PREDICTORS (for prediction across all cells)
# ==============================================================================
# This mimics data/processed/predictores_SEO_GEO.rds
# The pipeline reads this to predict favorability across the full grid.

env_vars <- setdiff(names(grid),
                    c("CUADRICULA", "X_UTM", "Y_UTM",
                      grep("^sp_|^m_|^n_metodos|^muestreado", names(grid), value = TRUE)))

grid_predictores <- list(
  vars_all = grid[, env_vars],
  CUADRICULA = grid$CUADRICULA,
  X_UTM = grid$X_UTM,
  Y_UTM = grid$Y_UTM
)
saveRDS(grid_predictores, "data/simulated/grid_simulated.rds")
cat(sprintf("  Saved: data/simulated/grid_simulated.rds (%d vars)\n",
            length(env_vars)))

# ==============================================================================
# 7. SAVE EFFORT TABLE
# ==============================================================================
# This mimics data/processed/esfuerzo_por_metodo.rds

esfuerzo <- grid %>%
  select(CUADRICULA, m_acustica, m_captura, m_cuevas, m_otros, n_metodos)
saveRDS(esfuerzo, "data/simulated/esfuerzo_simulated.rds")
cat("  Saved: data/simulated/esfuerzo_simulated.rds\n")

# ==============================================================================
# 8. CREATE GUILD METADATA FOR SIMULATED SPECIES
# ==============================================================================
# This file is used by run_example.R to override the real guild assignments.

cat("--- Step 6: Creating simulated species metadata ---\n")

especies_sim <- tibble(
  especie = c("Cavebat simulated", "Treebat simulated", "Generalbat simulated"),
  refugio = c("Cavernicola", "Arboricola", "Generalista"),
  alimentacion = c("Forestal", "Forestal", "Generalista"),
  modelar = c(TRUE, TRUE, TRUE),
  complejo = c(NA, NA, NA),
  notas = c("Synthetic cavernicolous species",
            "Synthetic arboreal species",
            "Synthetic generalist species")
)

write_csv(especies_sim, "data/simulated/especies_gremios_sim.csv")
cat("  Saved: data/simulated/especies_gremios_sim.csv\n")

# ==============================================================================
# SUMMARY
# ==============================================================================

cat("\n")
cat("================================================================\n")
cat("  SIMULATED DATA GENERATION COMPLETE\n")
cat("================================================================\n\n")
cat(sprintf("  UTM cells:        %d\n", n_cells))
cat(sprintf("  Env. variables:   %d\n", length(env_vars)))
cat(sprintf("  Species:          3\n"))
cat(sprintf("  Sampled cells:    %d (%.0f%%)\n",
            sum(grid$muestreado), mean(grid$muestreado) * 100))
cat("\n  Files created:\n")
cat("    data/simulated/PAxENV_simulated.rds\n")
cat("    data/simulated/grid_simulated.rds\n")
cat("    data/simulated/esfuerzo_simulated.rds\n")
cat("    data/simulated/especies_gremios_sim.csv\n")
cat("\n  Next step: source('examples/run_example.R')\n")
cat("================================================================\n\n")
