# ==============================================================================
# utils_metricas.R - Metricas de evaluacion de modelos
# ==============================================================================

suppressPackageStartupMessages(library(pROC))

#' Calcular AUC, TSS, Sensibilidad, Especificidad con umbral optimo
compute_metrics <- function(obs, pred) {
  idx_valid <- !is.na(obs) & !is.na(pred)
  obs <- obs[idx_valid]
  pred <- pred[idx_valid]

  if (length(obs) < 10) {
    return(tibble(AUC = NA, TSS = NA, Sens = NA, Spec = NA,
                  Threshold = NA, n = length(obs)))
  }

  roc_obj <- roc(obs, pred, quiet = TRUE)
  auc_val <- as.numeric(auc(roc_obj))

  coords_df <- coords(roc_obj, "all", ret = c("threshold", "sensitivity", "specificity"))
  coords_df$tss <- coords_df$sensitivity + coords_df$specificity - 1

  optimal_idx <- which.max(coords_df$tss)

  tibble(
    AUC = auc_val,
    TSS = coords_df$tss[optimal_idx],
    Sens = coords_df$sensitivity[optimal_idx],
    Spec = coords_df$specificity[optimal_idx],
    Threshold = coords_df$threshold[optimal_idx],
    n = length(obs)
  )
}

confusion_matrix <- function(obs, pred) {
  table(Observed = obs, Predicted = pred)
}

#' Imputar valores faltantes con medianas
impute_median <- function(data, medians) {
  for (var in names(medians)) {
    if (var %in% names(data)) {
      idx_na <- is.na(data[[var]])
      if (any(idx_na)) data[[var]][idx_na] <- medians[[var]]
    }
  }
  return(data)
}

message("[OK] Funciones metricas cargadas")
