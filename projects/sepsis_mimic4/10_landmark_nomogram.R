#!/usr/bin/env Rscript
# =============================================================================
# 10_landmark_nomogram.R  --  PHASE 2, TIER 1
# Full-feature elastic-net penalized-logistic NOMOGRAM at the hour-6 landmark.
#
# Purpose: establish the purely-statistical UPPER BOUND for predicting incident
# Sepsis-3 within 12h of the hour-6 landmark, by dropping Phase 1's deliberate
# non-circular handicap and bringing in the heavily-missing labs via an
# informative-missingness design (median-impute + "was it measured" indicators).
#
# Honest, leakage-safe evaluation:
#   - patient-grouped (landmark is first-stay-only => stay_id disjoint = patient)
#   - OUTER 5-fold CV; lambda chosen by INNER cv.glmnet on each training fold
#   - out-of-sample predictions aggregated for AUROC / PR-AUC / calibration / Brier
#   - DeLong test vs the reconstructed Phase-1 0.755 model on identical folds
#
# Outputs (processed_data/):
#   phase2_tier1_metrics.csv     headline metrics
#   phase2_tier1_coefs.csv       final-model penalized coefficients / odds ratios
#   phase2_tier1_oos_pred.csv    per-stay out-of-sample risk (feeds Tier 4)
# Figures (figure/):
#   calibration_h6.png           calibration curve
#   nomogram_h6.png              clinician-facing nomogram (post-selection lrm)
#
# Seed 486649 (project convention). Run from projects/sepsis_mimic4/.
# =============================================================================

suppressPackageStartupMessages({
  library(glmnet); library(pROC); library(PRROC); library(rms)
})
set.seed(486649)

find_data <- function(f) {
  cands <- c(file.path("../../processed_data", f),
             file.path("processed_data", f), f)
  hit <- cands[file.exists(cands)][1]
  if (is.na(hit)) stop("cannot find ", f)
  hit
}
OUT <- dirname(find_data("landmark_h6.csv"))
FIG <- if (dir.exists("figure")) "figure" else { dir.create("figure"); "figure" }

lm6 <- read.csv(find_data("landmark_h6.csv"))
cat(sprintf("Loaded landmark_h6: %d stays, onset-within-12h rate %.3f\n",
            nrow(lm6), mean(lm6$onset_within_h)))

# ---- Feature design ---------------------------------------------------------
# Vitals (near-complete after forward-fill at h6): use directly.
vitals <- c("hr","resp_rate","map","spo2","temp_c","gcs")
# Scores allowed now (nomogram is a full-feature model, not the non-circular one).
scores <- c("sofa_total","qsofa","sirs")
# Labs: 70-88% missing at h6 and the missingness is INFORMATIVE (a drawn lactate
# marks a sicker/suspected patient). Median-impute + a "_msg" measured indicator.
labs   <- c("lactate","creatinine","wbc","pf_ratio")
# 6h trajectory slopes: ~30% missing (fewer than 2 measurements). Impute 0
# (no trend) + a "_msg" indicator.
slopes <- c("hr_slope6","resp_rate_slope6","map_slope6","spo2_slope6")

df <- data.frame(row.names = seq_len(nrow(lm6)))
for (v in c(vitals, scores)) {                       # simple median-impute
  x <- lm6[[v]]; x[is.na(x)] <- median(x, na.rm = TRUE); df[[v]] <- x
}
for (v in labs) {                                    # impute + informative flag
  x <- lm6[[v]]; df[[paste0(v, "_msg")]] <- as.integer(is.na(x))
  x[is.na(x)] <- median(x, na.rm = TRUE); df[[v]] <- x
}
for (v in slopes) {                                  # impute 0 + flag
  x <- lm6[[v]]; df[[paste0(v, "_msg")]] <- as.integer(is.na(x))
  x[is.na(x)] <- 0; df[[v]] <- x
}
df$age    <- lm6$age
df$female <- as.integer(lm6$gender == "F")
y <- lm6$onset_within_h
X <- as.matrix(df)
cat(sprintf("Design matrix: %d features\n", ncol(X)))

# ---- Outer 5-fold CV with inner lambda selection ---------------------------
folds <- sample(rep(1:5, length.out = nrow(X)))
oos_en <- numeric(nrow(X))                           # elastic-net OOS risk
ALPHA  <- 0.5                                         # elastic net (LASSO-ish)
for (k in 1:5) {
  tr <- folds != k
  cvfit <- cv.glmnet(X[tr, ], y[tr], family = "binomial",
                     alpha = ALPHA, nfolds = 5, standardize = TRUE)
  oos_en[!tr] <- as.numeric(predict(cvfit, X[!tr, ],
                                    s = "lambda.min", type = "response"))
}

