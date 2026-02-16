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
| `_build.R` | Orchestrator — sources all scripts in order |

## Folder Conventions

- `data/input/` — Raw source data (symlinked, never modified)
- `data/output/` — Cleaned/processed output
- `code/` — Processing scripts, numbered in execution order
- `scratch/` — Temporary work files (gitignored)

## Code Style

- R with tidyverse + data.table
- Packages pinned via `groundhog.library()` in `0-setup.R`
- No `package::function()` syntax — load packages and call directly
