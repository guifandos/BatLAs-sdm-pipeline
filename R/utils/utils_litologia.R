# ==============================================================================
# utils_litologia.R - Litologia dominante y diversidad
# ==============================================================================

suppressPackageStartupMessages(library(tidyverse))

calcular_litologia_dominante <- function(datos) {
  req_cols <- c("Lito_karsticas", "Lito_siliciclasticas", "Lito_igneas", "Lito_metamorficas")
  if (!all(req_cols %in% names(datos))) stop("Ejecuta primero agrupar_litologia()")

  datos %>%
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
        (Lito_karsticas + Lito_siliciclasticas + Lito_igneas + Lito_metamorficas + Lito_otras + 1e-10) * 100
    )
}

calcular_diversidad_litologica <- function(datos) {
  req_cols <- c("Lito_karsticas", "Lito_siliciclasticas", "Lito_igneas", "Lito_metamorficas")
  if (!all(req_cols %in% names(datos))) stop("Ejecuta primero agrupar_litologia()")

  datos %>%
    rowwise() %>%
    mutate(
      Lito_total = sum(c(Lito_karsticas, Lito_siliciclasticas, Lito_igneas,
                         Lito_metamorficas, Lito_otras), na.rm = TRUE),
      p_karst = ifelse(Lito_total > 0, Lito_karsticas / Lito_total, 0),
      p_silic = ifelse(Lito_total > 0, Lito_siliciclasticas / Lito_total, 0),
      p_ignea = ifelse(Lito_total > 0, Lito_igneas / Lito_total, 0),
      p_metam = ifelse(Lito_total > 0, Lito_metamorficas / Lito_total, 0),
      p_otras = ifelse(Lito_total > 0, Lito_otras / Lito_total, 0),
      Lito_diversidad = -sum(
        ifelse(p_karst > 0, p_karst * log(p_karst), 0),
        ifelse(p_silic > 0, p_silic * log(p_silic), 0),
        ifelse(p_ignea > 0, p_ignea * log(p_ignea), 0),
        ifelse(p_metam > 0, p_metam * log(p_metam), 0),
        ifelse(p_otras > 0, p_otras * log(p_otras), 0), na.rm = TRUE),
      Lito_n_tipos = sum(c(p_karst > 0, p_silic > 0, p_ignea > 0,
                           p_metam > 0, p_otras > 0), na.rm = TRUE)
    ) %>%
    ungroup() %>%
    select(-starts_with("p_"), -Lito_total)
}

message("[OK] Funciones litologia cargadas")
