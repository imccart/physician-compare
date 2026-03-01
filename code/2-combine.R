# Meta --------------------------------------------------------------------

## Title:         Combine Era Outputs
## Author:        Ian McCarthy
## Date Created:  2026-02-28
## Description:   Read intermediate CSVs from the three era scripts, stack,
##                deduplicate, export final physician-hospital affiliation
##                panel, print diagnostics, and clean up intermediates.
##
## Inputs:        data/output/era1-affiliations.csv
##                data/output/era2-affiliations.csv
##                data/output/era3-affiliations.csv
## Outputs:       data/output/physician-hospital-affiliations.csv


# Read intermediate files -------------------------------------------------

message("\n--- Combining era outputs ---")

era1 <- read_csv("data/output/era1-affiliations.csv", col_types = cols(.default = "c"))
era2 <- read_csv("data/output/era2-affiliations.csv", col_types = cols(.default = "c"))
era3 <- read_csv("data/output/era3-affiliations.csv", col_types = cols(.default = "c"))

message(sprintf("  Era 1: %s rows", format(nrow(era1), big.mark = ",")))
message(sprintf("  Era 2: %s rows", format(nrow(era2), big.mark = ",")))
message(sprintf("  Era 3: %s rows", format(nrow(era3), big.mark = ",")))


# Stack and deduplicate ---------------------------------------------------

## Ensure year/quarter are integer for consistent typing
pc_all <- bind_rows(era1, era2, era3) %>%
  mutate(year = as.integer(year), quarter = quarter)

pc_dedup <- pc_all %>%
  distinct(npi, hosp_ccn, year, quarter, .keep_all = TRUE)

message(sprintf("  %s total rows after stacking", format(nrow(pc_all), big.mark = ",")))
message(sprintf("  %s rows after deduplication", format(nrow(pc_dedup), big.mark = ",")))


# Export ------------------------------------------------------------------

write_csv(pc_dedup, "data/output/physician-hospital-affiliations.csv")
message("  Wrote data/output/physician-hospital-affiliations.csv")


# Diagnostics -------------------------------------------------------------

message("\n=== Physician Compare Diagnostics ===")
message(sprintf("Total affiliation rows:    %s",
                format(nrow(pc_dedup), big.mark = ",")))
message(sprintf("Distinct physician NPIs:   %s",
                format(n_distinct(pc_dedup$npi), big.mark = ",")))
message(sprintf("Distinct hospital CCNs:    %s",
                format(n_distinct(pc_dedup$hosp_ccn), big.mark = ",")))

## Year-quarter breakdown
yq <- pc_dedup %>% count(year, quarter) %>% arrange(year, quarter)
message("\nRows by year-quarter:")
for (r in seq_len(nrow(yq))) {
  message(sprintf("  %d %s: %s", yq$year[r], yq$quarter[r],
                  format(yq$n[r], big.mark = ",")))
}

## hosp_name population by era
message("\nHospital name population rate:")
era12_pct <- pc_dedup %>%
  filter(year <= 2022) %>%
  summarise(pct = mean(!is.na(hosp_name) & hosp_name != "") * 100) %>%
  pull(pct)
era3_pct <- pc_dedup %>%
  filter(year >= 2023) %>%
  summarise(pct = mean(!is.na(hosp_name) & hosp_name != "") * 100) %>%
  pull(pct)
message(sprintf("  2013-2022 (wide):       %.1f%%", era12_pct))
message(sprintf("  2023-2026 (Fac. Afl.):  %.1f%%", era3_pct))

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


# Clean up intermediate files ---------------------------------------------

file.remove("data/output/era1-affiliations.csv",
            "data/output/era2-affiliations.csv",
            "data/output/era3-affiliations.csv")
message("  Cleaned up intermediate CSV files.")
