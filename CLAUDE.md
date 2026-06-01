# Physician Compare

## Project Overview

Data processing repo for CMS Physician Compare public data. Extracts and cleans physician demographics, group practice affiliations, and hospital affiliations from quarterly Physician Compare data files. Spun off from the `hc-atlas` repo.

## Data Sources

- **Physician Compare / CMS Archived Snapshots**: CMS physician demographics, group practice affiliations, and hospital affiliations (2013--2026)
  - Source: `research-data/care-compare/physicians/` (formerly `research-data/Physician Compare/`, merged Mar 2026)
  - Symlink: `data/input/physicians` (updated from `data/input/Physician Compare`)
  - Era 1 (2013--2018): quarterly CSVs in `Demographics/YYYY/YYYY_QN.csv`, wide `hosp_afl_N` columns
  - Era 2 (2019--2022): archived zips with DAC CSVs containing wide `hosp_afl_N` columns
  - Era 3 (2023--2026): archived zips with `Facility_Affiliation.csv` (already long-format)

## Pipeline

Scripts in `code/` are numbered in execution order and orchestrated by `_build.R`:

| Script | Purpose |
|--------|---------|
| `0-setup.R` | Load packages via renv |
| `1a-era1-quarterly.R` | Era 1 (2013--2018): read quarterly CSVs, pivot wide→long, write intermediate CSV |
| `1b-era2-dac-wide.R` | Era 2 (2019--2022): extract DAC from zips, pivot wide→long, write intermediate CSV |
| `1c-era3-facility-afl.R` | Era 3 (2023--2026): extract Facility_Affiliation + DAC demographics, write intermediate CSV |
| `2-combine.R` | Stack 3 era intermediates, dedup, export final output, diagnostics, clean up |
| `_build.R` | Orchestrator — sources all scripts in order |

Each era script is self-contained (no shared helpers). `read_pc_file()` is duplicated in 1a and 1b (frozen code for frozen files). Intermediate CSVs (`era{1,2,3}-affiliations.csv`) are written to `data/output/` and deleted by `2-combine.R` after the final export.

### Outputs

| File | Description |
|------|-------------|
| `physician-hospital-affiliations.csv` | Long-format physician NPI + hospital CCN panel (2013--2026). `hosp_name` populated 2013--2022, NA for 2023+. |

## Folder Conventions

- `data/input/` — Raw source data (symlinked, never modified)
- `data/output/` — Cleaned/processed output
- `code/` — Processing scripts, numbered in execution order
- `scratch/` — Temporary work files (gitignored)

## Code Style

- R with tidyverse + data.table
- Packages managed via renv (`renv.lock` + `renv/activate.R`), activated in `0-setup.R`
- No `package::function()` syntax — load packages and call directly

## Data Symlinks

Raw data is symlinked from `research-data/care-compare/physicians/` into `data/input/physicians`. The batch script `scratch/make_symlinks.bat` recreates the symlink on a fresh clone.


## Last Session

- **Date**: 2026-03-01
- Refactored monolithic `1-physician-compare.R` into 4 era-based scripts (`1a`, `1b`, `1c`, `2-combine.R`). Migrated from groundhog to renv.
- Full pipeline verified: 65.9M rows, 2.2M physicians, 10.2K hospitals, 2013 Q2 through 2026 Q1.
- 2024 Q3/Q4 have identical row counts (1,340,878) — CMS zips are identical for months 9--12 that year.
