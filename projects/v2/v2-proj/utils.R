# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Abdul Ahad
# utils.R — Shared R utility functions for the pipeline

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(dplyr)
  library(lubridate)
})

# --------------------------------------------------------------------------- #
# Logging
# --------------------------------------------------------------------------- #
v2_log <- function(..., level = "INFO") {
  ts <- format(Sys.time(), "%H:%M:%S")
  cat(sprintf("[%s] [%s] %s\n", ts, level, paste(...)), file = stderr())
}

step <- function(msg) v2_log(msg, level = "STEP")

# --------------------------------------------------------------------------- #
# File I/O helpers
# --------------------------------------------------------------------------- #

#' Read a MIMIC-IV CSV (plain or .gz) efficiently with data.table
read_mimic <- function(path, cols = NULL, nrows = Inf) {
  if (!file.exists(path)) stop("File not found: ", path)
  v2_log("Reading: ", basename(path))
  if (is.finite(nrows)) {
    dt <- data.table::fread(path, select = cols, nrows = nrows,
                            showProgress = FALSE)
  } else {
    dt <- data.table::fread(path, select = cols, showProgress = FALSE)
  }
  v2_log(sprintf("  -> %s rows, %d cols", format(nrow(dt), big.mark=","), ncol(dt)))
  dt
}

#' Save data.table/data.frame to Parquet in V2 output directory
save_parquet <- function(df, name, out_dir) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(out_dir, paste0(name, ".parquet"))
  if (inherits(df, "data.table")) df <- as.data.frame(df)
  arrow::write_parquet(df, path)
  sz <- file.size(path)
  v2_log(sprintf("Saved %s.parquet (%s rows, %d cols, %.1f MB)",
                 name, format(nrow(df), big.mark=","),
                 ncol(df), sz / 1e6))
  invisible(path)
}

#' Load Parquet from V2 output directory
load_parquet <- function(name, out_dir) {
  path <- file.path(out_dir, paste0(name, ".parquet"))
  if (!file.exists(path)) stop("Not found: ", path)
  df <- arrow::read_parquet(path)
  v2_log(sprintf("Loaded %s.parquet (%s rows, %d cols)",
                 name, format(nrow(df), big.mark=","), ncol(df)))
  as.data.table(df)
}

#' Save small result tables as CSV
save_csv <- function(df, name, out_dir) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(out_dir, paste0(name, ".csv"))
  data.table::fwrite(as.data.frame(df), path)
  v2_log(sprintf("Saved %s.csv (%d rows)", name, nrow(df)))
  invisible(path)
}

# --------------------------------------------------------------------------- #
# Weighted discrimination metrics
#
# Person-hours are clustered within ICU stays, so all uncertainty in this
# pipeline comes from a *stay-level* (cluster) bootstrap. Rather than
# materialising a resampled table on every replicate, each replicate is encoded
# as an integer weight per stay: w_s = number of times stay s was drawn. AUROC
# and AUPRC are then evaluated as weighted rank statistics in O(n) using
# pre-sorted data, which makes 2,000 replicates on ~5x10^5 rows tractable.
# --------------------------------------------------------------------------- #

#' Pre-sort a (prediction, outcome, cluster) triple for weighted AUC evaluation
#'
#' @param pred numeric vector of risk scores
#' @param y integer 0/1 outcome
#' @param stay_idx integer index (1..n_stays) identifying the cluster of each row
#' @param n_stays total number of clusters in the resampling frame
#' @return list consumed by boot_auroc_w() / boot_auprc_w()
auc_precompute <- function(pred, y, stay_idx, n_stays) {
  keep <- !is.na(pred) & !is.na(y)
  pred <- as.numeric(pred[keep]); y <- as.integer(y[keep]); stay_idx <- as.integer(stay_idx[keep])
  if (length(pred) == 0L) return(NULL)
  ord <- order(pred)                       # ascending; ties adjacent
  p_o <- pred[ord]
  # last row index of each tie group (groups are contiguous once sorted)
  grp_end <- which(c(p_o[-1] != p_o[-length(p_o)], TRUE))
  list(
    y        = y[ord],
    stay_idx = stay_idx[ord],
    grp_end  = grp_end,
    n        = length(p_o),
    n_stays  = as.integer(n_stays)
  )
}

