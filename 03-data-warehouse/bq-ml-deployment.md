# BigQuery ML Model Deployment — Context & Guide

## Why Deploy at All?

`ML.PREDICT` inside BigQuery is great for batch analysis but useless for real-time applications.
A taxi app wanting to show a suggested tip before payment can't run a SQL query for every trip —
it needs an HTTP API it can call in milliseconds with one trip's data and get a prediction back instantly.

```
Without deployment:          With deployment:
SQL query → BQ → result      App → HTTP POST → Docker container → prediction JSON
(batch, slow, SQL only)      (real-time, any language, any app)
```

---

## Architecture Overview

```
BigQuery ML model
      ↓ export (bq extract)
Google Cloud Storage (GCS)    ← model files stored here
      ↓ download (gsutil cp)
Local filesystem              ← copied to your machine
      ↓ serve
TensorFlow Serving (Docker)   ← HTTP server that loads the model
      ↓ expose
localhost:8501                ← REST API endpoint
      ↓ call
curl / any HTTP client        ← make predictions
```

BigQuery ML exports models in **TensorFlow SavedModel format** — which is why TensorFlow Serving
is used here even though you never wrote any TensorFlow. BigQuery ML uses TF under the hood
for linear regression.

## Prerequisites — Create GCS Bucket via Terraform

Before exporting the model, create a dedicated GCS bucket for ML artifacts using Terraform.
Keep ML artifacts separate from pipeline data (CSVs) for cleaner organisation and independent
lifecycle management.

### Terraform config (`03-data-warehouse/terraform/main.tf`)

```hcl
resource "google_storage_bucket" "ml_bucket" {
  name          = var.ml_bucket_name
  location      = var.location
  force_destroy = true
  storage_class = "STANDARD"

  uniform_bucket_level_access = true

  versioning {
    enabled = true    # keep previous model versions — useful for rollback
  }

  lifecycle_rule {
    condition {
      age = 1
    }
    action {
      type = "AbortIncompleteMultipartUpload"
    }
  }
}

output "ml_bucket_url" {
  value       = "gs://${google_storage_bucket.ml_bucket.name}"
  description = "GCS URL for ML model artifacts — use in bq extract command"
}
```

```bash
cd 03-data-warehouse/terraform
terraform init
terraform plan
terraform apply    # prints ml_bucket_url output — copy into bq extract command
```

Bucket naming convention: `{project_id}-ml-bucket` keeps it distinct from
`{project_id}-kestra-bucket` (pipeline data) and `{project_id}-terraform-bucket` (Module 1).

---

## Step-by-Step with Context

### Step 1 — Authenticate

```bash
gcloud auth login
```

Authenticates your terminal session with GCP so subsequent commands can access your project.
Same as logging into GCP Console but for the command line.

---

### Step 2 — Export Model from BigQuery to GCS

```bash
bq --project_id de-zoomcamp-499310 extract -m zoomcamp.tip_prediction_model \
  gs://de-zoomcamp-499310-ml-bucket/tip_prediction_model
```

`bq` is Google's BigQuery CLI tool. The `-m` flag means "this is a model, not a table."
This exports the trained model weights and metadata from BigQuery into GCS as TensorFlow
SavedModel files. Without this step the model only exists inside BigQuery — you can't run
it anywhere else.

To check what's in your GCS bucket right now:
```bash
gcloud storage ls gs://de-zoomcamp-499310-ml-bucket/tip_prediction_model
```
---

### Steps 3-5 — Download and Arrange Files Locally

Now download the model:
```bash
mkdir -p /tmp/model
gsutil cp -r gs://de-zoomcamp-499310-ml-bucket/tip_prediction_model /tmp/model
```
Verify it downloaded:
```bash
ls /tmp/model/tip_prediction_model/
```
Should show saved_model.pb, variables/, assets/, fingerprint.pb, explanation_metadata.json — matching what you see in GCS. Then we can set up the serving directory structure and run TF Serving.
And yes — once the model is downloaded locally you can terraform destroy the ML bucket to avoid any storage costs. The model files live on your Mac now.

TensorFlow Serving expects a specific folder structure:

```
serving_dir/
└── tip_model/           ← model name
    └── 1/               ← version number (must be an integer)
        ├── saved_model.pb
        └── variables/
```

The `/1` subdirectory is mandatory — TF Serving uses version numbers to support model versioning.
This allows deploying version 2 alongside version 1 for A/B testing, or rolling back to version 1
if version 2 performs poorly. The intermediate copy steps exist purely to reshape the downloaded
files into TF Serving's expected layout.

---

### Step 6 — Pull TensorFlow Serving Image

```bash
docker pull tensorflow/serving
```

Downloads the TF Serving Docker image — a pre-built HTTP server that knows how to load and serve
TensorFlow models. No custom code needed, just Google's official serving infrastructure.

---

### Step 7 — Run the Serving Container

