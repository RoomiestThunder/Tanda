variable "name" {
  type = string
}

variable "folder_id" {
  type = string
}

variable "cloud_id" {
  type    = string
  default = ""
}

variable "cidr" {
  description = "CIDR for VPC network"
  type        = string
  default     = "10.10.0.0/16"
}

variable "zones" {
  type    = list(string)
  default = ["ru-central1-a"]
}

variable "admin_ip" {
  description = "IP/CIDR allowed to SSH"
  type        = string
}

variable "tags" {
  type = map(string)
  default = {}
}
