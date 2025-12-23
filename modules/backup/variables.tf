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
}

variable "snapshot_retention_days" {
  type    = number
  default = 30
}

variable "db_backup_enabled" {
  type    = bool
  default = true
}

variable "db_backup_window" {
  type    = string
  default = "01:00"
}

variable "rto_minutes" {
  type    = number
  default = 60
}

variable "rpo_minutes" {
  type    = number
  default = 15
}
