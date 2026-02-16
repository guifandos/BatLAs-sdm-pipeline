# ==============================================================================
# utils_pca_litologia.R - PCA de litologia
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(FactoMineR)
  library(factoextra)
})

pca_litologia <- function(datos, n_componentes = 5, save_plots = FALSE, plot_dir = NULL) {
  lito_cols <- names(datos)[str_detect(names(datos), "^lito_HISTO_[0-9]+$")]
  if (length(lito_cols) == 0) stop("No se encontraron columnas lito_HISTO_")

  cat("Variables litologicas:", length(lito_cols), "\n")

  matriz_lito <- datos %>% select(all_of(lito_cols)) %>% as.matrix()
  matriz_lito[is.na(matriz_lito)] <- 0

  pca_result <- PCA(matriz_lito, ncp = n_componentes, graph = FALSE, scale.unit = TRUE)
  pcs <- as.data.frame(pca_result$ind$coord[, 1:n_componentes])
  colnames(pcs) <- paste0("Lito_PC", 1:n_componentes)

  datos_con_pca <- datos %>% bind_cols(pcs)

  var_exp <- pca_result$eig[1:n_componentes, 2]
  cat("Varianza explicada:\n")
  for (i in 1:n_componentes) cat(sprintf("  PC%d: %.1f%%\n", i, var_exp[i]))
  cat(sprintf("Acumulada: %.1f%%\n", sum(var_exp)))

  if (save_plots && !is.null(plot_dir)) {
    dir.create(plot_dir, recursive = TRUE, showWarnings = FALSE)
    p1 <- fviz_eig(pca_result, addlabels = TRUE, ncp = 10) +
      labs(title = "Varianza explicada por componente (Litologia)")
    ggsave(file.path(plot_dir, "pca_litologia_scree.png"), p1, width = 8, height = 6, dpi = 300)

    p2 <- fviz_contrib(pca_result, choice = "var", axes = 1, top = 20) +
      labs(title = "Contribucion de litologias a PC1")
    ggsave(file.path(plot_dir, "pca_litologia_contrib_pc1.png"), p2, width = 10, height = 6, dpi = 300)

    p3 <- fviz_pca_var(pca_result, col.var = "contrib",
                       gradient.cols = c("#00AFBB", "#E7B800", "#FC4E07"),
                       repel = TRUE) +
      labs(title = "Biplot de variables litologicas")
    ggsave(file.path(plot_dir, "pca_litologia_biplot.png"), p3, width = 10, height = 8, dpi = 300)

    cat(sprintf("[OK] Graficos guardados en %s\n", plot_dir))
  }

  list(datos = datos_con_pca, pca = pca_result)
}

message("[OK] Funciones PCA litologia cargadas")
