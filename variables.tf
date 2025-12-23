variable "env" {
  description = "Deployment environment: dev | stage | prod"
  type        = string
  default     = "dev"
}

variable "folder_id" {
  description = "Yandex Cloud folder id where resources will be created"
  type        = string
}

variable "cloud_id" {
  description = "Yandex Cloud id (optional)"
  type        = string
  default     = ""
}

variable "admin_ip" {
  description = "CIDR or IP allowed to SSH (e.g. 203.0.113.4/32)"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "tanda"
}

variable "db_password" {
  description = "Database password (recommended: provide via env var TF_VAR_db_password)"
  type        = string
  sensitive   = true
}

variable "image_family" {
  description = "Image family for compute instances (e.g. ubuntu-22-04, container-optimized-image)"
  type        = string
  default     = "ubuntu-22-04"
}
