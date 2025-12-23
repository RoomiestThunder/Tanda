/*
  Example S3-compatible backend configuration.
  NOTE: this file is intentionally provided as a template. Do NOT commit secrets.

  To use, uncomment and provide backend config values or pass them at `terraform init -backend-config`.
*/

# terraform {
#   backend "s3" {
#     bucket = "<your-terraform-state-bucket>"
#     key    = "tanda/terraform.tfstate"
#     region = "<s3-region>"
#     endpoint = "https://storage.yandexcloud.net" # if using YC Object Storage compatible endpoint
#     access_key = "<ACCESS_KEY>"
#     secret_key = "<SECRET_KEY>"
#     # If your S3 backend supports server-side encryption or KMS, enable here.
#   }
# }