# Collapse weighted positive/negative mass to tie groups (ascending score order)
.grp_mass <- function(pre, w_stay) {
  w  <- w_stay[pre$stay_idx]
  wy <- w * pre$y
  cy <- cumsum(wy)[pre$grp_end]
  cn <- cumsum(w - wy)[pre$grp_end]
  list(sy = diff(c(0, cy)), sn = diff(c(0, cn)))
}

#' Weighted AUROC (Mann-Whitney form, mid-rank tie handling)
boot_auroc_w <- function(pre, w_stay) {
  if (is.null(pre)) return(NA_real_)
  m <- .grp_mass(pre, w_stay)
  tot_p <- sum(m$sy); tot_n <- sum(m$sn)
  if (tot_p == 0 || tot_n == 0) return(NA_real_)
  neg_less <- c(0, cumsum(m$sn)[-length(m$sn)])
  sum(m$sy * (neg_less + 0.5 * m$sn)) / (tot_p * tot_n)
}

#' Weighted AUPRC (trapezoidal integration of the PR curve, as PRROC auc.integral)
boot_auprc_w <- function(pre, w_stay) {
  if (is.null(pre)) return(NA_real_)
  m <- .grp_mass(pre, w_stay)
  tot_p <- sum(m$sy); tot_n <- sum(m$sn)
  if (tot_p == 0 || tot_n == 0) return(NA_real_)
  # sweep the threshold from the highest score downwards
  sy <- rev(m$sy); sn <- rev(m$sn)
  tp <- cumsum(sy); fp <- cumsum(sn)
  rec  <- tp / tot_p
  prec <- tp / (tp + fp)
  keep <- tp > 0
  if (!any(keep)) return(0)
  rec <- c(0, rec[keep]); prec <- c(prec[keep][1], prec[keep])
  sum(diff(rec) * (head(prec, -1) + tail(prec, -1)) / 2)
}

#' Unweighted convenience wrappers (weights all one)
auroc_point <- function(pred, y) {
  pre <- auc_precompute(pred, y, rep(1L, length(pred)), 1L)
  boot_auroc_w(pre, 1)
}
auprc_point <- function(pred, y) {
  pre <- auc_precompute(pred, y, rep(1L, length(pred)), 1L)
  boot_auprc_w(pre, 1)
}

# --------------------------------------------------------------------------- #
# Cluster bootstrap machinery
# --------------------------------------------------------------------------- #

#' Run a stay-level cluster bootstrap
#'
#' Replicate weight vectors are generated one at a time rather than stored, so
#' memory stays flat regardless of B.
#'
#' @param n_stays number of clusters in the resampling frame
#' @param B number of replicates
#' @param FUN function of the weight vector returning a fixed-length numeric
#'   vector of statistics
#' @param strata optional vector (length n_stays). When given, stays are
#'   resampled *within* stratum so that stratum sizes are held fixed; this is
#'   the appropriate design for subgroup analyses, where the subgroup sizes are
#'   part of the estimand rather than a random quantity.
#' @param seed RNG seed
#' @param progress_every emit a progress line every N replicates (0 = silent)
#' @return matrix, B x length(FUN(...)), of bootstrap statistics
boot_run <- function(n_stays, B, FUN, strata = NULL, seed = 42L, progress_every = 0L) {
  set.seed(seed)
  groups <- if (is.null(strata)) list(seq_len(n_stays)) else
    unname(split(seq_len(n_stays), strata))
  gsize <- vapply(groups, length, integer(1))
  out <- NULL
  for (b in seq_len(B)) {
    w <- integer(n_stays)
    for (gi in seq_along(groups)) {
      ng <- gsize[gi]
      w[groups[[gi]]] <- tabulate(sample.int(ng, ng, replace = TRUE), nbins = ng)
    }
    val <- FUN(w)
    if (is.null(out)) out <- matrix(NA_real_, nrow = B, ncol = length(val),
                                    dimnames = list(NULL, names(val)))
    out[b, ] <- val
    if (progress_every > 0L && b %% progress_every == 0L)
      v2_log(sprintf("  bootstrap %d/%d", b, B))
  }
  out
}

