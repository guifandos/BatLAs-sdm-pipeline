# ==============================================================================
# evaluar_residuos_vs_directo.R
# Comparativa: modelo espacial directo vs. residuos
# ==============================================================================
# Compara los resultados del pipeline con modelo espacial directo (output_total_v2)
# vs. el pipeline con modelo espacial de residuos (output_residuos).
#
# Ejecutar DESPUES de que ambos pipelines hayan terminado:
#   source("R/run_residuos_total.R")   # genera output_residuos/
#   source("R/run_residuos_2014.R")    # genera output_residuos_2014/
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(sf)
  library(jsonlite)
  library(patchwork)
})

source("R/00_setup/00_config.R")

# --- Configuration ---
DIR_DIRECTO   <- CONFIG$output$base    # default: output/modelos
DIR_RESIDUOS  <- "output_residuos/modelos"

cat("\n")
cat("================================================================\n")
cat("  COMPARATIVA: ESPACIAL DIRECTO vs. RESIDUOS\n")
cat("================================================================\n\n")

# --- 1. Load species list ---
especies_gremios <- read_csv(CONFIG$paths$especies_gremios, show_col_types = FALSE) %>%
  filter(modelar == TRUE)
especies <- especies_gremios$especie

# --- 2. Compare metrics ---
cat("--- METRICAS DE VALIDACION ---\n\n")

comparacion <- map_dfr(especies, function(sp) {
  sp_file <- str_replace_all(sp, " ", "_")

  # Directo
  pred_dir <- tryCatch(
    read_csv(file.path(DIR_DIRECTO, sp_file, "interseccion", "predicciones.csv"),
             show_col_types = FALSE),
    error = function(e) NULL)

  val_dir <- tryCatch(
    read_csv(file.path(DIR_DIRECTO, sp_file, "validacion", "resumen_cv.csv"),
             show_col_types = FALSE),
    error = function(e) NULL)

  # Residuos
  pred_res <- tryCatch(
    read_csv(file.path(DIR_RESIDUOS, sp_file, "interseccion", "predicciones.csv"),
             show_col_types = FALSE),
    error = function(e) NULL)

  val_res <- tryCatch(
    read_csv(file.path(DIR_RESIDUOS, sp_file, "validacion", "resumen_cv.csv"),
             show_col_types = FALSE),
    error = function(e) NULL)

  if (is.null(pred_dir) || is.null(pred_res)) return(NULL)

  # Extract AUC from CV
  auc_dir <- if (!is.null(val_dir)) val_dir$AUC_mean[1] else NA
  tss_dir <- if (!is.null(val_dir)) val_dir$TSS_mean[1] else NA
  auc_res <- if (!is.null(val_res)) val_res$AUC_mean[1] else NA
  tss_res <- if (!is.null(val_res)) val_res$TSS_mean[1] else NA

  tibble(
    especie = sp,
    # Favorabilidad media
    F_mean_directo  = mean(pred_dir$F_final_mean, na.rm = TRUE),
    F_mean_residuos = mean(pred_res$F_final_mean, na.rm = TRUE),
    # Correlacion entre mapas
    cor_F = cor(pred_dir$F_final_mean, pred_res$F_final_mean, use = "complete.obs"),
    # Incertidumbre (ancho IC 95%)
    W_mean_directo  = mean(pred_dir$W_fuzzy, na.rm = TRUE),
    W_mean_residuos = mean(pred_res$W_fuzzy, na.rm = TRUE),
    # Metricas CV
    AUC_directo  = auc_dir,
    AUC_residuos = auc_res,
    delta_AUC    = auc_res - auc_dir,
    TSS_directo  = tss_dir,
    TSS_residuos = tss_res,
    delta_TSS    = tss_res - tss_dir
  )
})

if (nrow(comparacion) == 0) {
  cat("ERROR: No se encontraron resultados para comparar.\n")
  cat("Asegurate de haber ejecutado run_residuos_total.R primero.\n")
  stop()
}

# --- 3. Print summary table ---
cat(sprintf("%-30s %7s %7s %6s %7s %7s %7s %7s\n",
            "Especie", "AUC_dir", "AUC_res", "dAUC", "TSS_dir", "TSS_res", "cor_F", "dW"))
cat(paste(rep("-", 110), collapse = ""), "\n")

for (i in seq_len(nrow(comparacion))) {
  r <- comparacion[i, ]
  cat(sprintf("%-30s %7.3f %7.3f %+6.3f %7.3f %7.3f %7.3f %+7.3f\n",
              gsub("_", " ", r$especie),
              r$AUC_directo, r$AUC_residuos, r$delta_AUC,
              r$TSS_directo, r$TSS_residuos,
              r$cor_F,
              r$W_mean_residuos - r$W_mean_directo))
}

