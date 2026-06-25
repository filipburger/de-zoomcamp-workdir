terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.51.0"
    }
  }
}

provider "google" {
  credentials = var.credentials
  project     = var.project_id
  region      = var.region
}

resource "google_storage_bucket" "ml_bucket" {
  name          = var.ml_bucket_name
  location      = var.location
  force_destroy = true
  storage_class = "STANDARD"

  uniform_bucket_level_access = true

  versioning {
    enabled = true
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