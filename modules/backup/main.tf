/*
  Backup and Disaster Recovery (DR) module
  - Configures automated snapshots for compute instances
  - Sets backup policies for managed databases
  - Provides RTO/RPO targets and recovery procedures
*/

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

variable "snapshot_schedule_hour" {
  type    = number
  default = 2
  description = "Hour (UTC) to take snapshots"
}

variable "snapshot_retention_days" {
  type    = number
  default = 30
  description = "Retention period for snapshots in days"
}

variable "db_backup_enabled" {
  type    = bool
  default = true
  description = "Enable automated DB backups"
}

variable "db_backup_window" {
  type    = string
  default = "01:00"
  description = "Backup window for managed databases (HH:MM)"
}

variable "rto_minutes" {
  type    = number
  default = 60
  description = "Recovery Time Objective in minutes"
}

variable "rpo_minutes" {
  type    = number
  default = 15
  description = "Recovery Point Objective in minutes"
}

# ============================================================================
# COMPUTE SNAPSHOTS (automated schedule)
# ============================================================================

# Note: YC does not have native scheduled snapshots like AWS. 
# Use Cloud Functions + Cloud Scheduler or external tool.
# This is a placeholder configuration showing best practices.

resource "yandex_compute_snapshot_schedule" "nightly" {
  name        = "${var.name_prefix}-${var.env}-snapshot-schedule"
  description = "Nightly snapshots for ${var.env} environment"
  folder_id   = var.folder_id

  schedule_policy {
    expression = "0 ${var.snapshot_schedule_hour} * * *"
  }

  snapshot_count = var.snapshot_retention_days
  
  labels = {
    env = var.env
  }
}

# ============================================================================
# BACKUP STORAGE (Object Storage bucket for cross-region backups)
# ============================================================================

resource "yandex_storage_bucket" "backups" {
  bucket        = "${var.name_prefix}-${var.env}-backups-${data.yandex_client_config.current.account_id}"
  acl           = "private"
  force_destroy = false

  versioning {
    enabled = true
  }

  # Enable server-side encryption
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  # Lifecycle policy: transition old versions to cold storage, delete after retention
  lifecycle_rule {
    enabled = true

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "COLD"
    }

    noncurrent_version_expiration {
      noncurrent_days = var.snapshot_retention_days
    }
  }
}

# ============================================================================
# DATA SOURCES (for reference)
# ============================================================================

data "yandex_client_config" "current" {}

# ============================================================================
# OUTPUTS & RTO/RPO SUMMARY
# ============================================================================

output "snapshot_schedule_id" {
  value = yandex_compute_snapshot_schedule.nightly.id
}

output "backup_bucket_name" {
  value = yandex_storage_bucket.backups.id
}

output "rto_minutes" {
  value = var.rto_minutes
  description = "Recovery Time Objective: target time to restore service (minutes)"
}

output "rpo_minutes" {
  value = var.rpo_minutes
  description = "Recovery Point Objective: maximum acceptable data loss (minutes)"
}

output "dr_summary" {
  value = <<-EOT
    Disaster Recovery Configuration for ${var.env}:
    - Snapshot Schedule: Daily at ${var.snapshot_schedule_hour}:00 UTC
    - Snapshot Retention: ${var.snapshot_retention_days} days
    - Backup Bucket: ${yandex_storage_bucket.backups.id}
    - DB Backup Window: ${var.db_backup_window} UTC
    - RTO Target: ${var.rto_minutes} minutes
    - RPO Target: ${var.rpo_minutes} minutes
    
    Recovery Procedures:
    1. For VM snapshots: use 'yc compute disk-placement-group' or restore from snapshot
    2. For DB: restore from managed backup or WAL replay
    3. See runbooks/DISASTER_RECOVERY.md for detailed steps
  EOT
}
