#!/usr/bin/env Rscript
# =============================================================================
# 12_supermodel.R  --  PHASE 2, TIER 2
# Dynamic-prediction landmark SUPERMODEL (van Houwelingen 2007).
#
# One penalized-logistic model fit across the whole stack of landmarks
# {6,12,18,24,36,48}h, with the landmark time s and s-interactions as covariates,
# so evaluating it at the current hour yields an hourly-updating sepsis risk --
# a genuine real-time model built entirely from classical statistics.
#
# Leakage-safe: CV folds are grouped by stay_id (each stay recurs across
# landmarks), and features are only-past. We report:
#   * overall out-of-sample AUROC of the supermodel,
#   * AUC(s): discrimination as a function of the prediction hour s,
#   * a "separate model per landmark" comparator (does pooling+s help?).
#
# Outputs: phase2_tier2_auc_by_landmark.csv, phase2_tier2_supermodel_oos.csv
#          figure/auc_by_landmark.png
# Seed 486649. Run from projects/sepsis_mimic4/.
# =============================================================================

suppressPackageStartupMessages({ library(glmnet); library(pROC) })
set.seed(486649)

find_data <- function(f) {
  cands <- c(file.path("../../processed_data", f),
             file.path("processed_data", f), f)
  hit <- cands[file.exists(cands)][1]
  if (is.na(hit)) stop("cannot find ", f); hit
}
OUT <- dirname(find_data("landmark_stack.csv"))
FIG <- if (dir.exists("figure")) "figure" else { dir.create("figure"); "figure" }

st <- read.csv(find_data("landmark_stack.csv"))
cat(sprintf("Loaded stack: %d rows, %d stays, landmarks {%s}\n",
            nrow(st), length(unique(st$stay_id)),
            paste(sort(unique(st$landmark_time)), collapse = ",")))

# ---- Feature design (same informative-missingness scheme as Tier 1) ---------
vitals <- c("hr","resp_rate","map","spo2","temp_c","gcs")
labs   <- c("lactate","creatinine","wbc","pf_ratio")
slopes <- c("hr_slope6","resp_rate_slope6","map_slope6","spo2_slope6")
scores <- c("sofa_total","qsofa","sirs")

df <- data.frame(row.names = seq_len(nrow(st)))
for (v in c(vitals, scores)) { x <- st[[v]]; x[is.na(x)] <- median(x, na.rm=TRUE); df[[v]] <- x }
for (v in labs)   { x <- st[[v]]; df[[paste0(v,"_msg")]] <- as.integer(is.na(x));
                    x[is.na(x)] <- median(x, na.rm=TRUE); df[[v]] <- x }
for (v in slopes) { x <- st[[v]]; df[[paste0(v,"_msg")]] <- as.integer(is.na(x));
                    x[is.na(x)] <- 0; df[[v]] <- x }
df$age <- st$age; df$female <- as.integer(st$gender == "F")
base_feats <- names(df)

# landmark time and its interactions: s, s^2, and feature x s (standardized s so
# penalization treats the interactions on a comparable scale)
s   <- st$landmark_time
s_z <- as.numeric(scale(s))
df$s   <- s_z
df$s2  <- s_z^2
for (v in base_feats) df[[paste0(v, "_xS")]] <- df[[v]] * s_z   # smooth s-modulation
X <- as.matrix(df)
y <- st$onset_within_h
cat(sprintf("Supermodel design: %d features (incl. s, s^2, %d s-interactions)\n",
            ncol(X), length(base_feats)))

# ---- Patient-grouped 5-fold CV (split on stay_id, NOT rows) -----------------
ids   <- unique(st$stay_id)
idf   <- setNames(sample(rep(1:5, length.out = length(ids))), ids)
fold  <- idf[as.character(st$stay_id)]

oos <- numeric(nrow(X))
for (k in 1:5) {
  tr <- fold != k
  cv <- cv.glmnet(X[tr,], y[tr], family="binomial", alpha=0.5,
                  nfolds=5, standardize=TRUE)
  oos[!tr] <- as.numeric(predict(cv, X[!tr,], s="lambda.min", type="response"))
}

# ---- Comparator: a SEPARATE penalized model per landmark (no pooling) -------
Xb <- as.matrix(df[, base_feats])        # base features only, no s terms
oos_sep <- numeric(nrow(X))
for (sl in sort(unique(s))) {
  idx <- which(s == sl)
  fk  <- fold[idx]
  for (k in 1:5) {
    tr <- fk != k
    if (sum(y[idx][tr]) < 10) { oos_sep[idx][!tr] <- mean(y[idx][tr]); next }
    cv <- cv.glmnet(Xb[idx,][tr,], y[idx][tr], family="binomial",
                    alpha=0.5, nfolds=5, standardize=TRUE)
    oos_sep[idx][!tr] <- as.numeric(predict(cv, Xb[idx,][!tr,],
                                            s="lambda.min", type="response"))
  }
}

# ---- AUC(s): discrimination at each prediction hour -------------------------
auc_at <- function(p, sl) {
  i <- s == sl
  as.numeric(auc(roc(y[i], p[i], quiet=TRUE, direction="<")))
}
grid <- sort(unique(s))
tab <- data.frame(
  landmark_h = grid,
  n_at_risk  = as.integer(table(s)[as.character(grid)]),
  n_onset    = as.integer(tapply(y, s, sum)[as.character(grid)]),
  auc_supermodel   = sapply(grid, function(sl) auc_at(oos, sl)),
  auc_separate     = sapply(grid, function(sl) auc_at(oos_sep, sl)))
tab$auc_supermodel <- round(tab$auc_supermodel, 4)
tab$auc_separate   <- round(tab$auc_separate, 4)
overall <- as.numeric(auc(roc(y, oos, quiet=TRUE, direction="<")))
cat(sprintf("\nOverall supermodel out-of-sample AUROC (pooled): %.4f\n", overall))
print(tab, row.names = FALSE)
write.csv(tab, file.path(OUT, "phase2_tier2_auc_by_landmark.csv"), row.names=FALSE)
write.csv(data.frame(stay_id=st$stay_id, landmark_time=st$landmark_time,
                     onset_within_h=y, risk=oos),
          file.path(OUT, "phase2_tier2_supermodel_oos.csv"), row.names=FALSE)

# ---- Figure: AUC(s) supermodel vs separate ---------------------------------
png(file.path(FIG, "auc_by_landmark.png"), width=1100, height=850, res=200)
plot(tab$landmark_h, tab$auc_supermodel, type="b", pch=19, col="steelblue",
     ylim=range(c(tab$auc_supermodel, tab$auc_separate, 0.5)),
     xlab="Prediction hour s (landmark)", ylab="Out-of-sample AUROC (12h horizon)",
     main="Dynamic AUC(s): landmark supermodel")
lines(tab$landmark_h, tab$auc_separate, type="b", pch=1, lty=2, col="grey40")
abline(h=0.5, lty=3, col="grey70")
legend("topright", c("Supermodel (pooled + s)","Separate per-landmark"),
       col=c("steelblue","grey40"), pch=c(19,1), lty=c(1,2), bty="n", cex=0.8)
dev.off()
cat("\nTier 2 complete.\n")
