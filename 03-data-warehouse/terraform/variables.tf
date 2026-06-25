variable "credentials" {
  default = "./keys/de-zoomcamp-499310-creds.json"
}

variable "project_id" {
  default = "de-zoomcamp-499310"
}

variable "region" {
  default = "us-central1"
}

variable "location" {
  default = "us-central1"    # single region, cheaper, consistent with kestra bucket
}

variable "ml_bucket_name" {
  default = "de-zoomcamp-499310-ml-bucket"
}