output "snapshot_schedule_id" {
  value = yandex_compute_snapshot_schedule.nightly.id
}

output "backup_bucket_name" {
  value = yandex_storage_bucket.backups.id
}

output "rto_minutes" {
  value = var.rto_minutes
}

output "rpo_minutes" {
  value = var.rpo_minutes
}
