# Species Distribution Modelling Pipeline for Iberian Bats

Reproducible SDM pipeline for the **29 bat species** of the Iberian Peninsula
and Balearic Islands, at UTM 10x10 km resolution.

Developed within the [Bat Monitoring and Atlas project](https://secemu.org/proyectos/)
of the Spanish Ministry for the Ecological Transition (MITECO), coordinated by
[SECEMU](https://secemu.org/) and Tragsatec, funded by the EU-NextGenerationEU.


---

## Pipeline overview

```
 Raw data                                          Final outputs
 (presences,         ┌─────────────────────┐       (favorability maps,
  UTM grids,         │   R/run_pipeline.R  │        uncertainty index,
  env. variables)    │   orchestrates all  │        response curves)
       │             │   phases via CONFIG │
       ▼             └────────┬────────────┘
                              │
  Phase 0 ── Data preparation ──────────── PAxENV matrices per UTM cell
       │     (01a-01h)                     (~5400 cells, ~40 variables)
       ▼
  Phase 1 ── Variable selection ────────── JSON per species
       │     (02a-02d)                     (stability selection + VIF
       │                                    + ecological guild filter)
       ▼
  Phase 2 ── Environmental model ───────── GLM binomial → Favorability
       │     (03a)                         (bootstrap × 200 iterations)
       ▼
  Phase 3 ── Spatial model ─────────────── GAM / polynomial GLM
       │     (03b)                         (selected by AICc,
       │                                    bootstrap × 200 iterations)
       ▼
  Phase 4 ── Fuzzy intersection ────────── F_final = √(F_env × F_spa)
       │     (03c)
       ▼
  Phase 5 ── Spatial cross-validation ──── k-fold spatial CV
       │     (03d)                         (k=5, 10 repetitions)
       ▼
  Phase 6 ── Uncertainty ───────────────── Composite index
       │     (03e)                         (MESS + bootstrap CI
       │                                    + sampling effort)
       ▼
  Phase 7 ── Atlas maps ────────────────── Favorability, uncertainty,
             (04a-04e)                      bivariate 3×3 maps,
                                            response curves
```

Orchestrated by `R/run_pipeline.R`, configured from `R/00_setup/00_config.R`.
Each species produces its own results folder.

---

## Methodology

### Favorability transformation

The logistic probability from the environmental GLM is transformed into
**environmental favorability** (Real et al. 2006), which corrects for
prevalence bias. This enables direct comparison across species with very
different presence/absence ratios — a critical requirement when modelling
29 species that range from extremely common (e.g. *Pipistrellus pipistrellus*,
present in >70% of cells) to very rare (e.g. *Nyctalus lasiopterus*, <3%).

The transformation is: F = P / (P + (P₀/P₁)) where P is the predicted
probability, P₁ is the proportion of presences, and P₀ = 1 − P₁. A cell with
F > 0.5 is environmentally favorable regardless of the species' prevalence.

### Two-axis ecological guild system

Predictor variable selection is guided by a two-axis classification of species
ecology. Each species is assigned a **shelter guild** (cavernicolous,
arboreal, fissuricolous, generalist) and a **foraging guild** (forest,
riparian, generalist, mosaic, grassland, aerial). The guild system defines
which environmental variables receive priority during selection: for instance,
karst and cave-related variables are prioritized for cavernicolous species,
while forest cover variables are prioritized for arboreal species.

This ecological filter operates within a 7-phase statistical selection
pipeline that also applies correlation thresholds, VIF-based
multicollinearity removal, Harrell's sample-size rule, and stability
selection with 100 bootstrap resamples. The result is a parsimonious,
ecologically interpretable set of predictors per species.

### Environmental and spatial models

The environmental model is a binomial GLM fitted with the selected variables.
Bootstrap resampling (200 iterations by default) provides coefficient
uncertainty estimates. Predictions are converted to favorability.

The spatial model captures residual spatial autocorrelation using UTM
coordinates as predictors. Three candidate structures (quadratic GLM, cubic
GLM, GAM with smooth terms) are compared via AICc, and the best is retained.
This model is also bootstrapped independently.

### Fuzzy intersection

Environmental and spatial favorability are combined through a **geometric
fuzzy intersection** (Acevedo & Real 2012): F_final = √(F_env × F_spa).
This conservative operator ensures that a cell must be favorable in *both*
dimensions to receive a high final score, penalizing cells where only one
component is high.

### Composite uncertainty index

Prediction uncertainty is quantified as a weighted combination of three
sources:

1. **MESS** (Multivariate Environmental Similarity Surface): identifies cells
   where the model extrapolates beyond its training environment (Elith et al.
   2010).
2. **Bootstrap variability**: the width of the 95% confidence interval from
   the bootstrap ensemble, reflecting model coefficient instability.
3. **Sampling effort**: the number of independent survey methods that have
   covered each cell (acoustic, mist-netting, roost surveys, opportunistic).
   Cells surveyed by multiple methods have lower uncertainty.

Weights can be fixed (default: 0.33 each) or adaptive (calibrated per species
based on each component's variance).

### Bivariate mapping

The final atlas maps use a 3x3 bivariate color scheme crossing favorability
(low / medium / high) with uncertainty (low / medium / high). This allows
readers to immediately identify cells with reliable high favorability versus
cells where predictions should be interpreted with caution.

### Spatial cross-validation

Model predictive performance is evaluated using spatially-blocked k-fold
cross-validation (Roberts et al. 2017). Spatial blocks are created via
k-means clustering of UTM coordinates to minimize spatial autocorrelation
between training and test folds. The procedure is repeated 10 times with
different random seeds to obtain stable AUC and TSS estimates.

---

## Requirements

- **R >= 4.2**
- Key packages (managed via `renv`):

| Category | Packages |
|---|---|
| Data manipulation | tidyverse, jsonlite, readxl, broom |
| Spatial data | sf, terra |
| Modelling | mgcv, car, MuMIn, pROC |
| Geology PCA | FactoMineR, factoextra |
| Visualization | scico, patchwork, rnaturalearth, rnaturalearthdata |
| Parallelization | future, future.apply |
| Reproducibility | renv |

Restore the exact package versions with:

```r
renv::restore()
```

---

## Repository structure

```
R/
├── run_pipeline.R                 # Master orchestration script
├── 00_setup/                      # Centralized configuration
│   ├── 00_config.R                # All paths, parameters, phase toggles
│   └── 00_packages.R              # Package installation and loading
├── 01_data_preparation/           # Phase 0: raw data → PAxENV matrices
├── 02_variable_selection/         # Phase 1: 7-phase selection per species
├── 03_modeling/                   # Phases 2–6: GLM, GAM, fuzzy, CV, uncertainty
├── 04_visualization/              # Phase 7: atlas maps and response curves
├── 05_analysis/                   # Supplementary analyses
└── utils/                         # Shared utility modules

examples/
├── simulate_data.R                # Generate reproducible simulated data
└── run_example.R                  # Run the full pipeline on simulated data

data/
├── metadata/                      # Ecological metadata (versioned)
│   ├── especies_gremios.csv       # Species × guild assignments
│   ├── gremios_refugio.csv        # Shelter guild → priority variables
│   ├── gremios_alimentacion.csv   # Foraging guild → priority variables
│   ├── complejos_taxonomicos.csv  # Cryptic species complexes
│   └── diccionario_variables.csv  # Variable dictionary
├── raw/                           # Raw input data (not in repo)
├── processed/                     # Intermediate products (not in repo)
├── modelado_ready/                # Model-ready matrices (not in repo)
└── simulated/                     # Simulated data for examples

docs/                              # Technical documentation per phase
tests/                             # Automated tests
vignettes/                         # Quick-start guide (requires real data)
imagenes/                          # Institutional logos
```

---

## Quick start with simulated data

Real bat occurrence data are not included in this repository. To run the
pipeline end-to-end, use the simulated data generator:

```r
# 1. Restore package environment
renv::restore()

# 2. Generate simulated data (3 synthetic species, ~5400 UTM cells)
source("examples/simulate_data.R")

# 3. Run the full pipeline for one simulated species
source("examples/run_example.R")

# 4. Inspect results in output/modelos/<species_name>/
```

For details on data structure and sources, see `data/README_data.md`.

---

## Quick start with real data

If you have the real survey data:

```r
# 1. Restore packages
renv::restore()

# 2. Place raw data in data/raw/ (presences, shapefiles, variable Excels)

# 3. Run the full pipeline
source("R/run_pipeline.R")

# 4. Run only tests (no raw data needed)
source("tests/test_pipeline.R")
```

---

## References

- **Real, R., Barbosa, A. M. & Vargas, J. M.** (2006). Obtaining environmental
  favourability functions from logistic regression. *Environmental and
  Ecological Statistics*, 13, 237–245.
- **Acevedo, P. & Real, R.** (2012). Favourability: concept, distinctive
  characteristics and potential usefulness. *Naturwissenschaften*, 99, 515–522.
- **Lobo, J. M., Jiménez-Valverde, A. & Hortal, J.** (2010). The uncertain
  nature of absences and their importance in species distribution modelling.
  *Ecography*, 33, 103–114.
- **Elith, J., Kearney, M. & Phillips, S.** (2010). The art of modelling
  range-shifting species. *Methods in Ecology and Evolution*, 1, 330–342.
- **Roberts, D. R. et al.** (2017). Cross-validation strategies for data with
  temporal, spatial, hierarchical, or phylogenetic structure. *Ecography*, 40,
  913–929.
- **Muñoz, A. R. & Real, R.** (2006). Assessing the potential range expansion
  of the exotic monk parakeet in Spain. *Diversity and Distributions*, 12,
  656–665.
- **Dormann, C. F. et al.** (2013). Collinearity: a review of methods to deal
  with it and a simulation study evaluating their performance. *Ecography*, 36,
  27–46.

---

## Geographic scope

Iberian Peninsula and Balearic Islands. The Canary Islands are excluded due to
their distinct biogeographic characteristics and different species composition.

---

## Author

**Guillermo Fandos** — Dept. Biodiversity, Ecology and Evolution, Universidad
Complutense de Madrid *(pipeline development, modelling and analysis)*\
[gfandos.com](https://www.gfandos.com) · [UCM profile](https://produccioncientifica.ucm.es/investigadores/446092/detalle)

### Atlas team

- **Elena Tena** — SECEMU (scientific coordination and data)
- **Silvia María Cabezas León** — SECEMU (scientific coordination and data)
- **SECEMU Commission** (scientific advisory)

## Acknowledgements

We thank Daniel Fuentes Romero, Esther Murciano Quejido and Pedro Rebollo for
their participation in the preparation and processing of the environmental
variables used in this study.

We thank SEO/BirdLife for providing various environmental variables in digital
format and at grid scale for species distribution modelling, which constitutes a
fundamental contribution to the methodological development of this work.

We thank SECEM for sharing their modelling process.

## License

Code: MIT License · Data and results: CC BY 4.0

Citation: see `CITATION.cff`
