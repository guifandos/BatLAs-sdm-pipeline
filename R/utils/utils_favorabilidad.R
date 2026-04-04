# ==============================================================================
# utils_favorabilidad.R - Transformacion de favorabilidad (Real et al. 2006)
# ==============================================================================

suppressPackageStartupMessages(library(pROC))

#' Transformacion de probabilidad a favorabilidad
#' Corrige sesgo de prevalencia segun Real et al. (2006)
#' @references Real et al. (2006) J Biogeogr 33:1865-1877
favorabilidad <- function(prob, y_train) {
  n1 <- sum(y_train == 1)
  n0 <- sum(y_train == 0)
  if (n0 == 0) stop("No hay ausencias en datos de entrenamiento")
  # Clamp to avoid Inf/NaN from prob=0 or prob=1
  prob <- pmin(pmax(prob, 1e-15), 1 - 1e-15)
  odds <- prob / (1 - prob)
  prevalence <- n1 / n0
  F <- odds / (prevalence + odds)
  F[F < 0] <- 0
  F[F > 1] <- 1
  F[is.na(F)] <- 0
  return(F)
}

#' Transformacion inversa: favorabilidad a probabilidad
favorabilidad_inv <- function(F, prevalence) {
  prob <- (F * prevalence) / (1 - F + F * prevalence)
  prob[prob < 0] <- 0
  prob[prob > 1] <- 1
  prob[is.na(prob)] <- 0
  return(prob)
}

message("[OK] Funciones favorabilidad cargadas")
