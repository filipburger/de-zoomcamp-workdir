variable "project_id" {
  description = "My project id"
  #Update the below to what you want your dataset to be called
  default = "de-zoomcamp-499310"
}

variable "credentials" {
  description = "My Credentials"
  default     = "./keys/de-zoomcamp-499310-creds.json"
  #ex: if you have a directory where this file is called keys with your service account json file
  #saved there as my-creds.json you could use default = "./keys/my-creds.json"
}

variable "location" {
  description = "My project location"
  #Update the below to what you want your dataset to be called
  default = "US"
}

variable "region" {
  description = "My project region"
  #Update the below to what you want your dataset to be called
  default = "us-central1"
}

variable "bq_dataset_name" {
  description = "My bq dataset name"
  #Update the below to what you want your dataset to be called
  default = "dezoomcamp_dataset"
}

variable "gcs_bucket_name" {
  description = "My Storage Bucket Name"
  #Update the below to a unique bucket name
  default = "de-zoomcamp-499310-terraform-bucket"
}

variable "gcs_storage_class" {
  description = "Bucket Storage Class"
  default     = "STANDARD"
}