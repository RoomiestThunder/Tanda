variable "name" {
  type = string
}

variable "folder_id" {
  type = string
}

variable "network_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "zone" {
  type = string
}

variable "public_ip" {
  type = bool
  default = true
}

variable "image_family" {
  type = string
  default = "ubuntu-22-04"
  description = "Image family to use. For Container Optimized Image, set to the appropriate family name."
}

variable "instance_cpu" {
  type = number
  default = 2
}

variable "instance_memory" {
  type = number
  default = 2
}

variable "tags" {
  type = map(string)
  default = {}
}
