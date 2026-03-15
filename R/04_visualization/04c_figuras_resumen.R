# ==============================================================================
# 04c_figuras_resumen.R - Figuras resumen para publicacion
# ==============================================================================
#
# Genera:
#   - Tabla resumen de metricas por especie
#   - Forest plots de coeficientes
#   - Curvas de respuesta
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es) / UCM
# ==============================================================================

if (!exists("CONFIG")) source("R/00_setup/00_config.R")

suppressPackageStartupMessages({
  library(tidyverse)
  library(jsonlite)
})

cat("\n=== FIGURAS RESUMEN ===\n\n")

# Recopilar metricas de todas las especies
dirs_sp <- list.dirs(CONFIG$output$base, recursive = FALSE)

metricas_todas <- tibble()

for (dir_sp in dirs_sp) {
  sp_name <- str_replace_all(basename(dir_sp), "_", " ")

  # Metricas holdout
  met_file <- file.path(dir_sp, "ambiental", "metricas_holdout.csv")
  if (file.exists(met_file)) {
    met <- read_csv(met_file, show_col_types = FALSE) %>%
      mutate(especie = sp_name, tipo = "holdout")
    metricas_todas <- bind_rows(metricas_todas, met)
  }

  # Metricas CV
  cv_file <- file.path(dir_sp, "validacion", "resumen_cv.csv")
  if (file.exists(cv_file)) {
    cv <- read_csv(cv_file, show_col_types = FALSE) %>%
      transmute(especie = sp_name, tipo = "cv",
                AUC = AUC_mean, TSS = TSS_mean)
    metricas_todas <- bind_rows(metricas_todas, cv)
  }
}

if (nrow(metricas_todas) > 0) {
  cat(sprintf("Especies con metricas: %d\n", n_distinct(metricas_todas$especie)))

  # Guardar tabla completa
  write_csv(metricas_todas, file.path(CONFIG$output$base, "metricas_todas_especies.csv"))

  # Resumen
  resumen <- metricas_todas %>%
    filter(tipo == "holdout") %>%
    arrange(desc(AUC))

  cat("\nRESUMEN DE METRICAS (holdout):\n")
  cat(sprintf("  AUC medio: %.3f +/- %.3f\n",
              mean(resumen$AUC, na.rm = TRUE), sd(resumen$AUC, na.rm = TRUE)))
  cat(sprintf("  TSS medio: %.3f +/- %.3f\n",
              mean(resumen$TSS, na.rm = TRUE), sd(resumen$TSS, na.rm = TRUE)))

  # Grafico de barras AUC por especie
  p_auc <- ggplot(resumen, aes(x = reorder(especie, AUC), y = AUC)) +
    geom_col(fill = "#2C7BB6") +
    geom_hline(yintercept = 0.7, linetype = "dashed", color = "red") +
    coord_flip() +
    labs(title = "AUC por especie (holdout)", x = "", y = "AUC") +
    theme_minimal() +
    theme(plot.title = element_text(hjust = 0.5, face = "bold"))

  ggsave(file.path(CONFIG$output$base, "fig_AUC_por_especie.png"),
         p_auc, width = 20, height = 25, units = "cm", dpi = 300, bg = "white")
  cat("\n[OK] Figuras resumen generadas\n")
} else {
  cat("No se encontraron metricas. Ejecuta primero el pipeline de modelizacion.\n")
}
