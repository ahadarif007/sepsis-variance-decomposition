# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Abdul Ahad
# clinical_scores.R — Clinical scoring functions for V2 pipeline
#
# Implements: SOFA, NEWS2 (primary rule-based comparator), SIRS, qSOFA
# NEWS2 replaces qSOFA as headline comparator per Evans et al. (2021).
# qSOFA and SIRS retained as descriptive reference only.
#
# References:
# - SOFA: Vincent et al. 1996; thresholds per Singer et al. (Sepsis-3) 2016.
# - NEWS2: Royal College of Physicians, 2017.
# - qSOFA: Seymour et al. JAMA 2016. (not used as primary comparator in V2)
# - SIRS: Bone et al. 1992. (descriptive only in V2)

# --------------------------------------------------------------------------- #
# SOFA scoring
# --------------------------------------------------------------------------- #
#' Score all 6 SOFA components hourly from a person-hour panel
#' Returns a data.table with sofa_resp, sofa_coag, sofa_liver,
#' sofa_cardio, sofa_cns, sofa_renal, sofa_total columns.
#' NA values score 0 (assumed-normal per Sepsis-3 convention).
score_sofa <- function(panel) {
  n <- nrow(panel)
  get_col <- function(col) { v <- panel[[col]]; if (is.null(v)) rep(NA_real_, n) else as.numeric(v) }
  pf_ratio   <- get_col("pf_ratio")
  platelets  <- get_col("platelets")
  bilirubin  <- get_col("bilirubin")
  map_val    <- get_col("map")
  gcs_val    <- get_col("gcs")
  creatinine <- get_col("creatinine")

  # Replace NA with assumed-normal defaults
  pf_ratio[is.na(pf_ratio)]     <- 450    # normal PaO2/FiO2 > 400
  platelets[is.na(platelets)]   <- 200    # normal > 150
  bilirubin[is.na(bilirubin)]   <- 0.8   # normal < 1.2
  map_val[is.na(map_val)]       <- 80    # normal > 70
  gcs_val[is.na(gcs_val)]       <- 15    # normal = 15
  creatinine[is.na(creatinine)] <- 0.9   # normal < 1.2

  sofa_resp <- ifelse(pf_ratio < 100, 4L,
               ifelse(pf_ratio < 200, 3L,
               ifelse(pf_ratio < 300, 2L,
               ifelse(pf_ratio < 400, 1L, 0L))))

  sofa_coag <- ifelse(platelets < 20, 4L,
               ifelse(platelets < 50, 3L,
               ifelse(platelets < 100, 2L,
               ifelse(platelets < 150, 1L, 0L))))

  sofa_liver <- ifelse(bilirubin >= 12, 4L,
                ifelse(bilirubin >= 6, 3L,
                ifelse(bilirubin >= 2, 2L,
                ifelse(bilirubin >= 1.2, 1L, 0L))))

  sofa_cardio <- ifelse(map_val < 70, 1L, 0L)
  # Add vasopressor contributions
  if ("vaso_any" %in% names(panel)) {
    sofa_cardio <- pmax(sofa_cardio,
                        ifelse(!is.na(panel$vaso_any) & panel$vaso_any, 2L, 0L))
  }
  if ("norepi_epi_any" %in% names(panel)) {
    sofa_cardio <- pmax(sofa_cardio,
                        ifelse(!is.na(panel$norepi_epi_any) & panel$norepi_epi_any, 3L, 0L))
  }

  sofa_cns <- ifelse(gcs_val < 6, 4L,
              ifelse(gcs_val < 10, 3L,
              ifelse(gcs_val < 13, 2L,
              ifelse(gcs_val < 15, 1L, 0L))))

  sofa_renal <- ifelse(creatinine >= 5.0, 4L,
                ifelse(creatinine >= 3.5, 3L,
                ifelse(creatinine >= 2.0, 2L,
                ifelse(creatinine >= 1.2, 1L, 0L))))

  sofa_total <- sofa_resp + sofa_coag + sofa_liver + sofa_cardio +
                sofa_cns + sofa_renal

  data.frame(
    sofa_resp    = as.integer(sofa_resp),
    sofa_coag    = as.integer(sofa_coag),
    sofa_liver   = as.integer(sofa_liver),
    sofa_cardio  = as.integer(sofa_cardio),
    sofa_cns     = as.integer(sofa_cns),
    sofa_renal   = as.integer(sofa_renal),
    sofa_total   = as.integer(sofa_total)
  )
}

