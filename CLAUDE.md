# Physician Compare

## Project Overview

Data processing repo for CMS Physician Compare public data. Extracts and cleans physician demographics, group practice affiliations, and hospital affiliations from quarterly Physician Compare data files. Spun off from the `hc-atlas` repo.

## Data Sources

- **Physician Compare**: CMS quarterly data files containing physician demographics, group practice affiliations, and hospital affiliations (2013--2018)
  - Source: `research-data/Physician Compare/`

## Pipeline

Scripts in `code/` are numbered in execution order and orchestrated by `_build.R`:

| Script | Purpose |
|--------|---------|
| `0-setup.R` | Load packages via groundhog |
| `1-physician-compare.R` | Process quarterly demographics, extract hospital affiliations |
| `_build.R` | Orchestrator — sources all scripts in order |

### Outputs

| File | Description |
|------|-------------|
| `physician-hospital-affiliations.csv` | Long-format physician NPI + hospital CCN panel (2013--2018) |

## Folder Conventions

- `data/input/` — Raw source data (symlinked, never modified)
- `data/output/` — Cleaned/processed output
- `code/` — Processing scripts, numbered in execution order
- `scratch/` — Temporary work files (gitignored)

## Code Style

- R with tidyverse + data.table
- Packages pinned via `groundhog.library()` in `0-setup.R`
- No `package::function()` syntax — load packages and call directly

## Data Symlinks

Raw data is symlinked from `research-data/Physician Compare/` into `data/input/`. The batch script `scratch/make_symlinks.bat` recreates the symlink on a fresh clone.

## Last Session

- **Date**: 2026-02-16
- Scaffolded repo via `/kickoff-data`, ported `6-physician-compare.R` from hc-atlas as `1-physician-compare.R` (removed crosswalk validation section)
- Created data symlink to `research-data/Physician Compare/`
- Pipeline is ready to run but has not been executed yet
