# Meta --------------------------------------------------------------------

## Title:         Physician Compare Processing
## Author:        Ian McCarthy
## Date Created:  2026-02-16
## Description:   Process Physician Compare quarterly demographics (2013-2018).
##                Extracts physician NPI + hospital affiliation CCNs and reshapes
##                to a long physician-hospital panel.
##
## Inputs:        data/input/Physician Compare/Demographics/YYYY/YYYY_QN.csv
##
## Outputs:       data/output/physician-hospital-affiliations.csv
##
## Schema variants:
##   2013:      verbose names, 10 CCN slots ("Claims based hospital affiliation CCN N")
##   2014 Q1:   no header row, 40 cols, verbose layout without DBA name
##   2014 Q2+:  has header, verbose, 5 CCN slots, may have DBA
##   2015-2016: verbose, 5 CCN slots, has DBA
##   2017:      verbose but "Hospital affiliation CCN N" (not "Claims based")
##   2018:      short names (hosp_afl_N), leading spaces in some column names


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


# Load all quarterly files -------------------------------------------------

message("Loading Physician Compare quarterly demographics...")

pc_dir <- "data/input/Physician Compare/Demographics"
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

message(sprintf("  Loaded %d quarterly files", length(all_quarters)))


# Stack and reshape to long ------------------------------------------------

message("\nReshaping wide-to-long...")

pc_wide <- bind_rows(all_quarters)
message(sprintf("  %s physician-quarter rows", format(nrow(pc_wide), big.mark = ",")))

## Pivot CCN and LBN columns to long simultaneously (avoids many-to-many join)
pc_long <- pc_wide %>%
  pivot_longer(
    cols = matches("^hosp_(ccn|name)_\\d+$"),
    names_to = c(".value", "slot"),
    names_pattern = "hosp_(ccn|name)_(\\d+)"
  ) %>%
  rename(hosp_ccn = ccn, hosp_name = name) %>%
  select(-slot) %>%
  filter(!is.na(hosp_ccn), hosp_ccn != "")

message(sprintf("  %s physician-hospital-quarter rows",
                format(nrow(pc_long), big.mark = ",")))


# Deduplicate --------------------------------------------------------------

pc_dedup <- pc_long %>%
  distinct(npi, hosp_ccn, year, quarter, .keep_all = TRUE)

message(sprintf("  %s rows after deduplication",
                format(nrow(pc_dedup), big.mark = ",")))


# Export -------------------------------------------------------------------

write_csv(pc_dedup, "data/output/physician-hospital-affiliations.csv")


# Diagnostics --------------------------------------------------------------

message("\n=== Physician Compare Diagnostics ===")
message(sprintf("Total affiliation rows:    %s",
                format(nrow(pc_dedup), big.mark = ",")))
message(sprintf("Distinct physician NPIs:   %s",
                format(n_distinct(pc_dedup$npi), big.mark = ",")))
message(sprintf("Distinct hospital CCNs:    %s",
                format(n_distinct(pc_dedup$hosp_ccn), big.mark = ",")))

## Year-quarter breakdown
yq <- pc_long %>% count(year, quarter) %>% arrange(year, quarter)
message("\nRows by year-quarter:")
for (r in seq_len(nrow(yq))) {
  message(sprintf("  %d %s: %s", yq$year[r], yq$quarter[r],
                  format(yq$n[r], big.mark = ",")))
}

## Affiliations per physician
message("\nAffiliations per physician (across all year-quarters):")
aff_per_doc <- pc_dedup %>% count(npi) %>% pull(n) %>% summary()
for (nm in names(aff_per_doc)) {
  message(sprintf("  %-10s %.1f", nm, aff_per_doc[nm]))
}

## Top specialties
message("\nTop 10 specialties:")
spec_diag <- pc_dedup %>% count(specialty, sort = TRUE) %>% head(10)
for (r in seq_len(nrow(spec_diag))) {
  message(sprintf("  %-40s %s", spec_diag$specialty[r],
                  format(spec_diag$n[r], big.mark = ",")))
}

message("\nPhysician Compare processing complete.")
message("  Output: data/output/physician-hospital-affiliations.csv")