# --------------------------------------------------------------------------- #
# NEWS2 (National Early Warning Score 2) — primary rule-based comparator
# Royal College of Physicians, 2017.
# Uses Scale 1 SpO2 (no COPD flag available in MIMIC-IV routinely).
# --------------------------------------------------------------------------- #
#' Compute NEWS2 total score (0-20) from physiological variables.
#' Each argument is a numeric vector (same length).
#' NA values score 0 on that parameter (clinically conservative assumption).
news2 <- function(resp_rate, spo2, supplemental_o2, sbp, hr, temp_c, avpu_alert) {
  # Respiration rate
  rr <- ifelse(is.na(resp_rate), 0L,
        ifelse(resp_rate <= 8, 3L,
        ifelse(resp_rate <= 11, 1L,
        ifelse(resp_rate <= 20, 0L,
        ifelse(resp_rate <= 24, 2L, 3L)))))

  # SpO2 Scale 1
  sp <- ifelse(is.na(spo2), 0L,
        ifelse(spo2 <= 91, 3L,
        ifelse(spo2 <= 93, 2L,
        ifelse(spo2 <= 95, 1L, 0L))))

  # Supplemental O2 (1 if on O2, 0 if air)
  o2 <- ifelse(is.na(supplemental_o2), 0L,
        ifelse(supplemental_o2, 2L, 0L))

  # Systolic BP
  sbp_score <- ifelse(is.na(sbp), 0L,
               ifelse(sbp <= 90, 3L,
               ifelse(sbp <= 100, 2L,
               ifelse(sbp <= 110, 1L,
               ifelse(sbp <= 219, 0L, 3L)))))

  # Heart rate
  hr_score <- ifelse(is.na(hr), 0L,
              ifelse(hr <= 40, 3L,
              ifelse(hr <= 50, 1L,
              ifelse(hr <= 90, 0L,
              ifelse(hr <= 110, 1L,
              ifelse(hr <= 130, 2L, 3L))))))

  # Temperature (Celsius)
  temp_score <- ifelse(is.na(temp_c), 0L,
                ifelse(temp_c <= 35.0, 3L,
                ifelse(temp_c <= 36.0, 1L,
                ifelse(temp_c <= 38.0, 0L,
                ifelse(temp_c <= 39.0, 1L, 2L)))))

  # Consciousness: AVPU (Alert = 0, any other = 3)
  # avpu_alert = TRUE if patient is Alert, FALSE or NA if not
  con_score <- ifelse(is.na(avpu_alert) | avpu_alert, 0L, 3L)

  news2_total <- rr + sp + o2 + sbp_score + hr_score + temp_score + con_score

  data.frame(
    news2_rr    = as.integer(rr),
    news2_spo2  = as.integer(sp),
    news2_o2    = as.integer(o2),
    news2_sbp   = as.integer(sbp_score),
    news2_hr    = as.integer(hr_score),
    news2_temp  = as.integer(temp_score),
    news2_con   = as.integer(con_score),
    news2_total = as.integer(news2_total)
  )
}

# NEWS2 threshold for alert (high risk)
news2_alert <- function(news2_total, threshold = 5L) {
  as.integer(!is.na(news2_total) & news2_total >= threshold)
}

#' NEWS2 consciousness flag from GCS, propagating unmeasured as unmeasured.
#'
#' `news2()` scores its `avpu_alert` argument asymmetrically: `NA` contributes 0
#' points (the conservative "not assessed" reading) while `FALSE` contributes 3
#' (an explicit "not alert"). The natural expression `!is.na(gcs) & gcs >= 14`
#' collapses both cases to `FALSE`, so every row with an unmeasured GCS silently
#' acquires 3 NEWS2 points. Where GCS is entirely absent from a data source that
#' is a constant offset applied to every person-hour: harmless for AUROC, which
#' is rank-based, but it moves the score distribution bodily and invalidates any
#' threshold, specificity or alert-burden figure compared across sources.
#'
#' Callers that want the "not assessed scores 0" reading must use this helper.
avpu_alert_flag <- function(gcs, alert_threshold = 14) {
  ifelse(is.na(gcs), NA, gcs >= alert_threshold)
}

# --------------------------------------------------------------------------- #
# qSOFA — retained for descriptive comparison only (NOT primary comparator)
# Evans et al. (2021): strong recommendation AGAINST using as sole screening tool
# --------------------------------------------------------------------------- #
qsofa <- function(resp_rate, gcs, map_val) {
  as.integer(
    ((!is.na(resp_rate)) & (resp_rate >= 22)) +
    ((!is.na(gcs)) & (gcs < 15)) +
    ((!is.na(map_val)) & (map_val < 70))
  )
}

# --------------------------------------------------------------------------- #
# SIRS — retained for descriptive comparison only
# --------------------------------------------------------------------------- #
sirs <- function(hr, resp_rate, temp_c, wbc) {
  as.integer(
    ((!is.na(hr)) & (hr > 90)) +
    ((!is.na(resp_rate)) & (resp_rate > 20)) +
    ((!is.na(temp_c)) & (temp_c > 38 | temp_c < 36)) +
    ((!is.na(wbc)) & (wbc > 12 | wbc < 4))
  )
}
