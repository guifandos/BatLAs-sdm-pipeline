# ==============================================================================
# utils_corine.R - Agrupacion de variables CORINE Land Cover
# ==============================================================================
# 9 grupos ecologicos relevantes para murcielagos
# ==============================================================================

suppressPackageStartupMessages(library(tidyverse))

agrupar_corine <- function(datos) {
  columnas_clc <- names(datos)[str_detect(names(datos), "^CLC_HISTO_[0-9]")]
  if (length(columnas_clc) == 0) {
    warning("No se encontraron columnas CORINE (CLC_HISTO_)")
    return(datos)
  }
  cat("Columnas CORINE encontradas:", length(columnas_clc), "\n")

  datos %>%
    mutate(
      CLC_bosques = rowSums(select(., matches("CLC_HISTO_(311|312|313|244)")), na.rm = TRUE),
      CLC_rupicola = rowSums(select(., matches("CLC_HISTO_(332|131)")), na.rm = TRUE),
      CLC_acuatico = rowSums(select(., matches("CLC_HISTO_(511|512|411|421|522|523)")), na.rm = TRUE),
      CLC_pastizal = rowSums(select(., matches("CLC_HISTO_(231|321|323|333)")), na.rm = TRUE),
      CLC_mosaico = rowSums(select(., matches("CLC_HISTO_(242|243|241|324|322)")), na.rm = TRUE),
      CLC_cultivo_lenoso = rowSums(select(., matches("CLC_HISTO_(221|223|222)")), na.rm = TRUE),
      CLC_urbano = rowSums(select(., matches("CLC_HISTO_(111|112|141|142)")), na.rm = TRUE),
      CLC_cultivo_intensivo = rowSums(select(., matches("CLC_HISTO_(211|212|213)")), na.rm = TRUE),
      CLC_perturbacion_costera = rowSums(select(., matches("CLC_HISTO_(121|122|123|124|132|133|334|331|422|423)")), na.rm = TRUE)
    )
}

mostrar_resumen_corine <- function(datos) {
  columnas_grupo <- names(datos)[str_detect(names(datos), "^CLC_[a-z]+$")]
  if (length(columnas_grupo) == 0) {
    cat("No se encontraron grupos CLC\n")
    return(invisible(NULL))
  }
  datos %>%
    select(all_of(columnas_grupo)) %>%
    summarise(across(everything(),
                     list(media = ~mean(., na.rm = TRUE),
                          mediana = ~median(., na.rm = TRUE),
                          max = ~max(., na.rm = TRUE)),
                     .names = "{.col}_{.fn}")) %>%
    pivot_longer(everything(),
                 names_to = c("grupo", "estadistico"),
                 names_pattern = "(.+)_(.+)") %>%
    pivot_wider(names_from = estadistico, values_from = value) %>%
    arrange(desc(media)) %>%
    print(n = Inf)
}

message("[OK] Funciones CORINE cargadas")