#' Percentile bootstrap confidence interval
perc_ci <- function(theta_star, level = 0.95) {
  ts <- theta_star[is.finite(theta_star)]
  if (length(ts) < 10) return(c(lo = NA_real_, hi = NA_real_))
  a <- (1 - level) / 2
  q <- unname(stats::quantile(ts, c(a, 1 - a), na.rm = TRUE))
  c(lo = q[1], hi = q[2])
}

#' Bootstrap p-value obtained by inverting the percentile interval
#'
#' Tests H0: theta <= theta_0 (side = "greater"), H0: theta >= theta_0
#' (side = "less"), or H0: theta == theta_0 (side = "two.sided"). The bootstrap
#' distribution is recentred on the null boundary before the tail area is read
#' off, and the (1 + count)/(B + 1) convention keeps the p-value strictly
#' positive.
boot_pvalue <- function(theta_star, theta_hat, theta_0 = 0, side = c("two.sided", "greater", "less")) {
  side <- match.arg(side)
  ts <- theta_star[is.finite(theta_star)]
  B  <- length(ts)
  if (B < 10 || !is.finite(theta_hat)) return(NA_real_)
  t_centred <- ts - theta_hat          # approximates theta_hat - theta under H0
  d <- theta_hat - theta_0
  switch(side,
    greater   = (1 + sum(t_centred >=  d)) / (B + 1),
    less      = (1 + sum(t_centred <=  d)) / (B + 1),
    two.sided = min(1, 2 * min((1 + sum(t_centred >=  abs(d))) / (B + 1),
                               (1 + sum(t_centred <= -abs(d))) / (B + 1)))
  )
}

#' Exact one-sided upper bound on a binomial rate when zero events are observed
#'
#' Rule-of-three style Clopper-Pearson bound; used where a hypothesis becomes
#' untestable because the outcome is entirely absent from the evaluation window.
zero_event_upper <- function(n, level = 0.95) {
  if (n <= 0) return(NA_real_)
  1 - (1 - level)^(1 / n)
}

# --------------------------------------------------------------------------- #
# Antibiotic matching
# --------------------------------------------------------------------------- #
match_antibiotics <- function(drug_vec, abx_list) {
  drug_lower <- tolower(drug_vec)
  pattern <- paste(tolower(abx_list), collapse = "|")
  grepl(pattern, drug_lower, fixed = FALSE)
}

# --------------------------------------------------------------------------- #
# Time helpers
# --------------------------------------------------------------------------- #
parse_dt <- function(x) {
  as.POSIXct(x, format = "%Y-%m-%d %H:%M:%S", tz = "UTC")
}

hours_diff <- function(t1, t2) {
  as.numeric(difftime(t2, t1, units = "hours"))
}

# --------------------------------------------------------------------------- #
# Person-hour grid builder
# --------------------------------------------------------------------------- #
#' Expand stays into a dense (stay_id, hour) grid
#' hour 0 = ICU intime
build_person_hour_grid <- function(stays, max_hours = 72L) {
  los_h <- pmin(floor(stays$los_hours), max_hours)
  los_h[los_h < 0] <- 0L
  # one row per (stay_id, hour) for hours 0 .. los_h
  reps <- as.integer(los_h) + 1L
  stay_rep <- rep(stays$stay_id, reps)
  hour_rep  <- unlist(lapply(reps, seq_len)) - 1L
  data.table(
    stay_id = as.integer(stay_rep),
    hour    = as.integer(hour_rep)
  )
}

