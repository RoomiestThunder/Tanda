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

variable "db_password" {
  type      = string
  sensitive = true
}

variable "db_host" {
  type = string
  description = "Database hostname/endpoint"
}
