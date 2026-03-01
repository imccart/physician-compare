# Meta --------------------------------------------------------------------

## Title:         Era 2 — DAC Wide Format (2019-2022)
## Author:        Ian McCarthy
## Date Created:  2026-02-28
## Description:   Read DAC CSVs from CMS archived zips for 2019-2022.
##                These files use the same wide hosp_afl_N format as Era 1.
##                Handles three zip structures: 2019 flat, 2020 archive naming,
##                2021-2022 standard naming. Pivots wide→long and writes
##                intermediate CSV.
##
## Inputs:        data/input/Physician Compare/*.zip (2019-2022 archives)
## Outputs:       data/output/era2-affiliations.csv


# Helper: read one Physician Compare file ----------------------------------
# Same function as Era 1 — duplicated here so each script is self-contained.
# Only the short-name branch (hosp_afl_N) fires for 2019-2022 DAC files.

read_pc_file <- function(filepath, yr, qtr) {

  first_line <- readLines(filepath, n = 1)
  has_header <- grepl("^NPI", first_line)

  if (!has_header) {
    sel_idx <- c(1L, 12L, 18L, 25L, 27L, 28L, 29L, 30L, 31L, 32L, 33L, 34L, 35L, 36L)
    dt <- fread(filepath, header = FALSE, select = sel_idx, colClasses = "character")
    names(dt) <- c("npi", "specialty", "org_name", "state",
                   "hosp_ccn_1", "hosp_name_1", "hosp_ccn_2", "hosp_name_2",
                   "hosp_ccn_3", "hosp_name_3", "hosp_ccn_4", "hosp_name_4",
                   "hosp_ccn_5", "hosp_name_5")
    return(dt %>% as_tibble() %>% mutate(year = yr, quarter = qtr))
  }

  hdr <- fread(filepath, nrows = 0)
  nms <- trimws(names(hdr))

  if (any(grepl("^Claims based hospital affiliation CCN", nms))) {
    n_afl <- min(5, sum(grepl("^Claims based hospital affiliation CCN", nms)))
    ccn_cols <- paste("Claims based hospital affiliation CCN", 1:n_afl)
    lbn_cols <- paste("Claims based hospital affiliation LBN", 1:n_afl)
    sel <- c("NPI", "Primary specialty", "Organization legal name", "State",
             ccn_cols, lbn_cols)
    dt <- fread(filepath, select = sel, colClasses = "character")
    names(dt) <- c("npi", "specialty", "org_name", "state",
                   paste0("hosp_ccn_", 1:n_afl), paste0("hosp_name_", 1:n_afl))

  } else if (any(grepl("^Hospital affiliation CCN", nms))) {
    n_afl <- min(5, sum(grepl("^Hospital affiliation CCN", nms)))
    ccn_cols <- paste("Hospital affiliation CCN", 1:n_afl)
    lbn_cols <- paste("Hospital affiliation LBN", 1:n_afl)
    sel <- c("NPI", "Primary specialty", "Organization legal name", "State",
             ccn_cols, lbn_cols)
    dt <- fread(filepath, select = sel, colClasses = "character")
    names(dt) <- c("npi", "specialty", "org_name", "state",
                   paste0("hosp_ccn_", 1:n_afl), paste0("hosp_name_", 1:n_afl))

  } else if (any(grepl("hosp_afl_\\d+$", nms))) {
    names(hdr) <- nms
    n_afl <- sum(grepl("^hosp_afl_\\d+$", nms))
    ccn_cols <- paste0("hosp_afl_", 1:n_afl)
    lbn_cols <- paste0("hosp_afl_lbn_", 1:n_afl)
    sel <- c("NPI", "pri_spec", "org_nm", "st", ccn_cols, lbn_cols)
    orig_nms <- names(fread(filepath, nrows = 0))
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


# Helper: find the DAC CSV name inside a zip -------------------------------

find_dac_csv <- function(zip_path) {
  files <- unzip(zip_path, list = TRUE)$Name
  dac <- files[grepl("DAC_NationalDownloadableFile\\.csv$|mj5m.pzi6\\.csv$|Physician_Compare_National_Downloadable_File", files)]
  if (length(dac) == 0) return(NULL)
  dac[1]
}


# Quarter map for 2019-2022 -----------------------------------------------

quarter_map <- list(
  "2019" = list(c("Q2", "04"), c("Q3", "07"), c("Q4", "12")),
  "2020" = list(c("Q3", "08"), c("Q4", "12")),
  "2021" = list(c("Q1", "03"), c("Q2", "06"), c("Q3", "09"), c("Q4", "12")),
  "2022" = list(c("Q1", "03"), c("Q2", "06"), c("Q3", "09"), c("Q4", "10"))
)


# Load 2019-2022 from zip archives ----------------------------------------

message("\n--- Era 2: 2019-2022 (archived zips, wide format) ---")

zip_dir <- "data/input/Physician Compare"
tmp_dir <- "scratch/tmp"
dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)

all_quarters <- list()

for (yr in 2019:2022) {
  yr_str <- as.character(yr)
  if (is.null(quarter_map[[yr_str]])) next

  for (qm in quarter_map[[yr_str]]) {
    qtr <- qm[1]
    mo  <- qm[2]

    if (yr == 2019) {
      ## 2019: flat CSVs inside outer zip
      outer_zip <- file.path(zip_dir, "doc_archive_2019.zip")
      csv_name <- sprintf("Physician_Compare_National_Downloadable_File_%s%s.csv", yr, mo)
      unzip(outer_zip, files = csv_name, exdir = tmp_dir, junkpaths = TRUE, overwrite = TRUE)
      csv_path <- file.path(tmp_dir, csv_name)

    } else {
      ## 2020-2022: nested zips (outer year zip → inner month zip → CSV)
      if (yr == 2020) {
        outer_zip <- file.path(zip_dir, "doctors_and_clinicians_archive_2020.zip")
        inner_name <- sprintf("doctors_and_clinicians_archive_%s_%d.zip", mo, yr)
      } else {
        outer_zip <- file.path(zip_dir, sprintf("doctors_and_clinicians_%d.zip", yr))
        inner_name <- sprintf("doctors_and_clinicians_%s_%d.zip", mo, yr)
      }

      unzip(outer_zip, files = inner_name, exdir = tmp_dir, junkpaths = TRUE, overwrite = TRUE)
      inner_zip <- file.path(tmp_dir, inner_name)

      dac_name <- find_dac_csv(inner_zip)
      if (is.null(dac_name)) {
        message(sprintf("  %d %s: no DAC CSV found, skipping", yr, qtr))
        unlink(inner_zip)
        next
      }

      unzip(inner_zip, files = dac_name, exdir = tmp_dir, junkpaths = TRUE, overwrite = TRUE)
      csv_path <- file.path(tmp_dir, basename(dac_name))
      unlink(inner_zip)
    }

    if (!file.exists(csv_path)) {
      message(sprintf("  %d %s: CSV not found after extraction, skipping", yr, qtr))
      next
    }

    message(sprintf("  Reading %d %s (month %s)...", yr, qtr, mo))
    dt <- read_pc_file(csv_path, yr, qtr)
    if (!is.null(dt)) all_quarters[[length(all_quarters) + 1]] <- dt
    unlink(csv_path)
  }
}

unlink(tmp_dir, recursive = TRUE)
message(sprintf("  Era 2: loaded %d quarterly files", length(all_quarters)))


# Pivot wide to long and export -------------------------------------------

pc_wide <- bind_rows(all_quarters)
message(sprintf("  %s physician-quarter rows (wide)",
                format(nrow(pc_wide), big.mark = ",")))

era2 <- pc_wide %>%
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
                format(nrow(era2), big.mark = ",")))

write_csv(era2, "data/output/era2-affiliations.csv")
message("  Wrote data/output/era2-affiliations.csv")

## Year-quarter breakdown
yq <- era2 %>% count(year, quarter) %>% arrange(year, quarter)
for (r in seq_len(nrow(yq))) {
  message(sprintf("    %d %s: %s rows", yq$year[r], yq$quarter[r],
                  format(yq$n[r], big.mark = ",")))
}
