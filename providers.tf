variable "yc_token" {
  description = "Yandex Cloud token (recommended to set via env var YC_TOKEN)"
  type        = string
  default     = ""
}

provider "yandex" {
  # The provider supports multiple auth methods. For CI, prefer using YC OAuth token (YC_TOKEN env var)
  token = var.yc_token != "" ? var.yc_token : null

  # Optional: set cloud and folder via variables or environment
  # cloud_id  = var.cloud_id
  # folder_id = var.folder_id
}