```bash
docker run -d -p 8501:8501 \
  --mount type=bind,source=`pwd`/serving_dir/tip_model,target=/models/tip_model \
  -e MODEL_NAME=tip_model \
  tensorflow/serving
```

Flag breakdown:

```
-p 8501:8501              → expose port 8501 (REST API) from container to your Mac
--mount type=bind,...     → bind mount your local serving_dir into the container
                            container reads model files directly from your local folder
                            same concept as -v flag, just newer Docker syntax
-e MODEL_NAME=tip_model   → tells TF Serving which model to load
-t tensorflow/serving     → the image to run
-d                       → run in background so terminal stays usable
```

Port 8501 is TF Serving's default REST API port.
Port 8500 (not used here) is its gRPC port — lower level, higher performance, used in production.

---

### Step 8 — Make a Prediction via HTTP

```bash
curl -d '{"instances": [{"passenger_count":1, "trip_distance":12.2, "PULocationID":"193", "DOLocationID":"264", "payment_type":"1","fare_amount":20.4,"tolls_amount":0.0}]}' \
  -X POST http://localhost:8501/v1/models/tip_model:predict
```

This is the core use case — a single trip's features sent as JSON to the REST API.
The model returns a predicted tip amount in milliseconds.

```
-d '{"instances": [...]}'   → POST body: one or more trip records as JSON
-X POST                     → HTTP POST request
/v1/models/tip_model:predict  → TF Serving's standard prediction endpoint
```

TF Serving URL structure:
```
/v1/models/{model_name}:predict    → prediction endpoint (POST)
/v1/models/{model_name}            → model status endpoint (GET)
```

You can pass multiple instances in one request for batch predictions:
```bash
curl -d '{"instances": [
  {"passenger_count":1, "trip_distance":12.2, "PULocationID":"193", "DOLocationID":"264", "payment_type":"1","fare_amount":20.4,"tolls_amount":0.0},
  {"passenger_count":2, "trip_distance":5.1,  "PULocationID":"132", "DOLocationID":"138", "payment_type":"1","fare_amount":18.5,"tolls_amount":6.12}
]}' -X POST http://localhost:8501/v1/models/tip_model:predict
```

---

### Step 9 — Check Model Status

```bash
curl http://localhost:8501/v1/models/tip_model
```

Simple GET request to verify the model loaded correctly and is ready to serve.
Returns JSON with model version, status, and readiness.
If it shows `"state": "AVAILABLE"` the server is ready.

## Alternative: Run with Docker Compose

Instead of the `docker run` command, you can use Docker Compose for a cleaner,
repeatable setup with no flags to remember:

```yaml
# docker-compose.yaml
services:
  tip-model:
    image: tensorflow/serving
    platform: linux/amd64    # required on Apple Silicon (arm64)
    ports:
      - "8501:8501"
    volumes:
      - ./serving_dir/tip_model:/models/tip_model
    environment:
      MODEL_NAME: tip_model
```

```bash
docker compose up -d
docker compose down    # to stop
```

**Folder structure required** — TF Serving expects a version number subdirectory:

---

## The Broader Pattern

This export → containerize → serve via REST API pattern is how virtually every
production ML deployment works. The specific tools change but the concept is identical:

```
Train model (BigQuery ML / sklearn / PyTorch)
     ↓
Export model artifacts (SavedModel / pickle / ONNX)
     ↓
Wrap in HTTP server (TF Serving / FastAPI / Flask)
     ↓
Containerize (Docker)
     ↓
Deploy (GCP Cloud Run / Vertex AI / Kubernetes)
     ↓
Call from application (REST API)
```

### Alternative serving tools worth knowing:

```
TF Serving     → official TensorFlow model server, what BigQuery ML exports to
FastAPI        → Python-based, popular for custom sklearn/XGBoost models
Vertex AI      → GCP's managed ML platform, no Docker management needed
BentoML        → framework-agnostic model serving, good for mixed frameworks
Triton         → NVIDIA's high-performance inference server (GPU workloads)
```

---

## Why the Prediction Includes payment_type="2" (Cash)?

In the example curl command, `payment_type` is "2" (cash). This is intentional —
the model was trained to predict what the tip *would be*, not to check if it's
a cash trip where tips aren't recorded. In a real application you'd only call
this endpoint for credit card trips (payment_type=1) where the tip suggestion
actually makes sense in the UI.

---

## Data Quality Note

Recall from the model training phase:
- The model achieved R² ≈ 0.42 even after filtering to credit card trips only
- Tipping is driven by human factors not captured in the data (driver behavior,
  mood, time of day, surge pricing, app UI nudges)
- This model is suitable for *suggesting* a tip amount, not *predicting* it precisely
- A real production tip suggestion model would use additional features and likely
  a more sophisticated algorithm (gradient boosted trees, neural network)

---

## Official Reference

[BigQuery ML Export Model Tutorial](https://cloud.google.com/bigquery-ml/docs/export-model-tutorial)