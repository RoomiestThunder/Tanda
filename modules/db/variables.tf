variable "name" {
  type = string
}

variable "folder_id" {
  type = string
}

variable "network_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "postgres_user" {
  type = string
  default = "app"
}

variable "postgres_pass" {
  type      = string
  sensitive = true
}

variable "ha" {
  description = "Enable High Availability (multi-host)"
  type        = bool
  default     = false
}

variable "backup_window" {
  type = string
  default = "01:00"
}

variable "tags" {
  type = map(string)
  default = {}
}
