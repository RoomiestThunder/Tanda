/*
  Monitoring module: provisions Prometheus, Loki, Grafana and alerting rules
  Uses Docker Compose on VM for containerized monitoring stack
  Deployed via cloud-init script to monitoring VM instance
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

variable "grafana_admin_password" {
  type      = string
  sensitive = true
}

variable "slack_webhook_url" {
  type      = string
  sensitive = true
  default   = ""
}

variable "telegram_bot_token" {
  type      = string
  sensitive = true
  default   = ""
}

variable "telegram_chat_id" {
  type      = string
  sensitive = true
  default   = ""
}
