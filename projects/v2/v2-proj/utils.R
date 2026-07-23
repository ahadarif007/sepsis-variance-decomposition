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