cat("\n")
cat("--- RESUMEN GLOBAL ---\n\n")
cat(sprintf("  N especies comparadas: %d\n", nrow(comparacion)))
cat(sprintf("  AUC medio directo:     %.3f\n", mean(comparacion$AUC_directo, na.rm = TRUE)))
cat(sprintf("  AUC medio residuos:    %.3f\n", mean(comparacion$AUC_residuos, na.rm = TRUE)))
cat(sprintf("  Delta AUC medio:       %+.3f\n", mean(comparacion$delta_AUC, na.rm = TRUE)))
cat(sprintf("  TSS medio directo:     %.3f\n", mean(comparacion$TSS_directo, na.rm = TRUE)))
cat(sprintf("  TSS medio residuos:    %.3f\n", mean(comparacion$TSS_residuos, na.rm = TRUE)))
cat(sprintf("  Delta TSS medio:       %+.3f\n", mean(comparacion$delta_TSS, na.rm = TRUE)))
cat(sprintf("  Correlacion F media:   %.3f\n", mean(comparacion$cor_F, na.rm = TRUE)))
cat(sprintf("  Especies con AUC mejor (residuos): %d / %d\n",
            sum(comparacion$delta_AUC > 0, na.rm = TRUE), nrow(comparacion)))
cat(sprintf("  Especies con AUC peor (residuos):  %d / %d\n",
            sum(comparacion$delta_AUC < 0, na.rm = TRUE), nrow(comparacion)))
cat(sprintf("  Incertidumbre media directo:   %.3f\n", mean(comparacion$W_mean_directo, na.rm = TRUE)))
cat(sprintf("  Incertidumbre media residuos:  %.3f\n", mean(comparacion$W_mean_residuos, na.rm = TRUE)))

# --- 4. Diagnostic plots ---
cat("\n--- GENERANDO FIGURAS ---\n\n")
dir.create("output_residuos/figs", recursive = TRUE, showWarnings = FALSE)

# Plot 1: AUC comparison
p1 <- ggplot(comparacion, aes(x = AUC_directo, y = AUC_residuos)) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "grey60") +
  geom_point(aes(color = delta_AUC > 0), size = 2.5, alpha = 0.8) +
  scale_color_manual(values = c("TRUE" = "#06D6A0", "FALSE" = "#EF476F"),
                     labels = c("Peor", "Mejor"), name = "Residuos") +
  labs(x = "AUC (directo)", y = "AUC (residuos)",
       title = "AUC: Directo vs. Residuos") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

# Plot 2: Delta AUC distribution
p2 <- ggplot(comparacion, aes(x = reorder(especie, delta_AUC), y = delta_AUC)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey60") +
  geom_col(aes(fill = delta_AUC > 0), width = 0.7) +
  scale_fill_manual(values = c("TRUE" = "#06D6A0", "FALSE" = "#EF476F"), guide = "none") +
  coord_flip() +
  labs(x = NULL, y = "Delta AUC (residuos - directo)",
       title = "Cambio en AUC por especie") +
  theme_minimal(base_size = 9)

# Plot 3: Correlation between maps
p3 <- ggplot(comparacion, aes(x = reorder(especie, cor_F), y = cor_F)) +
  geom_col(fill = "#00B4D8", width = 0.7) +
  coord_flip() +
  labs(x = NULL, y = "Correlacion F_final",
       title = "Similitud entre mapas (directo vs residuos)") +
  theme_minimal(base_size = 9)

# Plot 4: Uncertainty comparison
p4 <- ggplot(comparacion, aes(x = W_mean_directo, y = W_mean_residuos)) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "grey60") +
  geom_point(size = 2.5, alpha = 0.8, color = "#1B2A4A") +
  labs(x = "Incertidumbre media (directo)", y = "Incertidumbre media (residuos)",
       title = "Incertidumbre: Directo vs. Residuos") +
  theme_minimal(base_size = 11)

# Compose
fig_comp <- patchwork::wrap_plots(p1, p2, p3, p4, ncol = 2)
ggsave("output_residuos/figs/comparativa_directo_vs_residuos.png",
       fig_comp, width = 16, height = 14, dpi = 150)
cat("  Guardado: output_residuos/figs/comparativa_directo_vs_residuos.png\n")

# --- 5. Example species maps (top 3 most different) ---
cat("\n--- MAPAS COMPARATIVOS (3 especies mas diferentes) ---\n\n")

