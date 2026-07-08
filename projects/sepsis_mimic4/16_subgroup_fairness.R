#!/usr/bin/env Rscript
# =============================================================================
# 16_subgroup_fairness.R  --  PHASE 2, TIER 5 (fairness half)
# Subgroup discrimination + calibration of the Tier-1 nomogram's out-of-sample
# risk, by sex and age band. External validation on eICU is DEFERRED (no eICU
# database present locally); this delivers the within-MIMIC fairness check that
# a clinical model needs before deployment.
#
# For each subgroup: n, event rate, AUROC, and calibration-in-the-large
# (mean predicted risk vs observed rate) -- a model can discriminate well
# overall yet be miscalibrated for a subpopulation.
#
# Output: phase2_tier5_subgroups.csv
# Run from projects/sepsis_mimic4/.
# =============================================================================
suppressPackageStartupMessages({ library(pROC) })

find_data <- function(f) {
  cands <- c(file.path("../../processed_data", f),
             file.path("processed_data", f), f)
  hit <- cands[file.exists(cands)][1]; if (is.na(hit)) stop("cannot find ", f); hit
}
OUT <- dirname(find_data("phase2_tier1_oos_pred.csv"))

pred <- read.csv(find_data("phase2_tier1_oos_pred.csv"))
lm6  <- read.csv(find_data("landmark_h6.csv"))[, c("stay_id","age","gender")]
d <- merge(pred, lm6, by="stay_id")
d$age_band <- cut(d$age, c(-Inf,50,65,80,Inf),
                  labels=c("<50","50-64","65-79","80+"))

grp_metrics <- function(sub, label) {
  y <- sub$onset_within_h; p <- sub$risk_en
  au <- tryCatch(as.numeric(auc(roc(y, p, quiet=TRUE, direction="<"))), error=function(e) NA)
  data.frame(subgroup=label, n=nrow(sub), event_rate=round(mean(y),4),
             auroc=round(au,4), mean_pred=round(mean(p),4),
             obs_rate=round(mean(y),4),
             calib_ratio=round(mean(p)/mean(y),3))
}

rows <- list(grp_metrics(d, "ALL"))
for (g in sort(unique(d$gender)))
  rows[[length(rows)+1]] <- grp_metrics(d[d$gender==g,], paste0("sex=",g))
for (b in levels(d$age_band))
  rows[[length(rows)+1]] <- grp_metrics(d[d$age_band==b,], paste0("age=",b))
tab <- do.call(rbind, rows)
print(tab, row.names=FALSE)
write.csv(tab, file.path(OUT, "phase2_tier5_subgroups.csv"), row.names=FALSE)
cat("\nTier 5 (fairness) complete. External eICU validation deferred (no data).\n")
