"""Scoring engine: supports both Tier-1 (static) and Tier-2 (supermodel) models."""

import math


def compute_risk_score(
    feature_vector: dict,
    model_config: dict,
    hours_since_admission: float = 0.0,
) -> float:
    """Compute sepsis risk probability from the feature vector.

    For Tier-2 supermodels, the score adapts with ICU stay duration
    via time-interaction terms.
    """
    intercept = model_config["intercept"]

    if "base_coefficients" in model_config:
        return _score_tier2(feature_vector, model_config, hours_since_admission)

    return _score_tier1(feature_vector, model_config)


def _score_tier1(feature_vector: dict, model_config: dict) -> float:
    logit = model_config["intercept"]
    for name, coef in model_config["coefficients"].items():
        logit += coef * feature_vector.get(name, 0.0)
    return _sigmoid(logit)


def _score_tier2(
    feature_vector: dict,
    model_config: dict,
    hours_since_admission: float,
) -> float:
    logit = model_config["intercept"]

    for name, coef in model_config["base_coefficients"].items():
        logit += coef * feature_vector.get(name, 0.0)

    mean_s = model_config["mean_s"]
    sd_s = model_config["sd_s"]
    s_z = (hours_since_admission - mean_s) / sd_s

    time_coefs = model_config.get("time_coefficients", {})
    logit += time_coefs.get("s", 0.0) * s_z
    logit += time_coefs.get("s2", 0.0) * s_z * s_z

    for name, coef in model_config.get("interaction_coefficients", {}).items():
        if coef != 0.0:
            logit += coef * feature_vector.get(name, 0.0) * s_z

    return _sigmoid(logit)


def _sigmoid(x: float) -> float:
    if x > 500:
        return 1.0
    if x < -500:
        return 0.0
    return 1.0 / (1.0 + math.exp(-x))


def is_sepsis_risk(risk_score: float, model_config: dict, threshold: str = "youden") -> bool:
    threshold_key = f"threshold_{threshold}"
    threshold_value = model_config.get(threshold_key, model_config.get("threshold_youden", 0.05))
    return risk_score >= threshold_value
