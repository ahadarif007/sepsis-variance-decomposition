# SepsisNet: Real-Time ICU Sepsis Prediction System

**System Design Document**

> A deployable, database-backed clinical decision support system for real-time Sepsis-3 onset prediction, built on validated statistical models from a MIMIC-IV research pipeline.

| | |
|---|---|
| **Version** | 1.0 |
| **Date** | July 2026 |
| **Status** | Design |
| **Origin** | `sepsis_mimic4/` research pipeline |

---

## Table of Contents

1. [Goals & Constraints](#1-goals--constraints)
2. [System Architecture](#2-system-architecture)
3. [Data Ingestion Layer](#3-data-ingestion-layer)
4. [Temporal Data Store](#4-temporal-data-store)
5. [Feature Engine](#5-feature-engine)
6. [Scoring Engine](#6-scoring-engine)
7. [Alert & Webhook Layer](#7-alert--webhook-layer)
8. [API Surface](#8-api-surface)
9. [Database Schema](#9-database-schema)
10. [Deployment & Configuration](#10-deployment--configuration)
11. [Migration from Research Codebase](#11-migration-from-research-codebase)
12. [Monitoring & Drift Detection](#12-monitoring--drift-detection)
13. [Implementation Roadmap](#13-implementation-roadmap)

---

## 1. Goals & Constraints

### Primary goal

Predict incident Sepsis-3 onset **up to 12 hours before clinical recognition**, using only routinely collected ICU vitals, labs, and vasopressor data — and deliver that prediction as a real-time alert to any endpoint via webhook.

### Design principles

- **Deployable by anyone.** A single Docker Compose file brings up the full stack. No proprietary EHR integrations required — the system accepts data through a standard REST API.
- **Model-agnostic scoring.** The scoring engine loads model coefficients from a config file. Swap in a new model (retrained on local data, upgraded architecture) by changing one JSON file — no code changes.
- **Hospital-agnostic features.** Every feature is computable from HR, MAP, RR, SpO2, Temp, GCS, six labs (lactate, creatinine, WBC, platelets, bilirubin, PaO2), urine output, and vasopressor status. No EHR-specific fields.
- **Self-contained temporal buffer.** The system maintains its own per-patient time-series store. EHR integration only needs to push new observations forward — never re-send history.
- **Clinically validated baseline.** Ships with frozen Tier-2 dynamic landmark supermodel coefficients (pooled OOS AUROC 0.789 on MIMIC-IV) as the default model. The supermodel's time-interaction terms adapt predictions as the ICU stay progresses. Institutions recalibrate on local data.

### Non-goals (v1)

- Deep learning models (LSTM, Transformer) — deferred to v2
- Closed-loop treatment recommendations
- Direct HL7/FHIR parsing (handled by adapter layer outside this system)
- Regulatory submission (intended for research and clinical pilot use)

---

## 2. System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      EXTERNAL SOURCES                          │
│  ┌──────────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │ EHR / Bedside    │  │ Manual Entry │  │ Lab System       │  │
│  │ Monitor          │  │ (Nurse Stn)  │  │ (LIS interface)  │  │
│  │ HL7 · FHIR · CSV │  │              │  │                  │  │
│  └────────┬─────────┘  └──────┬───────┘  └────────┬─────────┘  │
└───────────┼────────────────────┼───────────────────┼────────────┘
            ▼                    ▼                   ▼
┌─────────────────────────────────────────────────────────────────┐
│                       INGESTION LAYER                          │
│  ┌────────────────────────────────────┐  ┌──────────────────┐  │
│  │ REST API Gateway                   │  │ Batch Loader     │  │
│  │ POST /api/v1/observations          │  │ CSV / Parquet    │  │
│  └────────────────┬───────────────────┘  └────────┬─────────┘  │
└───────────────────┼───────────────────────────────┼─────────────┘
                    ▼                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                        STORAGE LAYER                           │
│  ┌────────────────────────────────────┐  ┌──────────────────┐  │
│  │ Temporal Data Store                │  │ Patient Registry │  │
│  │ PostgreSQL + TimescaleDB           │  │ Active ICU stays │  │
│  └────────────────┬───────────────────┘  └──────────────────┘  │
└───────────────────┼─────────────────────────────────────────────┘
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                       COMPUTE LAYER                            │
│  ┌──────────────────┐  ┌────────────────┐  ┌────────────────┐  │
│  │ Feature Engine   │  │ Scoring Engine │  │ SOFA           │  │
│  │ Rolling windows  │  │ Model coefs    │  │ Calculator     │  │
│  │ LOCF · Slopes    │  │ Threshold      │  │ 6 organ scores │  │
│  └──────────────────┘  └────────────────┘  └────────────────┘  │
└───────────────────┬─────────────────────────────────────────────┘
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                        OUTPUT LAYER                            │
│  ┌──────────────────┐  ┌────────────────┐  ┌────────────────┐  │
│  │ Webhook          │  │ Dashboard API  │  │ Audit Log      │  │
│  │ Dispatcher       │  │ Risk timeline  │  │ Every score    │  │
│  │ Config endpoints │  │ Feature attrib │  │ persisted      │  │
│  └──────────────────┘  └────────────────┘  └────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Core loop

Every time new data arrives for a patient — a vitals reading, a lab result, a vasopressor order — the system executes one cycle:

1. **Ingest** — validate and persist the observation to the temporal store
2. **Buffer** — the store now holds the full history; no re-fetch needed
3. **Feature** — query the patient's last 9 hours, compute the landmark feature vector
4. **Score** — apply model coefficients, produce a risk probability
5. **Decide** — compare against threshold; if crossed, fire webhook
6. **Log** — persist the score, features, and decision to the audit table

> **Design choice:** The system is **event-driven, not polled**. Scoring triggers on each new observation rather than on a fixed interval. This matches clinical reality: new vitals arrive every ~5 minutes, labs arrive sporadically. The effective scoring rate is governed by the data flow, not an arbitrary timer.

---

## 3. Data Ingestion Layer

### Observation format

The system accepts observations through a single normalized schema. The adapter layer at each hospital maps its native format (HL7 messages, FHIR resources, CSV feeds) into this common shape before hitting the API:

```json
{
  "patient_id": "P-00482",
  "stay_id": "S-10294",
  "timestamp": "2026-07-10T14:32:00Z",
  "parameter": "heart_rate",
  "value": 112.0,
  "unit": "bpm",
  "source": "bedside_monitor"
}
```

### Accepted parameters

| Category | Parameters | Expected units |
|---|---|---|
| **Vitals** | `heart_rate`, `sbp`, `dbp`, `map`, `resp_rate`, `spo2`, `temp_c`, `gcs_total` | bpm, mmHg, mmHg, mmHg, /min, %, °C, 3–15 |
| **Labs** | `lactate`, `creatinine`, `wbc`, `platelets`, `bilirubin`, `pao2`, `fio2`, `pf_ratio` | mmol/L, mg/dL, K/uL, K/uL, mg/dL, mmHg, fraction, ratio |
| **Vasopressors** | `norepinephrine`, `epinephrine`, `dopamine`, `dobutamine`, `vasopressin`, `phenylephrine` | mcg/kg/min (vasopressin: units/min) |
| **Output** | `urine_output` | mL |

### Unit normalization

The ingestion layer applies the same conversions as the research pipeline:

- Temperature in Fahrenheit → Celsius: `(F − 32) × 5/9`
- FiO2 as percentage → fraction: `value / 100`, clamped to [0.21, 1.0]
- MAP clipped to [10, 250] mmHg
- GCS clipped to [3, 15]

### Batch loading

For retrospective analysis or system testing, a batch loader accepts CSV or Parquet files matching the research pipeline's output format (`hourly_panel.parquet`). This enables deployers to validate the system against their historical data before going live.

---

## 4. Temporal Data Store

### Why a dedicated store

The scoring engine needs the last 9 hours of data for every active patient on every scoring cycle. Querying the EHR for this on each new observation is impractical — EHR APIs are slow, rate-limited, and not designed for high-frequency analytical queries. The system maintains its own time-series buffer.

### Technology choice: PostgreSQL + TimescaleDB

TimescaleDB is a PostgreSQL extension purpose-built for time-series data. It provides automatic time-based partitioning (hypertables), fast window queries, and continuous aggregates — while remaining fully SQL-compatible. This means:

- No new query language to learn. Standard SQL for all analytics.
- Automatic chunk management. Data older than 96 hours is compressed; data older than 30 days is dropped (configurable).
- The patient registry, audit log, and config tables live in the same PostgreSQL instance — one database to manage.

### Data lifecycle

| Phase | Retention | Storage |
|---|---|---|
| Hot (active ICU stay) | Full stay duration | Uncompressed hypertable |
| Warm (post-discharge) | 30 days | Compressed chunks |
| Cold (archive) | Configurable | Exported Parquet → object storage |

> **Capacity planning:** A 20-bed ICU with vitals every 5 min generates ~5,760 rows/day per variable × 8 vitals = ~46K rows/day. With 16 parameters total, ~92K rows/day. A 100-bed unit: ~460K rows/day. TimescaleDB handles this comfortably on a single node. The bottleneck will be network, not storage.

---

## 5. Feature Engine

The feature engine translates raw time-series observations into the exact feature vector the model expects. This is the most critical piece to get right — it must reproduce the research pipeline's feature definitions exactly, or the model's calibration is invalidated.

### Feature computation pipeline

Given a patient at current hour `h` (hours since ICU admission):

#### Step 1 — Forward fill

For each parameter, carry the last observed value forward (LOCF). This matches the `_ff` columns in the research pipeline's `hourly_panel.parquet`. If a parameter has never been measured, it remains null.

#### Step 2 — Time-since-last-measured

For each parameter, compute hours since the most recent observation. This is both a data quality signal and a clinical signal — a lactate drawn at hour 3 that hasn't been repeated by hour 12 means the clinician didn't feel the need to recheck.

#### Step 3 — Informative missingness flags

Binary indicators: was this lab *ever drawn* during the stay? These are among the strongest predictors in the trained model — a drawn lactate signals clinical suspicion of sepsis.

> **From the research:** The Tier-2 supermodel's top predictors by coefficient magnitude are `pf_ratio_msg` (PF ratio not measured: coef +0.716), `hr_slope6_msg` (HR slope not computable: +0.413), `creatinine_msg` (creatinine not measured: +0.312), and `wbc_msg` (WBC not drawn: +0.300). The actual lab *values* rank lower. This is the informative missingness phenomenon — the act of *not* ordering a test carries clinical information. Note: `_msg = 1` means the value was NOT measured.

#### Step 4 — Trajectory slopes

For heart rate, respiratory rate, MAP, and SpO2: compute `value@h − value@(h−6)`. This 6-hour slope captures acute deterioration. If either endpoint is missing, the slope is zero and the corresponding `_msg` flag is set to 0.

#### Step 5 — Clinical scores

- **SOFA** — six organ sub-scores computed from the forward-filled values, using the exact threshold functions from `05_sofa_sepsis3.py`
- **qSOFA** — RR ≥ 22, GCS < 15, MAP < 70 (sum of 0–3)
- **SIRS** — HR > 90, RR > 20, temp outside [36, 38]°C, WBC outside [4, 12] K/uL (sum of 0–4)

#### Step 6 — Assemble feature vector

The final vector for the Tier-1 model contains 26 features:

| Group | Features | Count |
|---|---|---|
| **Vitals (FF)** | hr, resp_rate, map, spo2, temp_c, gcs | 6 |
| **Scores** | sofa_total, qsofa, sirs | 3 |
| **Labs + miss.** | lactate, creatinine, wbc, pf_ratio + 4 × _msg flags | 8 |
| **Slopes + miss.** | hr_slope6, resp_rate_slope6, map_slope6, spo2_slope6 + 4 × _msg | 8 |
| **Demographics** | age, female | 2 |

### Imputation

Matches the research pipeline exactly. Vitals and scores receive population-median imputation (medians shipped in the model config). Labs receive median imputation plus the binary missingness flag. Slopes receive zero imputation plus flag. These medians are frozen from the training set — they ship with the model coefficients.

---

## 6. Scoring Engine

### Model representation

The trained model ships as a single JSON config file. No framework dependencies — the scoring engine is pure arithmetic. The default model is the **Tier-2 dynamic landmark supermodel**, which includes time-interaction terms that adapt predictions as the ICU stay progresses:

```json
{
  "model_name": "tier2_supermodel_v1",
  "model_type": "dynamic_landmark_supermodel",
  "trained_on": "MIMIC-IV v3.1",
  "training_rows": 207010,
  "training_stays": 48829,
  "landmark_hours": [6, 12, 18, 24, 36, 48],
  "prediction_horizon_hours": 12,
  "auroc_oos_pooled": 0.7885,

  "mean_s": 19.3021,
  "sd_s": 12.4553,
  "intercept": -11.664482,

  "base_coefficients": {
    "hr": 0.012175, "resp_rate": 0.005355, "map": -0.006462,
    "spo2": 0.0, "temp_c": 0.193193, "gcs": -0.039354,
    "sofa_total": -0.190582, "qsofa": 0.141342, "sirs": 0.193756,
    "lactate_msg": -0.095802, "lactate": 0.0,
    "creatinine_msg": 0.311682, "creatinine": -0.007998,
    "wbc_msg": 0.300263, "wbc": 0.00486,
    "pf_ratio_msg": 0.716262, "pf_ratio": -0.001856,
    "hr_slope6_msg": 0.413497, "hr_slope6": 0.0,
    "resp_rate_slope6_msg": 0.0, "resp_rate_slope6": -0.013831,
    "map_slope6_msg": 0.075235, "map_slope6": 0.002789,
    "spo2_slope6_msg": 0.0, "spo2_slope6": 0.014611,
    "age": 0.009976, "female": -0.258669
  },

  "time_coefficients": { "s": 0.0, "s2": 0.0 },

  "interaction_coefficients": {
    "resp_rate": -0.023906, "map": 0.006228, "gcs": -0.046567,
    "sofa_total": 0.126765, "lactate": -0.00712,
    "wbc_msg": -0.145052, "pf_ratio_msg": -0.195556,
    "hr_slope6": 0.006561, "resp_rate_slope6": 0.012704,
    "spo2_slope6_msg": 0.047933
  },

  "imputation_medians": {
    "hr": 81, "resp_rate": 18, "map": 78, "spo2": 97,
    "temp_c": 36.83, "gcs": 15, "sofa_total": 1,
    "qsofa": 1, "sirs": 1, "lactate": 1.6,
    "creatinine": 0.9, "wbc": 10.4, "pf_ratio": 407
  },

  "threshold_youden": 0.036904,
  "threshold_high_sensitivity": 0.011993,
  "threshold_high_specificity": 0.067259,
  "missingness_convention": "1 = value NOT measured (missing), 0 = value measured"
}
```

### Scoring function

The Tier-2 supermodel scoring is still pure arithmetic — no ML framework needed:

```python
def score(features: dict, model: dict, hours_since_admission: float) -> float:
    logit = model["intercept"]

    # Base coefficients
    for name, coef in model["base_coefficients"].items():
        logit += coef * features[name]

    # Standardized landmark time
    s_z = (hours_since_admission - model["mean_s"]) / model["sd_s"]
    logit += model["time_coefficients"]["s"] * s_z
    logit += model["time_coefficients"]["s2"] * s_z ** 2

    # Feature × time interactions
    for name, coef in model["interaction_coefficients"].items():
        logit += coef * features[name] * s_z

    return 1 / (1 + exp(-logit))
```

The key insight: `sofa_total` has a **negative** base coefficient (-0.191) because the model predicts *incident* onset — patients with already-high SOFA are past the prediction window. But the positive interaction term (+0.127) means SOFA becomes more predictive later in the stay, which is clinically meaningful.

### Threshold strategy

The system ships three operating points derived from the Tier-2 supermodel's OOS evaluation:

| Threshold | Name | Use case |
|---|---|---|
| `0.012` | High sensitivity | Screening — catches most developing cases |
| `0.037` | Youden optimal | Balanced — recommended default |
| `0.067` | High specificity | Confirmation — fewer false alarms |

Deployers choose their operating point via the `SEPSISNET_SCORING_THRESHOLD` env var.

---

## 7. Alert & Webhook Layer

### Webhook dispatch

When the risk score crosses the configured threshold *and* the patient is not already in an active alert state, the system fires a webhook:

```json
POST {configured_webhook_url}
Content-Type: application/json

{
  "event": "sepsis_risk_alert",
  "severity": "high",
  "patient_id": "P-00482",
  "stay_id": "S-10294",
  "timestamp": "2026-07-10T14:35:00Z",
  "risk_score": 0.134,
  "threshold_used": 0.082,
  "hours_since_admission": 14.5,
  "top_contributors": [
    {"feature": "lactate_msg", "contribution": 0.41},
    {"feature": "hr_slope6", "contribution": 0.18},
    {"feature": "sofa_total", "contribution": 0.12}
  ],
  "sofa_current": 4,
  "sofa_delta_6h": 2,
  "vitals_snapshot": {
    "hr": 112, "map": 62, "resp_rate": 28,
    "spo2": 93, "temp_c": 38.6, "gcs": 14
  }
}
```

### Alert state machine

To prevent alarm fatigue (the Tier-4 evaluation measured 6.5 false alarms per patient-day at 90% sensitivity), the alert layer implements a state machine per patient:

- **MONITORING** — default state. Scores are computed but no alert is active.
- **ALERTED** — threshold crossed. Webhook fired. No repeat webhook for this patient until the score drops below threshold for a configurable cooldown period (default: 2 hours).
- **ESCALATED** — score has stayed above threshold for > N hours, or crossed the high-specificity threshold. Second webhook with elevated severity.
- **RESOLVED** — score dropped below threshold for the cooldown period. State returns to MONITORING.

### Webhook targets

The system is agnostic to what receives the webhook. Common integrations:

- **Nurse dashboard** — a web UI that displays active alerts (built separately)
- **Slack / Teams** — via incoming webhook URL
- **PagerDuty / Opsgenie** — for on-call escalation
- **EHR alert inbox** — if the EHR supports inbound webhooks
- **Custom endpoint** — any HTTP POST receiver

Multiple webhook targets can be configured, each with its own threshold level. This enables the stepped alerting pattern: Slack at high-sensitivity, PagerDuty at Youden.

---

## 8. API Surface

### Data ingestion

**`POST /api/v1/observations`**
Submit a single observation. Triggers scoring cycle for the patient.

**`POST /api/v1/observations/batch`**
Submit multiple observations in one request (up to 1000). Triggers one scoring cycle per affected patient after all rows are ingested.

### Patient management

**`POST /api/v1/stays`**
Register a new ICU stay. Body: `{"patient_id", "stay_id", "admission_time", "age", "sex"}`. This starts the prediction clock.

**`POST /api/v1/stays/{stay_id}/discharge`**
Mark a stay as discharged. Scoring stops; data enters warm retention.

**`GET /api/v1/stays/active`**
List all active ICU stays with latest risk score and alert state.

### Risk queries

**`GET /api/v1/stays/{stay_id}/risk`**
Current risk score, feature vector, SOFA breakdown, and alert state for one patient.

**`GET /api/v1/stays/{stay_id}/risk/timeline`**
Hourly risk score history for the entire stay. Powers the trend chart on a dashboard.

### Configuration

**`GET /api/v1/config/model`**
Returns the active model config (coefficients, thresholds, imputation medians).

**`POST /api/v1/config/webhooks`**
Register or update webhook endpoints and their threshold levels.

---

## 9. Database Schema

```sql
-- Core time-series table (TimescaleDB hypertable)
CREATE TABLE observations (
    time         TIMESTAMPTZ      NOT NULL,
    stay_id      TEXT             NOT NULL,
    parameter    TEXT             NOT NULL,
    value        DOUBLE PRECISION NOT NULL,
    source       TEXT
);
SELECT create_hypertable('observations', 'time');
CREATE INDEX idx_obs_stay_time ON observations (stay_id, time DESC);
CREATE INDEX idx_obs_stay_param ON observations (stay_id, parameter, time DESC);

-- Patient registry
CREATE TABLE stays (
    stay_id          TEXT PRIMARY KEY,
    patient_id       TEXT NOT NULL,
    admission_time   TIMESTAMPTZ NOT NULL,
    discharge_time   TIMESTAMPTZ,
    age              SMALLINT NOT NULL,
    sex              CHAR(1) NOT NULL,
    is_active        BOOLEAN DEFAULT TRUE,
    created_at       TIMESTAMPTZ DEFAULT NOW()
);

-- Score audit trail
CREATE TABLE scores (
    id               BIGSERIAL PRIMARY KEY,
    stay_id          TEXT NOT NULL REFERENCES stays(stay_id),
    scored_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    hours_since_adm  REAL NOT NULL,
    risk_score       REAL NOT NULL,
    sofa_total       SMALLINT,
    alert_state      TEXT DEFAULT 'MONITORING',
    feature_vector   JSONB NOT NULL,
    model_version    TEXT NOT NULL
);
CREATE INDEX idx_scores_stay ON scores (stay_id, scored_at DESC);

-- Webhook configuration
CREATE TABLE webhooks (
    id               SERIAL PRIMARY KEY,
    url              TEXT NOT NULL,
    threshold_level  TEXT NOT NULL DEFAULT 'youden',
    threshold_value  REAL NOT NULL,
    is_active        BOOLEAN DEFAULT TRUE,
    headers          JSONB DEFAULT '{}'
);

-- Alert state
CREATE TABLE alerts (
    id               BIGSERIAL PRIMARY KEY,
    stay_id          TEXT NOT NULL REFERENCES stays(stay_id),
    state            TEXT NOT NULL DEFAULT 'MONITORING',
    alerted_at       TIMESTAMPTZ,
    resolved_at      TIMESTAMPTZ,
    peak_score       REAL,
    webhook_sent     BOOLEAN DEFAULT FALSE
);
```

> **Query pattern:** The feature engine's primary query — "get all observations for patient X in the last 9 hours" — is a **narrow, indexed, time-bounded scan**. With the `(stay_id, time DESC)` index, this returns in under 5ms even with millions of rows in the table. TimescaleDB's chunk exclusion means it only touches the relevant time partition.

---

## 10. Deployment & Configuration

### Docker Compose stack

The entire system runs as three containers:

```yaml
services:
  db:
    image: timescale/timescaledb:latest-pg16
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./schema.sql:/docker-entrypoint-initdb.d/01-schema.sql
    environment:
      POSTGRES_DB: sepsisnet
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    ports:
      - "5432:5432"

  api:
    build: ./services/api
    depends_on: [db]
    environment:
      DATABASE_URL: postgresql://postgres:${DB_PASSWORD}@db:5432/sepsisnet
      SEPSISNET_MODEL_CONFIG_PATH: /app/models/tier2_supermodel_v1.json
      SCORING_MIN_HOURS: 6
      ALERT_COOLDOWN_HOURS: 2
    ports:
      - "8000:8000"
    volumes:
      - ./models:/app/models

  worker:
    build: ./services/worker
    depends_on: [db]
    environment:
      DATABASE_URL: postgresql://postgres:${DB_PASSWORD}@db:5432/sepsisnet
      SEPSISNET_MODEL_CONFIG_PATH: /app/models/tier2_supermodel_v1.json
    volumes:
      - ./models:/app/models
```

### Configuration hierarchy

| Setting | Source | Default |
|---|---|---|
| Model coefficients | JSON file in `/app/models/` | Tier-2 supermodel |
| Scoring threshold | Model JSON + env override | Youden (0.037) |
| Min hours before scoring | `SCORING_MIN_HOURS` | 6 |
| Alert cooldown | `ALERT_COOLDOWN_HOURS` | 2 |
| Data retention (warm) | `RETENTION_DAYS` | 30 |
| Webhook endpoints | Database table + API | None (must configure) |

### To deploy at a new hospital

1. `git clone` the repository
2. Set `DB_PASSWORD` in `.env`
3. `docker compose up -d`
4. Register webhook endpoints via `POST /api/v1/config/webhooks`
5. Point your EHR adapter at `POST /api/v1/observations`
6. Register ICU admissions via `POST /api/v1/stays`

That's it. The system starts scoring after 6 hours of data accumulation for each patient.

> **Recalibration:** The shipped model was trained on MIMIC-IV (US academic center). External validation on eICU showed calibration slope 0.537 — the model over-predicts risk ~3× on a different population. Before clinical use, deployers should: (1) run the system in shadow mode for 2–4 weeks, (2) compute calibration on local data, (3) apply recalibration intercept/slope adjustments to the model JSON file. A one-line recalibration corrected Brier score from 0.052 to 0.040 on eICU.

---

## 11. Migration from Research Codebase

The existing `sepsis_mimic4/` pipeline is a batch-mode research tool. The real-time system reuses the logic but restructures the execution model.

### Code reuse map

| Research script | Real-time component | Reuse |
|---|---|---|
| `config.py` | Model JSON config | Item IDs, thresholds, unit conversions, antibiotics list → extracted into the config schema |
| `04_extract_measurements.py` | Ingestion layer (unit normalization) | FiO2 conversion, temp F→C, MAP/GCS clipping logic → reused verbatim |
| `05_sofa_sepsis3.py` | SOFA Calculator service | Six organ scoring functions (lines 46–111) → extracted as a standalone module |
| `07_hourly_panel.py` | Feature Engine (LOCF, TSL) | Forward-fill and time-since-last logic → reimplemented as SQL window functions |
| `08_onset_label.py` | Feature Engine (scores, slopes) | qSOFA/SIRS calculation, 6h slope computation → reused as Python functions |
| `11_landmark_stack.py` | Feature Engine (assembly) | Feature vector schema, imputation defaults → defines the contract |
| `10_landmark_nomogram.Rmd` | Model JSON config | Tier-1 coefficients exported to `tier1_coefs.csv` → transcribed to JSON |
| `12_supermodel.Rmd` | Model JSON config (v1.1) | Supermodel coefficients with s-interaction terms → JSON with interaction block |
| `14_realtime_holdout.py` | Validation / test harness | The holdout scoring logic is essentially the real-time loop — closest precursor to the production code |
| `15_realtime_eval.Rmd` | Threshold selection | Youden cutoffs, utility scores, alarm rates → inform default threshold config |

### What must be rewritten

- **Data access.** Research scripts read CSV/Parquet files in batch. The real-time system reads from PostgreSQL via parameterized queries. The feature computation logic stays; the I/O layer changes entirely.
- **Hourly resampling.** The research pipeline bins all observations into discrete hours (`07_hourly_panel.py`). The real-time system operates on raw timestamps and computes features at query time. The forward-fill becomes a SQL `LAST_VALUE` window function rather than a pandas operation.
- **Stacking.** The landmark stack (`11_landmark_stack.py`) pre-computes features at fixed hours {6, 12, 18, 24, 36, 48}. The real-time system computes features at the current hour — whatever that is. No stacking needed.

### What stays identical

- SOFA organ scoring thresholds and functions
- qSOFA and SIRS definitions
- Unit conversion rules
- Feature names and semantics
- Imputation strategy (median + missingness flag)
- Model coefficients and the logistic scoring function
- The 26-feature vector schema

---

## 12. Monitoring & Drift Detection

### Operational metrics

- **Ingestion rate** — observations/sec per parameter type. Alert if a source goes silent for > 15 min (suggests interface failure).
- **Scoring latency** — p50 and p99 time from observation ingestion to score computation. Target: < 500ms p99.
- **Alert rate** — alerts/day per active bed. Compare against expected range from Tier-4 evaluation. A sudden spike suggests a sensor or interface problem, not an outbreak.
- **Webhook delivery** — success/failure rate and latency for each configured endpoint.

### Model drift monitoring

The system logs every feature vector and score. A weekly batch job (or on-demand) computes:

- **Feature distribution drift** — compare the distribution of each feature over the last 7 days against the training distribution (shipped as quantiles in the model config). Flag if KL divergence exceeds threshold.
- **Calibration check** — among patients who were scored > threshold, what fraction actually developed sepsis within 12 hours? Plot observed vs. predicted by decile.
- **Alert-to-outcome ratio** — of alerts fired, how many preceded a clinical sepsis diagnosis? This is the deployed positive predictive value.

> **When to retrain:** If calibration slope drifts below 0.7 or above 1.3, or if the alert-to-outcome ratio drops below 15%, the model needs recalibration on local data. The system supports hot-swapping the model config file — update the JSON, restart the API container. No redeployment needed.

### Data quality guards

- Reject observations with physiologically impossible values (HR < 0 or > 300, SpO2 > 100, temp < 25°C or > 45°C)
- Flag duplicate timestamps for the same patient + parameter
- Track per-patient observation density — if vitals frequency drops from every 5 min to every 30 min, the feature quality degrades (time-since-last values inflate, slopes become unreliable)

---

## 13. Implementation Roadmap

| Phase | Scope | Estimate |
|---|---|---|
| **Phase 1 — Core** | Database schema, ingestion API, feature engine, scoring engine, score logging. No webhooks yet — scores are queryable via API. | 2–3 weeks |
| **Phase 2 — Alerts** | Webhook dispatcher, alert state machine, cooldown logic. Integration testing with a Slack webhook. | 1 week |
| **Phase 3 — Validation** | Batch-load MIMIC-IV holdout data through the system. Verify that scores match the research pipeline's output within floating-point tolerance. This is the critical acceptance test. | 1–2 weeks |
| **Phase 4 — Hardening** | Data quality guards, drift monitoring, Docker Compose packaging, documentation for deployers. | 1–2 weeks |
| **Phase 5 — Pilot** | Shadow mode at a partner site. Ingest real data, score silently, compare against actual sepsis diagnoses. Recalibrate. | 4–8 weeks |

---

*SepsisNet System Design Document — derived from `sepsis_mimic4` research pipeline*
*Model baseline: Tier-2 dynamic landmark supermodel, pooled OOS AUROC 0.789 (MIMIC-IV)*
