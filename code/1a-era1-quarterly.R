# Meta --------------------------------------------------------------------

## Title:         Era 1 — Quarterly CSVs (2013-2018)
## Author:        Ian McCarthy
## Date Created:  2026-02-28
## Description:   Read Physician Compare quarterly CSV files for 2013-2018.
##                Handles 5 schema variants across years. Pivots wide hospital
##                affiliation columns to long format and writes intermediate CSV.
##
## Inputs:        data/input/physicians/Demographics/YYYY/YYYY_QN.csv
## Outputs:       data/output/era1-affiliations.csv


# Helper: read one Physician Compare file ----------------------------------

read_pc_file <- function(filepath, yr, qtr) {

  ## Pass 1: detect schema (fast — reads 0 rows or 1 line)
  first_line <- readLines(filepath, n = 1)
  has_header <- grepl("^NPI", first_line)

  if (!has_header) {
    ## No-header files (2014 Q1): position-based extraction
    ## Verified layout: NPI=1, specialty=12, org_name=18, state=25,
    ## CCN/LBN pairs at 27/28, 29/30, 31/32, 33/34, 35/36
    sel_idx <- c(1L, 12L, 18L, 25L, 27L, 28L, 29L, 30L, 31L, 32L, 33L, 34L, 35L, 36L)
    dt <- fread(filepath, header = FALSE, select = sel_idx, colClasses = "character")
    names(dt) <- c("npi", "specialty", "org_name", "state",
                   "hosp_ccn_1", "hosp_name_1", "hosp_ccn_2", "hosp_name_2",
                   "hosp_ccn_3", "hosp_name_3", "hosp_ccn_4", "hosp_name_4",
                   "hosp_ccn_5", "hosp_name_5")
    return(dt %>% as_tibble() %>% mutate(year = yr, quarter = qtr))
  }

  ## Has header — detect column names
  hdr <- fread(filepath, nrows = 0)
  nms <- trimws(names(hdr))

  if (any(grepl("^Claims based hospital affiliation CCN", nms))) {
    ## 2013, 2014 Q2+, 2015-2016
    n_afl <- min(5, sum(grepl("^Claims based hospital affiliation CCN", nms)))
    ccn_cols <- paste("Claims based hospital affiliation CCN", 1:n_afl)
    lbn_cols <- paste("Claims based hospital affiliation LBN", 1:n_afl)
    sel <- c("NPI", "Primary specialty", "Organization legal name", "State",
             ccn_cols, lbn_cols)
    dt <- fread(filepath, select = sel, colClasses = "character")
    names(dt) <- c("npi", "specialty", "org_name", "state",
                   paste0("hosp_ccn_", 1:n_afl), paste0("hosp_name_", 1:n_afl))

  } else if (any(grepl("^Hospital affiliation CCN", nms))) {
    ## 2017
    n_afl <- min(5, sum(grepl("^Hospital affiliation CCN", nms)))
    ccn_cols <- paste("Hospital affiliation CCN", 1:n_afl)
    lbn_cols <- paste("Hospital affiliation LBN", 1:n_afl)
    sel <- c("NPI", "Primary specialty", "Organization legal name", "State",
             ccn_cols, lbn_cols)
    dt <- fread(filepath, select = sel, colClasses = "character")
    names(dt) <- c("npi", "specialty", "org_name", "state",
                   paste0("hosp_ccn_", 1:n_afl), paste0("hosp_name_", 1:n_afl))

  } else if (any(grepl("hosp_afl_\\d+$", nms))) {
    ## 2018: short names (may have leading spaces)
    names(hdr) <- nms  # use trimmed names
    n_afl <- sum(grepl("^hosp_afl_\\d+$", nms))
    ccn_cols <- paste0("hosp_afl_", 1:n_afl)
    lbn_cols <- paste0("hosp_afl_lbn_", 1:n_afl)
    sel <- c("NPI", "pri_spec", "org_nm", "st", ccn_cols, lbn_cols)
    ## Re-read with original (untrimmed) names for select to work
    orig_nms <- names(fread(filepath, nrows = 0))
    ## Map trimmed names to original names for select
    sel_orig <- orig_nms[match(sel, trimws(orig_nms))]
    dt <- fread(filepath, select = sel_orig, colClasses = "character")
    names(dt) <- c("npi", "specialty", "org_name", "state",
                   paste0("hosp_ccn_", 1:n_afl), paste0("hosp_name_", 1:n_afl))

  } else {
    warning(sprintf("  %d-%s: unknown schema — skipping", yr, qtr))
    return(NULL)
  }

  dt %>% as_tibble() %>% mutate(year = yr, quarter = qtr)
}


# Load 2013-2018 quarterly files ------------------------------------------

message("\n--- Era 1: 2013-2018 (quarterly CSVs) ---")

pc_dir <- "data/input/physicians/Demographics"
all_quarters <- list()

for (yr in 2013:2018) {
  yr_dir <- file.path(pc_dir, yr)
  if (!dir.exists(yr_dir)) {
    message(sprintf("  %d: directory not found, skipping", yr))
    next
  }

  files <- list.files(yr_dir, pattern = "\\.csv$", full.names = TRUE)

  for (f in files) {
    qtr <- str_extract(basename(f), "Q\\d")
    if (is.na(qtr)) {
      message(sprintf("  Skipping %s (can't parse quarter)", basename(f)))
      next
    }

    message(sprintf("  Reading %d %s (%s)...", yr, qtr, basename(f)))
    dt <- read_pc_file(f, yr, qtr)
    if (!is.null(dt)) all_quarters[[length(all_quarters) + 1]] <- dt
  }
}

message(sprintf("  Era 1: loaded %d quarterly files", length(all_quarters)))


# Pivot wide to long and export -------------------------------------------

pc_wide <- bind_rows(all_quarters)
message(sprintf("  %s physician-quarter rows (wide)",
                format(nrow(pc_wide), big.mark = ",")))

era1 <- pc_wide %>%
  pivot_longer(
    cols = matches("^hosp_(ccn|name)_\\d+$"),
    names_to = c(".value", "slot"),
    names_pattern = "hosp_(ccn|name)_(\\d+)"
  ) %>%
  rename(hosp_ccn = ccn, hosp_name = name) %>%
  select(-slot) %>%
  filter(!is.na(hosp_ccn), hosp_ccn != "") %>%
  distinct(npi, hosp_ccn, year, quarter, .keep_all = TRUE)

message(sprintf("  %s physician-hospital rows after pivot + dedup",
                format(nrow(era1), big.mark = ",")))

write_csv(era1, "data/output/era1-affiliations.csv")
message("  Wrote data/output/era1-affiliations.csv")

## Year-quarter breakdown
yq <- era1 %>% count(year, quarter) %>% arrange(year, quarter)
for (r in seq_len(nrow(yq))) {
  message(sprintf("    %d %s: %s rows", yq$year[r], yq$quarter[r],
                  format(yq$n[r], big.mark = ",")))
}
