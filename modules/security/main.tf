# Security & IAM module for Yandex Cloud
# Manages service accounts, IAM roles, Yandex Lockbox secrets

terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = ">= 0.77.0"
    }
  }
}

variable "folder_id" {
  type = string
}

variable "env" {
  type = string
}

variable "name_prefix" {
  type    = string
  default = "tanda"
}

# ============================================================================
# SERVICE ACCOUNTS
# ============================================================================

# Service account for Terraform (IaC operations)
resource "yandex_iam_service_account" "terraform" {
  name        = "${var.name_prefix}-terraform-${var.env}"
  folder_id   = var.folder_id
  description = "Service account for Terraform operations in ${var.env}"
}

# Service account for application runtime
resource "yandex_iam_service_account" "app" {
  name        = "${var.name_prefix}-app-${var.env}"
  folder_id   = var.folder_id
  description = "Service account for application in ${var.env}"
}

# Service account for database operations
resource "yandex_iam_service_account" "db" {
  name        = "${var.name_prefix}-db-${var.env}"
  folder_id   = var.folder_id
  description = "Service account for database backups and monitoring in ${var.env}"
}

# ============================================================================
# IAM ROLE BINDINGS
# ============================================================================

# Grant Terraform SA permissions to manage compute and network resources
resource "yandex_resourcemanager_folder_iam_member" "terraform_compute" {
  folder_id = var.folder_id
  role      = "compute.admin"
  member    = "serviceAccount:${yandex_iam_service_account.terraform.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "terraform_vpc" {
  folder_id = var.folder_id
  role      = "vpc.admin"
  member    = "serviceAccount:${yandex_iam_service_account.terraform.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "terraform_mdb" {
  folder_id = var.folder_id
  role      = "mdb.admin"
  member    = "serviceAccount:${yandex_iam_service_account.terraform.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "terraform_lockbox" {
  folder_id = var.folder_id
  role      = "lockbox.admin"
  member    = "serviceAccount:${yandex_iam_service_account.terraform.id}"
}

# Grant app SA permissions to read secrets and logs
resource "yandex_resourcemanager_folder_iam_member" "app_lockbox" {
  folder_id = var.folder_id
  role      = "lockbox.payloadViewer"
  member    = "serviceAccount:${yandex_iam_service_account.app.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "app_logging" {
  folder_id = var.folder_id
  role      = "logging.logWriter"
  member    = "serviceAccount:${yandex_iam_service_account.app.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "app_monitoring" {
  folder_id = var.folder_id
  role      = "monitoring.metricWriter"
  member    = "serviceAccount:${yandex_iam_service_account.app.id}"
}

# Grant DB SA permissions for backups
resource "yandex_resourcemanager_folder_iam_member" "db_mdb" {
  folder_id = var.folder_id
  role      = "mdb.admin"
  member    = "serviceAccount:${yandex_iam_service_account.db.id}"
}

# ============================================================================
# API KEYS FOR SERVICE ACCOUNTS
# ============================================================================

resource "yandex_iam_service_account_static_access_key" "terraform" {
  service_account_id = yandex_iam_service_account.terraform.id
  description        = "Static access key for Terraform SA"
}

resource "yandex_iam_service_account_static_access_key" "app" {
  service_account_id = yandex_iam_service_account.app.id
  description        = "Static access key for App SA"
}

# ============================================================================
# YANDEX LOCKBOX (SECRET MANAGER)
# ============================================================================

resource "yandex_lockbox_secret" "db_password" {
  name                = "${var.name_prefix}-${var.env}-db-password"
  folder_id           = var.folder_id
  description         = "Database password for ${var.env}"
  recovery_window     = 7
}

resource "yandex_lockbox_secret_version" "db_password" {
  secret_id = yandex_lockbox_secret.db_password.id
  entries {
    key        = "password"
    text_value = var.db_password
  }
}

resource "yandex_lockbox_secret" "app_env" {
  name            = "${var.name_prefix}-${var.env}-app-env"
  folder_id       = var.folder_id
  description     = "Application environment variables for ${var.env}"
  recovery_window = 7
}

resource "yandex_lockbox_secret_version" "app_env" {
  secret_id = yandex_lockbox_secret.app_env.id
  entries {
    key        = "DATABASE_URL"
    text_value = "postgresql://tanda_app:${var.db_password}@${var.db_host}:5432/tanda"
  }
  entries {
    key        = "APP_ENV"
    text_value = var.env
  }
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "terraform_sa_id" {
  value = yandex_iam_service_account.terraform.id
}

output "terraform_sa_access_key" {
  value     = yandex_iam_service_account_static_access_key.terraform.access_key
  sensitive = true
}

output "terraform_sa_secret_key" {
  value     = yandex_iam_service_account_static_access_key.terraform.secret_key
  sensitive = true
}

output "app_sa_id" {
  value = yandex_iam_service_account.app.id
}

output "app_sa_access_key" {
  value     = yandex_iam_service_account_static_access_key.app.access_key
  sensitive = true
}

output "app_sa_secret_key" {
  value     = yandex_iam_service_account_static_access_key.app.secret_key
  sensitive = true
}

output "db_password_secret_id" {
  value = yandex_lockbox_secret.db_password.id
}

output "app_env_secret_id" {
  value = yandex_lockbox_secret.app_env.id
}