# --------------------------------------------------------------------------- #
# Forward-fill within groups (fast data.table approach)
# --------------------------------------------------------------------------- #
#' Last-observation-carried-forward within stay_id groups
#' dt must be sorted by (stay_id, hour)
ffill_by_stay <- function(dt, cols, time_col = NULL) {
  dt_copy <- copy(dt)
  if (is.null(time_col)) time_col <- if ("hour" %in% names(dt_copy)) "hour" else "obs_hour"
  setorderv(dt_copy, c("stay_id", time_col))
  for (col in cols) {
    dt_copy[, (col) := nafill(get(col), type = "locf"), by = stay_id]
  }
  dt_copy
}

# --------------------------------------------------------------------------- #
# Rolling window helpers
# --------------------------------------------------------------------------- #
#' Rolling mean over past n_h hours within stay groups
rolling_mean_by_stay <- function(dt, col, n_h = 6L, col_out = NULL, time_col = NULL) {
  if (is.null(col_out)) col_out <- paste0(col, "_slope")
  if (is.null(time_col)) time_col <- if ("hour" %in% names(dt)) "hour" else "obs_hour"
  setorderv(dt, c("stay_id", time_col))
  dt[, (col_out) := frollmean(get(col), n = n_h, align = "right",
                               na.rm = TRUE, hasNA = TRUE), by = stay_id]
  dt
}

#' Simple 6-h slope via linear regression on forward-filled values
compute_slope <- function(values, hours) {
  keep <- !is.na(values)
  if (sum(keep) < 2) return(NA_real_)
  coef(lm.fit(cbind(1, hours[keep]), values[keep]))[2]
}

# --------------------------------------------------------------------------- #
# DuckDB-based reader for very large CSV.gz files (pushes predicates to disk)
# Use this instead of fread when the full table exceeds available memory.
# --------------------------------------------------------------------------- #
read_large_csv_filtered <- function(path, cols, itemids = NULL,
                                     hadm_ids = NULL, stay_ids = NULL,
                                     value_col = "valuenum") {
  if (!requireNamespace("duckdb", quietly = TRUE))
    stop("duckdb package required for large file reads. Install with install.packages('duckdb')")
  suppressPackageStartupMessages(library(duckdb))
  con <- dbConnect(duckdb(), dbdir = ":memory:")
  on.exit(dbDisconnect(con, shutdown = TRUE))

  if (!is.null(hadm_ids))
    dbWriteTable(con, "cohort_hadm", data.frame(hadm_id = as.integer(hadm_ids)))
  if (!is.null(stay_ids))
    dbWriteTable(con, "cohort_stay", data.frame(stay_id = as.integer(stay_ids)))

  where_parts <- character(0)
  if (!is.null(itemids))
    where_parts <- c(where_parts,
                     sprintf("itemid IN (%s)", paste(as.integer(itemids), collapse = ",")))
  if (!is.null(value_col) && nzchar(value_col))
    where_parts <- c(where_parts, sprintf("%s IS NOT NULL", value_col))

  from_clause <- sprintf("read_csv('%s', header=true, compression='gzip')", path)
  where_clause <- if (length(where_parts)) paste(" WHERE", paste(where_parts, collapse = " AND ")) else ""

  if (!is.null(stay_ids)) {
    sql <- sprintf(
      "SELECT t.%s FROM %s t INNER JOIN cohort_stay s ON t.stay_id = s.stay_id%s",
      paste(cols, collapse = ", t."), from_clause, where_clause
    )
  } else if (!is.null(hadm_ids)) {
    sql <- sprintf(
      "SELECT t.%s FROM %s t INNER JOIN cohort_hadm h ON t.hadm_id = h.hadm_id%s",
      paste(cols, collapse = ", t."), from_clause, where_clause
    )
  } else {
    sql <- sprintf("SELECT %s FROM %s%s", paste(cols, collapse = ", "), from_clause, where_clause)
  }

  v2_log("DuckDB query: ", substr(sql, 1, 120))
  dt <- as.data.table(dbGetQuery(con, sql))
  v2_log(sprintf("  -> %s rows, %d cols", format(nrow(dt), big.mark = ","), ncol(dt)))
  dt
}

