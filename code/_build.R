# Meta --------------------------------------------------------------------

## Title:         Physician Compare Pipeline
## Author:        Ian McCarthy
## Date Created:  2026-02-16
## Description:   Orchestrator script. Sources all processing scripts in order.


# Preliminaries -----------------------------------------------------------

source("code/0-setup.R")


# Call individual code files ----------------------------------------------

source("code/1a-era1-quarterly.R")
source("code/1b-era2-dac-wide.R")
source("code/1c-era3-facility-afl.R")
source("code/2-combine.R")

message("Build complete.")
