# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Abdul Ahad
#
# Install the pipeline's R dependencies from requirements.txt.
#
# This exists because the instruction it replaces --
#   install.packages(readLines("requirements.txt"))
# -- passed comment lines and blank lines to install.packages() as package
# names and failed. Parse the file properly, and report what is missing or at a
# different version rather than installing silently over the top.
#
# Usage:
#   Rscript install_requirements.R          # install anything missing
#   Rscript install_requirements.R --check  # report only, install nothing

`%||%` <- function(a, b) if (is.null(a) || is.na(a)) b else a

args       <- commandArgs(trailingOnly = TRUE)
check_only <- "--check" %in% args
repo       <- "https://cloud.r-project.org"

# Resolve requirements.txt next to this script, so it works from any wd.
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_dir <- if (length(script_arg)) dirname(sub("^--file=", "", script_arg[1])) else "."
req_file   <- file.path(script_dir, "requirements.txt")
if (!file.exists(req_file)) req_file <- "requirements.txt"
if (!file.exists(req_file))
  stop("requirements.txt not found next to this script or in the working directory.")

lines <- readLines(req_file, warn = FALSE)
lines <- trimws(lines)
lines <- lines[nzchar(lines) & !startsWith(lines, "#")]

parts <- strsplit(lines, "[[:space:]]+")
reqs  <- data.frame(
  package = vapply(parts, `[`, character(1), 1),
  version = vapply(parts, function(p) if (length(p) > 1) p[2] else NA_character_,
                   character(1)),
  stringsAsFactors = FALSE
)

installed_version <- function(p) {
  tryCatch(as.character(utils::packageVersion(p)), error = function(e) NA_character_)
}

reqs$have    <- vapply(reqs$package, installed_version, character(1))
reqs$missing <- is.na(reqs$have)
reqs$differs <- !reqs$missing & !is.na(reqs$version) & reqs$have != reqs$version

cat(sprintf("%-22s %-12s %-12s %s\n", "PACKAGE", "REQUIRED", "INSTALLED", "STATUS"))
for (i in seq_len(nrow(reqs))) {
  status <- if (reqs$missing[i]) "MISSING"
            else if (reqs$differs[i]) "VERSION DIFFERS"
            else "ok"
  cat(sprintf("%-22s %-12s %-12s %s\n", reqs$package[i],
              reqs$version[i] %||% "-",
              if (reqs$missing[i]) "-" else reqs$have[i], status))
}

n_missing <- sum(reqs$missing)
n_differs <- sum(reqs$differs)

cat(sprintf("\n%d required, %d missing, %d at a different version.\n",
            nrow(reqs), n_missing, n_differs))

if (n_differs > 0) {
  cat("\nA differing version is not necessarily a problem, but it is the first\n",
      "thing to check if a re-run does not reproduce a reported estimate.\n",
      "The GBT rows are the designated canary: xgboost is not bit-reproducible\n",
      "across library builds, so those numbers may move while every other\n",
      "estimate reproduces exactly.\n", sep = "")
}

if (check_only) {
  quit(status = if (n_missing > 0) 1L else 0L)
}

if (n_missing > 0) {
  cat("\nInstalling", n_missing, "missing package(s)...\n")
  utils::install.packages(reqs$package[reqs$missing], repos = repo)
} else {
  cat("\nNothing to install.\n")
}