# --------------------------------------------------------------------------- #
# Streaming chunk reader for large tables (labevents, chartevents)
# --------------------------------------------------------------------------- #
stream_agg_by_stay <- function(path, itemids, windows,
                                key_col = "stay_id",
                                time_col = "charttime",
                                value_col = "valuenum",
                                chunksize = 2e6) {
  want_ids <- as.integer(itemids)
  windows_dt <- as.data.table(windows)
  setkey(windows_dt, stay_id)

  partials <- list()
  con <- file(path, "r")
  header <- readLines(con, n = 1)
  col_names <- strsplit(header, ",")[[1]]
  close(con)

  chunk_n <- 0L
  reader <- data.table::fread(path, showProgress = FALSE, nrows = Inf)
  setnames(reader, trimws(names(reader)))

  # Filter by itemid and join to windows
  reader <- reader[itemid %in% want_ids]
  if (nrow(reader) == 0) return(data.table())

  reader[[time_col]] <- parse_dt(reader[[time_col]])
  reader[[key_col]]  <- as.integer(reader[[key_col]])
  reader[[value_col]] <- as.numeric(reader[[value_col]])
  reader <- reader[!is.na(get(key_col)) & !is.na(get(value_col))]

  merged <- merge(reader[, .(stay_id = get(key_col), time = get(time_col),
                              itemid, value = get(value_col))],
                  windows_dt[, .(stay_id, win_start, win_end)],
                  by = "stay_id", all.x = FALSE)
  merged <- merged[time >= win_start & time <= win_end]

  if (nrow(merged) == 0) return(data.table())

  result <- merged[, .(
    vmin   = min(value, na.rm = TRUE),
    vmax   = max(value, na.rm = TRUE),
    vmean  = mean(value, na.rm = TRUE),
    vcount = .N
  ), by = .(stay_id, itemid)]

  v2_log(sprintf("  stream_agg: %s stays x %d itemids",
                 format(result[, uniqueN(stay_id)], big.mark=","),
                 result[, uniqueN(itemid)]))
  result
}

# --------------------------------------------------------------------------- #
# Model-fit guards
# --------------------------------------------------------------------------- #

#' Fail loudly when a declared feature is absent from the data
#'
#' Every stage used to select its predictors with `intersect(FEATURES, names(dt))`,
#' which silently drops any feature whose name does not match a column. That is
#' how heart rate and `hr_slope6h` disappeared from the primary model, the GBT
#' and the Cox model without a single line of output. Selection still uses
#' `intersect()`; this check simply makes the drop visible.
#'
#' @param ... one or more character vectors of required column names
#' @param available column names actually present
#' @param strict when TRUE, stop instead of warning
require_features <- function(..., available, strict = TRUE) {
  wanted  <- unique(unlist(list(...)))
  missing <- setdiff(wanted, available)
  if (length(missing) == 0) {
    cat(sprintf("  Feature check: all %d declared features present.\n", length(wanted)))
    return(invisible(TRUE))
  }
  msg <- sprintf("Declared features absent from the data: %s",
                 paste(missing, collapse = ", "))
  if (isTRUE(strict)) stop(msg, call. = FALSE)
  v2_log(paste0("  ", msg), level = "WARN")
  invisible(FALSE)
}