# ---- Reconstruct the Phase-1 models on the SAME outer folds (for DeLong) ----
# Fit on the imputed matrix `df` so all three models use identical rows (the raw
# lm6 vitals carry a little missingness that would leave NA predictions).
gdat <- cbind(df, y = y)
cvauc_glm <- function(form, data) {
  p <- numeric(nrow(data))
  for (k in 1:5) { tr <- folds != k
    m <- glm(form, data[tr, ], family = binomial)
    p[!tr] <- predict(m, data[!tr, ], type = "response") }
  p
}
p_static <- cvauc_glm(y ~ age + sofa_total + qsofa + sirs +
                        hr + resp_rate + map + spo2 + temp_c, gdat)
p_traj   <- cvauc_glm(y ~ age + sofa_total + qsofa + sirs +
                        hr + resp_rate + map + spo2 + temp_c +
                        hr_slope6 + resp_rate_slope6 + map_slope6 + spo2_slope6,
                      gdat)

# ---- Metrics ----------------------------------------------------------------
auc_of <- function(p) as.numeric(auc(roc(y, p, quiet = TRUE, direction = "<")))
prauc_of <- function(p) pr.curve(scores.class0 = p[y==1],
                                 scores.class1 = p[y==0])$auc.integral
brier <- function(p) mean((p - y)^2)

roc_en  <- roc(y, oos_en,   quiet = TRUE, direction = "<")
roc_trj <- roc(y, p_traj,   quiet = TRUE, direction = "<")
dl_vs_traj   <- roc.test(roc_en, roc_trj, method = "delong")$p.value

metrics <- data.frame(
  model = c("Phase1 static (glm)", "Phase1 + slopes (glm, the 0.755)",
            "Tier1 full-feature elastic net"),
  auroc = c(auc_of(p_static), auc_of(p_traj), auc_of(oos_en)),
  prauc = c(prauc_of(p_static), prauc_of(p_traj), prauc_of(oos_en)),
  brier = c(brier(p_static), brier(p_traj), brier(oos_en)))
metrics$delong_p_vs_phase1slopes <- c(NA, NA, dl_vs_traj)
metrics[ ,-1] <- round(metrics[ ,-1], 4)
print(metrics, row.names = FALSE)
write.csv(metrics, file.path(OUT, "phase2_tier1_metrics.csv"), row.names = FALSE)

# ---- Final model on all data (coefficients / odds ratios) -------------------
cvfull <- cv.glmnet(X, y, family = "binomial", alpha = ALPHA,
                    nfolds = 5, standardize = TRUE)
co <- as.matrix(coef(cvfull, s = "lambda.min"))
coefs <- data.frame(term = rownames(co), coef = as.numeric(co))
coefs$odds_ratio <- exp(coefs$coef)
coefs <- coefs[coefs$coef != 0, ]
coefs[ ,c("coef","odds_ratio")] <- round(coefs[ ,c("coef","odds_ratio")], 4)
write.csv(coefs, file.path(OUT, "phase2_tier1_coefs.csv"), row.names = FALSE)
cat(sprintf("\nSelected features (non-zero at lambda.min): %d / %d\n",
            nrow(coefs) - 1, ncol(X)))

# ---- Out-of-sample risk export (feeds Tier 4 alarm/utility analysis) --------
write.csv(data.frame(stay_id = lm6$stay_id, onset_within_h = y,
                     risk_en = oos_en, risk_phase1slopes = p_traj),
          file.path(OUT, "phase2_tier1_oos_pred.csv"), row.names = FALSE)

# ---- Calibration curve ------------------------------------------------------
png(file.path(FIG, "calibration_h6.png"), width = 1000, height = 1000, res = 200)
bins <- cut(oos_en, quantile(oos_en, seq(0, 1, 0.1)), include.lowest = TRUE)
cal <- aggregate(cbind(pred = oos_en, obs = y), list(bin = bins), mean)
plot(cal$pred, cal$obs, pch = 19, xlab = "Predicted risk",
     ylab = "Observed onset rate", main = "Calibration (out-of-sample, h6)",
     xlim = range(cal$pred, cal$obs), ylim = range(cal$pred, cal$obs))
abline(0, 1, lty = 2, col = "grey50"); lines(cal$pred, cal$obs, col = "steelblue")
dev.off()

# ---- Nomogram (post-selection lrm on selected features) --------------------
sel <- setdiff(coefs$term, "(Intercept)")
nomo_df <- df[, intersect(sel, names(df)), drop = FALSE]; nomo_df$y <- y
dd <- datadist(nomo_df); options(datadist = "dd")
frm <- as.formula(paste("y ~", paste(names(nomo_df)[names(nomo_df) != "y"],
                                     collapse = " + ")))
fit_lrm <- lrm(frm, data = nomo_df, maxit = 1000)
png(file.path(FIG, "nomogram_h6.png"), width = 1800, height = 1400, res = 180)
plot(nomogram(fit_lrm, fun = plogis, funlabel = "Risk of sepsis within 12h"),
     cex.axis = 0.6, cex.var = 0.7)
dev.off()

cat("\nTier 1 complete. Outputs in", OUT, "and", FIG, "\n")
