#!/usr/bin/env Rscript
# =============================================================================
# 13_repeated_measures.R  --  PHASE 2, TIER 3
# Correct-for-correlation inferential models on the hourly panel.
#
# plan.md §3B.4 flags that Phase 1 never modelled the WITHIN-PATIENT correlation
# of repeated hourly measurements. Here we do it two classical ways:
#   (1) GLMM  -- logistic with a random intercept per patient (lme4::glmer),
#       giving the between-patient variance, the ICC, and cluster-robust
#       fixed-effect odds ratios; contrasted with a naive pooled GLM that
#       (wrongly) treats the 100k+ hours as independent.
#   (2) Penalized (ridge) time-varying-covariate Cox on a counting-process
#       build of the same sampled stays -- the hazard of onset from physiology
#       as it evolves, stabilised by an L2 penalty.
#
# Runs on the sampled long panel (2,500 stays) for tractability, matching how
# Phase 1's report handled the time-varying models.
# Output: phase2_tier3_glmm.csv, phase2_tier3_tvcox.csv
# Seed 486649. Run from projects/sepsis_mimic4/.
# =============================================================================

suppressPackageStartupMessages({ library(geepack); library(sandwich); library(survival) })
set.seed(486649)

find_data <- function(f) {
  cands <- c(file.path("../../processed_data", f),
             file.path("processed_data", f), f)
  hit <- cands[file.exists(cands)][1]
  if (is.na(hit)) stop("cannot find ", f); hit
}
OUT <- dirname(find_data("panel_sample_long.csv"))
d0 <- read.csv(find_data("panel_sample_long.csv"))   # full copy (for the Cox)
d <- d0

# ---- DYNAMIC incident outcome on AT-RISK hours ------------------------------
# The stored per-hour `label` is patient-near-constant (all-0 for non-septic;
# 1 from onset-6h onward for septic) -> a random intercept would trivially
# separate it (complete separation). Instead we model the proper early-warning
# target on at-risk hours only: y = onset occurs within the next 12h.
#   at-risk hour = non-septic (any hour) OR septic with hour < onset_hour
# This varies WITHIN a septic patient (0 early, 1 as onset nears) and is the
# correct repeated-measures outcome.
HORIZON <- 12
d <- d[is.na(d$onset_hour) | d$hour < d$onset_hour, ]
d$y <- as.integer(!is.na(d$onset_hour) &
                    (d$onset_hour - d$hour) <= HORIZON &
                    (d$onset_hour - d$hour) > 0)
cat(sprintf("Loaded sampled panel (at-risk hours): %d stay-hours, %d stays, incident-within-12h rate %.3f\n",
            nrow(d), length(unique(d$stay_id)), mean(d$y)))

# ---- standardize predictors (median-impute; z-score for comparable ORs) -----
zt <- function(x) { x[is.na(x)] <- median(x, na.rm=TRUE); as.numeric(scale(x)) }
d$z_hr   <- zt(d$hr);   d$z_map  <- zt(d$map);   d$z_rr <- zt(d$resp_rate)
d$z_temp <- zt(d$temp_c); d$z_lac <- zt(d$lactate); d$z_hour <- zt(d$hour)
preds <- c("z_hr","z_map","z_rr","z_temp","z_lac","z_hour")
form  <- as.formula(paste("y ~", paste(preds, collapse=" + ")))

# ---- (1) population-averaged GEE vs naive pooled GLM ------------------------
# A per-patient random-intercept GLMM is DEGENERATE for this outcome: most
# patients never have an event, so their intercepts diverge (quasi-complete
# separation) and the variance component explodes. GEE is the correct classical
# alternative -- it models the population-averaged effect with an exchangeable
# WITHIN-PATIENT working correlation and cluster-robust ("sandwich") SEs, with
# no per-cluster parameters to blow up. Contrast with a naive GLM that treats
# the 76k hours as independent and so reports far-too-small SEs.
d <- d[order(d$stay_id, d$hour), ]
g_pool <- glm(form, data=d, family=binomial)

# (a) same GLM coefficients, but NAIVE (model-based) vs CLUSTER-ROBUST SEs.
# This isolates the effect of within-patient clustering on inference, holding
# the estimator fixed: treating 76k correlated hours as independent understates
# the SEs; the sandwich SE clustered by patient is the honest one.
se_naive  <- sqrt(diag(vcov(g_pool)))
se_robust <- sqrt(diag(vcovCL(g_pool, cluster = d$stay_id, type = "HC0")))
# (b) GEE gives the interpretable within-patient working correlation.
cat("fitting GEE (exchangeable within-patient correlation) ...\n")
g_gee <- geeglm(form, id=stay_id, data=d, family=binomial, corstr="exchangeable")
alpha <- summary(g_gee)$corr[["Estimate"]]
cat(sprintf("exchangeable within-patient correlation alpha = %.3f\n", alpha))

nm <- names(coef(g_pool))
comp <- data.frame(
  term            = nm,
  OR_glm          = round(exp(coef(g_pool)), 3),
  SE_naive        = round(se_naive[nm], 3),
  SE_cluster_robust = round(se_robust[nm], 3))
comp$SE_inflation <- round(comp$SE_cluster_robust / comp$SE_naive, 2)
rownames(comp) <- NULL
cat(sprintf("\nCluster-robust vs naive SEs on the pooled GLM (within-patient alpha=%.3f):\n", alpha))
print(comp, row.names=FALSE)
write.csv(rbind(comp,
                data.frame(term="__alpha_within_patient__", OR_glm=round(alpha,4),
                           SE_naive=NA, SE_cluster_robust=NA, SE_inflation=NA)),
          file.path(OUT, "phase2_tier3_glmm.csv"), row.names=FALSE)

# ---- (2) penalized time-varying-covariate Cox (counting process) ------------
# Build (start, stop, event] intervals per stay-hour; event at the onset hour.
# Uses the FULL sampled panel d0 (not the pre-onset-only GLMM frame).
cat("\nbuilding counting-process time-varying Cox (ridge) ...\n")
dc <- d0[order(d0$stay_id, d0$hour), ]
dc$z_hr <- zt(dc$hr); dc$z_map <- zt(dc$map); dc$z_rr <- zt(dc$resp_rate)
dc$z_temp <- zt(dc$temp_c); dc$z_lac <- zt(dc$lactate)
dc$start <- dc$hour
dc$stop  <- dc$hour + 1
# event = 1 at the onset hour of a septic stay, else 0
dc$ev <- as.integer(!is.na(dc$onset_hour) & dc$hour == dc$onset_hour)
# keep intervals up to and including onset (drop post-onset hours)
dc <- dc[is.na(dc$onset_hour) | dc$hour <= dc$onset_hour, ]
tv <- coxph(Surv(start, stop, ev) ~
              ridge(z_hr, z_map, z_rr, z_temp, z_lac, theta=1) + cluster(stay_id),
            data=dc)
cox_tab <- data.frame(
  term = c("z_hr","z_map","z_rr","z_temp","z_lac"),
  HR   = round(exp(coef(tv)), 3))
cat("\nTime-varying Cox (ridge) hazard ratios for incident onset:\n")
print(cox_tab, row.names=FALSE)
write.csv(cox_tab, file.path(OUT, "phase2_tier3_tvcox.csv"), row.names=FALSE)
cat("\nTier 3 complete.\n")
