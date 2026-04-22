# ==============================================================================
# 03c_bis_comparacion_pmin.R
# ==============================================================================
#
# Compara la interseccion fuzzy geometrica (media geometrica, actual) con la
# interseccion por minimo (pmin) para diagnosticar favorabilidades espurias
# en zonas sin presencias (caso Baleares para M. blythii y N. noctula).
#
# Reutiliza los bootstrap_samples ya guardados en
# output_version_final_20260417/modelos/{sp}/{ambiental,espacial}/
# NO reajusta modelos ni modifica el pipeline oficial.
#
# SALIDA: output_png_final/_comparacion_interseccion_pmin/
#   - mapas PNG por especie (geometrica vs pmin, lado a lado)
#   - resumen_comparacion.csv
#   - README.md (explicacion del diagnostico)
#
# AUTOR: Guillermo Fandos (gfandos@ucm.es)
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(sf)
  library(patchwork)
})

set.seed(42)

# ---- Configuracion ----------------------------------------------------------

DIR_MODELOS <- "output_version_final_20260417/modelos"
DIR_OUT     <- "output_png_final/_comparacion_interseccion_pmin"
PATH_PA     <- "data/processed/PAxENV_all_metodos.rds"
PATH_MALLA  <- "data/processed/malla_union.rds"

# 2 especies con favorabilidad espuria en Baleares + 2 de control peninsular
especies_sel <- c(
  "Myotis_blythii",             # mediterranea, 0 presencias Baleares
  "Nyctalus_noctula",           # pocas presencias peninsulares, 0 Baleares
  "Rhinolophus_ferrumequinum",  # control: amplia distribucion peninsular
  "Pipistrellus_pipistrellus"   # control: ubicua
)

dir.create(DIR_OUT, recursive = TRUE, showWarnings = FALSE)

# ---- Cargar datos comunes ---------------------------------------------------

cat("Cargando datos...\n")
pa    <- readRDS(PATH_PA)
malla <- readRDS(PATH_MALLA)

stopifnot("UTMCODE" %in% names(pa), "UTMCODE" %in% names(malla))

# Flag Baleares por rango lon/lat (pa$X y pa$Y estan en grados)
bal_flag <- pa$Y > 38.5 & pa$Y < 40.5 & pa$X > 1 & pa$X < 5
cat(sprintf("Celdas Baleares identificadas: %d / %d\n", sum(bal_flag), nrow(pa)))

# ---- Bucle especies ---------------------------------------------------------

resumen <- tibble()

for (sp_file in especies_sel) {
  cat(sprintf("\n--- %s ---\n", sp_file))
  sp <- gsub("_", " ", sp_file)

  f_amb <- file.path(DIR_MODELOS, sp_file, "ambiental", "bootstrap_samples.rds")
  f_esp <- file.path(DIR_MODELOS, sp_file, "espacial",  "bootstrap_samples.rds")
  if (!file.exists(f_amb) || !file.exists(f_esp)) {
    cat("  [SKIP] faltan bootstraps\n"); next
  }

  boot_amb <- readRDS(f_amb)
  boot_esp <- readRDS(f_esp)
  stopifnot(nrow(boot_amb) == nrow(pa), nrow(boot_esp) == nrow(pa))

  n_boot <- min(ncol(boot_amb), ncol(boot_esp))
  a <- boot_amb[, seq_len(n_boot), drop = FALSE]
  e <- boot_esp[, seq_len(n_boot), drop = FALSE]

  # Dos metodos de interseccion sobre cada iteracion bootstrap, luego promedio
  F_geom <- rowMeans(sqrt(a * e),  na.rm = TRUE)
  F_pmin <- rowMeans(pmin(a, e),   na.rm = TRUE)
  F_geom[!is.finite(F_geom)] <- NA
  F_pmin[!is.finite(F_pmin)] <- NA

  col_sp <- paste0("sp_", sp)
  pres_bal <- if (col_sp %in% names(pa)) sum(pa[[col_sp]] == 1 & bal_flag,  na.rm = TRUE) else NA_integer_
  pres_pen <- if (col_sp %in% names(pa)) sum(pa[[col_sp]] == 1 & !bal_flag, na.rm = TRUE) else NA_integer_

  # Estadisticos resumen (Baleares vs Peninsula)
  q90 <- function(x) as.numeric(quantile(x, 0.9, na.rm = TRUE))
  resumen <- bind_rows(resumen, tibble(
    especie        = sp_file,
    pres_peninsula = pres_pen,
    pres_baleares  = pres_bal,
    F_geom_bal_med = median(F_geom[bal_flag],  na.rm = TRUE),
    F_geom_bal_q90 = q90(F_geom[bal_flag]),
    F_geom_bal_max = suppressWarnings(max(F_geom[bal_flag], na.rm = TRUE)),
    F_pmin_bal_med = median(F_pmin[bal_flag],  na.rm = TRUE),
    F_pmin_bal_q90 = q90(F_pmin[bal_flag]),
    F_pmin_bal_max = suppressWarnings(max(F_pmin[bal_flag], na.rm = TRUE)),
    F_geom_pen_med = median(F_geom[!bal_flag], na.rm = TRUE),
    F_geom_pen_max = suppressWarnings(max(F_geom[!bal_flag], na.rm = TRUE)),
    F_pmin_pen_med = median(F_pmin[!bal_flag], na.rm = TRUE),
    F_pmin_pen_max = suppressWarnings(max(F_pmin[!bal_flag], na.rm = TRUE))
  ))

  # ---- Mapas comparativos -------------------------------------------------
  df_vals <- tibble(UTMCODE = pa$UTMCODE, F_geom = F_geom, F_pmin = F_pmin)
  malla_sp <- malla %>% left_join(df_vals, by = "UTMCODE")

  base_theme <- theme_minimal(base_size = 10) +
    theme(axis.title = element_blank(),
          panel.grid = element_blank())

  p1 <- ggplot(malla_sp) +
    geom_sf(aes(fill = F_geom), color = NA) +
    scale_fill_viridis_c(limits = c(0, 1), na.value = "grey92",
                        name = "F_final") +
    labs(title = "Geometrica  sqrt(F_amb x F_esp)  — ACTUAL") +
    base_theme

  p2 <- ggplot(malla_sp) +
    geom_sf(aes(fill = F_pmin), color = NA) +
    scale_fill_viridis_c(limits = c(0, 1), na.value = "grey92",
                        name = "F_final") +
    labs(title = "Minimo  min(F_amb, F_esp)  — ALTERNATIVA") +
    base_theme

  panel <- (p1 + p2) +
    plot_layout(guides = "collect") +
    plot_annotation(
      title    = sp,
      subtitle = sprintf("Presencias: Peninsula = %d  |  Baleares = %d",
                         pres_pen, pres_bal),
      caption  = "Bootstraps reutilizados de output_version_final_20260417"
    )

  ggsave(file.path(DIR_OUT, paste0(sp_file, ".png")),
         panel, width = 12, height = 5.2, dpi = 140, bg = "white")
  cat(sprintf("  [OK] mapa guardado | F_geom bal max=%.2f | F_pmin bal max=%.2f\n",
              suppressWarnings(max(F_geom[bal_flag], na.rm = TRUE)),
              suppressWarnings(max(F_pmin[bal_flag], na.rm = TRUE))))
}

# ---- Tabla resumen ----------------------------------------------------------

write_csv(resumen, file.path(DIR_OUT, "resumen_comparacion.csv"))
cat(sprintf("\n[OK] resumen en %s/resumen_comparacion.csv\n", DIR_OUT))
cat("\nsessionInfo ---\n")
print(sessionInfo())
