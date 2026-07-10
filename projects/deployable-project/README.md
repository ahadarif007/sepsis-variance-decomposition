# SepsisNet — Real-Time Sepsis Risk Prediction API

A standalone, deployable API for real-time Sepsis-3 onset prediction in ICU patients. Ships with a pre-trained Tier-2 dynamic landmark supermodel (pooled OOS AUROC 0.789 on MIMIC-IV) with time-varying coefficients that adapt as the ICU stay progresses.

## Quick Start

```bash
cp .env.example .env
docker compose up -d
```

The API is available at `http://localhost:8000`. Interactive docs at `http://localhost:8000/docs`.

## API Endpoints

### 1. Register a patient stay

```bash
curl -X POST http://localhost:8000/api/v1/stays \
  -H "Content-Type: application/json" \
  -d '{
    "patient_id": "P-001",
    "stay_id": "S-001",
    "admission_time": "2026-07-10T08:00:00Z",
    "age": 65,
    "sex": "M"
  }'
```

### 2. Send observations and get immediate sepsis assessment

```bash
curl -X POST http://localhost:8000/api/v1/observations \
  -H "Content-Type: application/json" \
  -d '{
    "patient_id": "P-001",
    "stay_id": "S-001",
    "timestamp": "2026-07-10T14:30:00Z",
    "parameter": "heart_rate",
    "value": 112,
    "unit": "bpm"
  }'
```

**Response:**
```json
{
  "patient_id": "P-001",
  "stay_id": "S-001",
  "risk_score": 0.134,
  "sepsis_risk": true,
  "threshold_used": "youden",
  "threshold_value": 0.036904,
  "hours_since_admission": 6.5,
  "sofa_total": 4,
  "scored_at": "2026-07-10T14:30:00Z",
  "feature_vector": { ... }
}
```

### 3. Check sepsis status by patient ID

```bash
curl http://localhost:8000/api/v1/patients/P-001/sepsis-status
```

**Response:**
```json
{
  "patient_id": "P-001",
  "stay_id": "S-001",
  "sepsis_risk": true,
  "risk_score": 0.134,
  "scored_at": "2026-07-10T14:30:00Z",
  "hours_since_admission": 6.5,
  "message": "Sepsis risk detected"
}
```

## Accepted Parameters

| Category | Parameters |
|---|---|
| Vitals | `heart_rate`, `sbp`, `dbp`, `map`, `resp_rate`, `spo2`, `temp_c`, `gcs_total` |
| Labs | `lactate`, `creatinine`, `wbc`, `platelets`, `bilirubin`, `pao2`, `fio2`, `pf_ratio` |
| Vasopressors | `norepinephrine`, `epinephrine`, `dopamine`, `dobutamine`, `vasopressin`, `phenylephrine` |
| Output | `urine_output` |

## Configuration

All settings are via environment variables (prefix `SEPSISNET_`):

| Variable | Default | Description |
|---|---|---|
| `SEPSISNET_DATABASE_URL` | `postgresql+asyncpg://...` | Database connection string |
| `SEPSISNET_MODEL_CONFIG_PATH` | `models/tier2_supermodel_v1.json` | Path to model coefficients |
| `SEPSISNET_SCORING_THRESHOLD` | `youden` | One of: `youden`, `high_sensitivity`, `high_specificity` |

## Project Structure

```
deployable-project/
├── docker-compose.yml
├── .env.example
├── models/
│   └── tier2_supermodel_v1.json     # Tier-2 supermodel coefficients + thresholds
├── services/
│   └── api/
│       ├── Dockerfile
│       ├── requirements.txt
│       └── app/
│           ├── main.py              # FastAPI app + lifespan
│           ├── config.py            # Settings via env vars
│           ├── core/
│           │   ├── sofa.py          # SOFA organ sub-scores
│           │   ├── feature_engine.py # 26-feature vector builder
│           │   └── scoring.py       # Logistic regression scorer
│           ├── db/
│           │   ├── database.py      # Async SQLAlchemy setup
│           │   └── models.py        # ORM models
│           ├── routers/
│           │   ├── observations.py  # POST /observations → score
│           │   └── patients.py      # GET /patients/{id}/sepsis-status
│           └── schemas/
│               ├── observation.py   # Request/response schemas
│               └── patient.py       # Stay schemas
└── SYSTEM_DESIGN.md                 # Full system design document
```