#' Report convergence and separation diagnostics for a multinom fit
#'
#' `nnet::multinom` reports `convergence = 0` whenever its BFGS stopping rule is
#' met, which on a separated likelihood happens at an essentially arbitrary
#' point: the optimum is at infinity, so "converged" carries no information
#' about identification. The unpenalised 2026-07-30 fits returned
#' `convergence = 0` for every variant while Variant B's fit was degenerate
#' (test predictions reaching 1.0 at a 0.19% hourly event rate). Large
#' coefficients are the observable symptom, so log them explicitly.
#'
#' @param fit  a multinom fit (or NULL / a glm fallback, both passed through)
#' @param tag  label used in the log lines
#' @param warn_at absolute coefficient size above which separation is flagged
check_multinom_fit <- function(fit, tag = "", warn_at = 20) {
  if (is.null(fit) || !inherits(fit, "multinom")) return(invisible(NULL))
  cm  <- coef(fit)
  mx  <- max(abs(cm))
  cat(sprintf("  Fit diagnostics [%s]: convergence=%d  deviance=%.1f  max|coef|=%.3f\n",
              tag, fit$convergence, fit$deviance, mx))
  if (!identical(as.integer(fit$convergence), 0L))
    v2_log(sprintf("  [%s] multinom did NOT converge (maxit reached).", tag), level = "WARN")
  if (mx > warn_at)
    v2_log(sprintf(paste0("  [%s] max|coef| = %.1f exceeds %g - the likelihood may be ",
                          "separated and the fit not identified. Check PLAUSIBLE_RANGES ",
                          "and PRIMARY_MODEL_DECAY."), tag, mx, warn_at), level = "WARN")
  invisible(list(convergence = fit$convergence, max_abs_coef = mx))
}

# --------------------------------------------------------------------------- #
# Cross-label coefficient stability (H2, and the Amendment 5 ablation)
# --------------------------------------------------------------------------- #
#' Flag covariates whose coefficient reverses sign or changes magnitude
#' >= `mag_ratio`-fold across label variants.
#'
#' Factored out of 12_inference.Rmd so the confirmatory H2 count and the
#' ablated-arm count are produced by one implementation. Two implementations of
#' a stability rule would be two chances to compare unlike things, and the whole
#' point of the ablation is that the two counts are comparable.
#'
#' @param coef_dt   coefficient table with columns outcome, term, coef, variant
#' @param variants  variants to compare across (default the pre-registered three)
#' @param mag_ratio magnitude-change threshold
#' @return data.table(term, sign_flip, mag_flip), one row per covariate shared
#'   by all `variants`; spline basis and intercept terms are excluded.
coef_stability_flags <- function(coef_dt, variants = c("A", "B", "C"),
                                 mag_ratio = 2) {
  ct <- as.data.table(coef_dt)
  cs <- ct[outcome == "sepsis" & !grepl("^ns\\(|^\\(Intercept\\)", as.character(term))]
  terms_common <- Reduce(intersect, lapply(variants, function(v)
    unique(as.character(cs[variant == v, term]))))
  if (length(terms_common) == 0)
    return(data.table(term = character(0), sign_flip = logical(0),
                      mag_flip = logical(0)))
  rbindlist(lapply(terms_common, function(tm) {
    vals <- vapply(variants, function(v) {
      r <- cs[variant == v & as.character(term) == tm, coef]
      if (length(r) == 0) NA_real_ else as.numeric(r[1])
    }, numeric(1))
    vals <- vals[!is.na(vals)]
    if (length(vals) < 2)
      return(data.table(term = tm, sign_flip = FALSE, mag_flip = FALSE))
    mag <- abs(vals); mag <- mag[mag > 0]
    data.table(term      = tm,
               sign_flip = diff(range(sign(vals))) != 0,
               mag_flip  = length(mag) >= 2 && (max(mag) / min(mag)) >= mag_ratio)
  }))
}

#' Split stability flags by whether the covariate is action-derived.
#'
#' `ACTION_DERIVED_FEATURES` names columns; a fitted term may carry a factor
#' level suffix (`vaso_any` -> `vaso_anyTRUE`), so matching is by prefix.
stability_by_feature_kind <- function(flags,
                                      action_features = ACTION_DERIVED_FEATURES) {
  f <- as.data.table(flags)
  f[, is_action := vapply(as.character(term), function(tm)
    any(startsWith(tm, action_features)), logical(1))]
  f[, .(n_terms   = .N,
        n_sign    = sum(sign_flip),
        n_mag     = sum(mag_flip),
        n_unstable = sum(sign_flip | mag_flip),
        pct_unstable = round(100 * sum(sign_flip | mag_flip) / .N, 1)),
    by = .(kind = fifelse(is_action, "action-derived", "physiological"))]
}