grid_sf <- readRDS(CONFIG$paths$predictores_seo_geo_sf)
grid_sf$CUAD_NORM <- toupper(gsub("\\s+", "", trimws(grid_sf$CUADRICULA)))
bbox <- st_bbox(grid_sf)

top3 <- comparacion %>% arrange(cor_F) %>% head(3)

for (i in seq_len(nrow(top3))) {
  sp <- top3$especie[i]
  sp_file <- str_replace_all(sp, " ", "_")
  cat(sprintf("  %s (cor = %.3f, dAUC = %+.3f)\n", sp, top3$cor_F[i], top3$delta_AUC[i]))

  pred_dir <- read_csv(file.path(DIR_DIRECTO, sp_file, "interseccion", "predicciones.csv"),
                       show_col_types = FALSE)
  pred_res <- read_csv(file.path(DIR_RESIDUOS, sp_file, "interseccion", "predicciones.csv"),
                       show_col_types = FALSE)

  # Load PAxENV to get cuadricula alignment
  paxenv <- readRDS(CONFIG$paths$pa_data)
  paxenv$CUAD_NORM <- toupper(gsub("\\s+", "", trimws(paxenv$CUADRICULA)))

  mapa_dir <- grid_sf %>%
    left_join(tibble(CUAD_NORM = paxenv$CUAD_NORM, F_directo = pred_dir$F_final_mean),
              by = "CUAD_NORM")
  mapa_res <- grid_sf %>%
    left_join(tibble(CUAD_NORM = paxenv$CUAD_NORM, F_residuos = pred_res$F_final_mean),
              by = "CUAD_NORM")
  mapa_dif <- grid_sf %>%
    left_join(tibble(CUAD_NORM = paxenv$CUAD_NORM,
                     delta = pred_res$F_final_mean - pred_dir$F_final_mean),
              by = "CUAD_NORM")

  pal <- c("#FDE725", "#5DC863", "#21908C", "#3B528B", "#440154")
  common_coord <- coord_sf(xlim = c(bbox["xmin"], bbox["xmax"]),
                           ylim = c(bbox["ymin"], bbox["ymax"]), expand = FALSE)

  pa <- ggplot(mapa_dir) +
    geom_sf(aes(fill = F_directo), color = NA) +
    scale_fill_gradientn(colors = pal, limits = c(0, 1), name = "F") +
    common_coord + theme_void() + labs(title = "Directo")

  pb <- ggplot(mapa_res) +
    geom_sf(aes(fill = F_residuos), color = NA) +
    scale_fill_gradientn(colors = pal, limits = c(0, 1), name = "F") +
    common_coord + theme_void() + labs(title = "Residuos")

  pc <- ggplot(mapa_dif) +
    geom_sf(aes(fill = delta), color = NA) +
    scale_fill_gradient2(low = "#2166AC", mid = "#F7F7F7", high = "#B2182B",
                         midpoint = 0, limits = c(-0.5, 0.5), name = "Delta") +
    common_coord + theme_void() + labs(title = "Diferencia")

  fig_sp <- patchwork::wrap_plots(pa, pb, pc, ncol = 3) +
    patchwork::plot_annotation(title = sp, theme = theme(plot.title = element_text(face = "bold")))

  ggsave(sprintf("output_residuos/figs/mapa_comp_%s.png", sp_file),
         fig_sp, width = 15, height = 5, dpi = 150)
}

# --- 6. Save results table ---
write_csv(comparacion, "output_residuos/figs/comparativa_metricas.csv")
cat("\n  Tabla guardada: output_residuos/figs/comparativa_metricas.csv\n")

cat("\n================================================================\n")
cat("  COMPARATIVA COMPLETADA\n")
cat("================================================================\n\n")
cat("Revisa:\n")
cat("  1. output_residuos/figs/comparativa_directo_vs_residuos.png  (resumen global)\n")
cat("  2. output_residuos/figs/mapa_comp_*.png                     (mapas comparativos)\n")
cat("  3. output_residuos/figs/comparativa_metricas.csv             (tabla completa)\n\n")
cat("CRITERIOS DE DECISION:\n")
cat("  - Si AUC residuos >= AUC directo para la mayoria: usar residuos para todas\n")
cat("  - Si correlacion F media > 0.95: diferencia practica minima\n")
cat("  - Si incertidumbre residuos < directo: residuos son mas conservadores (mejor)\n")
cat("  - Revisar mapas comparativos para especies con mayor diferencia\n\n")
