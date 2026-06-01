# Meta --------------------------------------------------------------------

## Title:         Era 3 — Facility Affiliation (2023-2026)
## Author:        Ian McCarthy
## Date Created:  2026-02-28
## Description:   Read Facility_Affiliation.csv from CMS archived zips for
##                2023-2026. These files are already in long format (one row
##                per NPI-facility). Demographics come from a separate DAC CSV.
##                Handles column name changes mid-2023 and 2024's flat zip
##                structure.
##
## Inputs:        data/input/physicians/*.zip (2023-2026 archives)
## Outputs:       data/output/era3-affiliations.csv


# Helper: find the DAC CSV name inside a zip -------------------------------

find_dac_csv <- function(zip_path) {
  files <- unzip(zip_path, list = TRUE)$Name
  dac <- files[grepl("DAC_NationalDownloadableFile\\.csv$|mj5m.pzi6\\.csv$|Physician_Compare_National_Downloadable_File", files)]
  if (length(dac) == 0) return(NULL)
  dac[1]
}


# Quarter map for 2023-2026 -----------------------------------------------

quarter_map <- list(
  "2023" = list(c("Q1", "03"), c("Q2", "06"), c("Q3", "09"), c("Q4", "12")),
  "2024" = list(c("Q1", "03"), c("Q2", "06"), c("Q3", "09"), c("Q4", "12")),
  "2025" = list(c("Q1", "03"), c("Q2", "06"), c("Q3", "09"), c("Q4", "12")),
  "2026" = list(c("Q1", "02"))
)


# Load 2023-2026 from zip archives ----------------------------------------

message("\n--- Era 3: 2023-2026 (Facility_Affiliation.csv) ---")

zip_dir <- "data/input/physicians"
tmp_dir <- "scratch/tmp"
dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)

long_quarters <- list()

for (yr in 2023:2026) {
  yr_str <- as.character(yr)
  if (is.null(quarter_map[[yr_str]])) next

  for (qm in quarter_map[[yr_str]]) {
    qtr <- qm[1]
    mo  <- qm[2]

    if (yr == 2024) {
      ## 2024: individual monthly zips (flat, not nested)
      inner_zip <- file.path(zip_dir, sprintf("doctors_and_clinicians_%s_%d.zip", mo, yr))
    } else {
      ## Nested: outer year zip → inner month zip
      outer_zip <- file.path(zip_dir, sprintf("doctors_and_clinicians_%d.zip", yr))
      inner_name <- sprintf("doctors_and_clinicians_%s_%d.zip", mo, yr)
      unzip(outer_zip, files = inner_name, exdir = tmp_dir, junkpaths = TRUE, overwrite = TRUE)
      inner_zip <- file.path(tmp_dir, inner_name)
    }

    ## Extract Facility_Affiliation.csv
    fa_files <- unzip(inner_zip, list = TRUE)$Name
    fa_name <- fa_files[grepl("Facility_Affiliation\\.csv$", fa_files)]
    if (length(fa_name) == 0) {
      message(sprintf("  %d %s: no Facility_Affiliation.csv, skipping", yr, qtr))
      if (yr != 2024) unlink(inner_zip)
      next
    }
    unzip(inner_zip, files = fa_name, exdir = tmp_dir, junkpaths = TRUE, overwrite = TRUE)

    ## Extract DAC CSV for demographics
    dac_name <- find_dac_csv(inner_zip)
    if (!is.null(dac_name)) {
      unzip(inner_zip, files = dac_name, exdir = tmp_dir, junkpaths = TRUE, overwrite = TRUE)
    }

    if (yr != 2024) unlink(inner_zip)

    message(sprintf("  Reading %d %s (month %s)...", yr, qtr, mo))

    ## Read Facility_Affiliation: filter to hospitals, keep NPI + CCN
    fa <- fread(file.path(tmp_dir, "Facility_Affiliation.csv"), colClasses = "character")
    names(fa) <- trimws(names(fa))
    ## CCN column name changed mid-2023
    ccn_col <- intersect(names(fa), c("facility_afl_ccn", "Facility Affiliations Certification Number"))
    if (length(ccn_col) == 0) {
      message(sprintf("  %d %s: no CCN column in Facility_Affiliation, skipping", yr, qtr))
      unlink(list.files(tmp_dir, full.names = TRUE))
      next
    }
    fa <- fa %>%
      as_tibble() %>%
      filter(facility_type == "Hospital") %>%
      select(npi = NPI, hosp_ccn = all_of(ccn_col[1]))

    ## Read DAC for demographics (NPI, pri_spec, org_nm/Facility Name, st/State)
    dac_path <- file.path(tmp_dir, basename(dac_name %||% ""))
    if (!is.null(dac_name) && file.exists(dac_path)) {
      orig_nms <- names(fread(dac_path, nrows = 0))
      trimmed  <- trimws(orig_nms)
      ## Map canonical names to whichever variant exists
      spec_col <- orig_nms[match("pri_spec", trimmed)]
      org_col  <- orig_nms[which(trimmed %in% c("org_nm", "Facility Name"))[1]]
      st_col   <- orig_nms[which(trimmed %in% c("st", "State"))[1]]
      npi_col  <- orig_nms[match("NPI", trimmed)]
      sel_orig <- c(npi_col, spec_col, org_col, st_col)
      sel_orig <- sel_orig[!is.na(sel_orig)]

      if (length(sel_orig) >= 2) {
        dac <- fread(dac_path, colClasses = "character", select = sel_orig)
        clean_nms <- c("npi", "specialty", "org_name", "state")[seq_along(sel_orig)]
        names(dac) <- clean_nms
        dac <- dac %>% distinct(npi, .keep_all = TRUE)

        n_before <- nrow(fa)
        fa <- fa %>% left_join(dac, by = "npi")
        stopifnot(nrow(fa) == n_before)
        ## Fill any missing demographic columns
        for (col in c("specialty", "org_name", "state")) {
          if (!col %in% names(fa)) fa[[col]] <- NA_character_
        }
      } else {
        fa <- fa %>% mutate(specialty = NA_character_, org_name = NA_character_,
                            state = NA_character_)
      }
    } else {
      fa <- fa %>% mutate(specialty = NA_character_, org_name = NA_character_,
                          state = NA_character_)
    }

    fa <- fa %>% mutate(hosp_name = NA_character_, year = yr, quarter = qtr)
    long_quarters[[length(long_quarters) + 1]] <- fa

    unlink(list.files(tmp_dir, full.names = TRUE))
  }
}

unlink(tmp_dir, recursive = TRUE)
message(sprintf("  Era 3: loaded %d quarterly files", length(long_quarters)))


# Export ------------------------------------------------------------------

era3 <- bind_rows(long_quarters) %>%
  distinct(npi, hosp_ccn, year, quarter, .keep_all = TRUE)

message(sprintf("  %s physician-hospital rows after dedup",
                format(nrow(era3), big.mark = ",")))

write_csv(era3, "data/output/era3-affiliations.csv")
message("  Wrote data/output/era3-affiliations.csv")

## Year-quarter breakdown
yq <- era3 %>% count(year, quarter) %>% arrange(year, quarter)
for (r in seq_len(nrow(yq))) {
  message(sprintf("    %d %s: %s rows", yq$year[r], yq$quarter[r],
                  format(yq$n[r], big.mark = ",")))
}
