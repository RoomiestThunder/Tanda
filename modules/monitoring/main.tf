/*
  Monitoring module: provisions Prometheus, Loki, Grafana and alerting rules
  Uses Helm charts for Kubernetes deployments (if applicable) or Docker on VMs
  
  This module assumes you have Helm available. For VM-based setups, adjust to Docker Compose.
*/

terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = ">= 0.77.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.9.0"
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

variable "monitoring_namespace" {
  type    = string
  default = "monitoring"
}

variable "grafana_admin_password" {
  type      = string
  sensitive = true
}

variable "slack_webhook_url" {
  type      = string
  sensitive = true
  default   = ""
  description = "Optional: Slack webhook for alerts"
}

variable "telegram_bot_token" {
  type      = string
  sensitive = true
  default   = ""
  description = "Optional: Telegram bot token for alerts"
}

variable "telegram_chat_id" {
  type      = string
  sensitive = true
  default   = ""
  description = "Optional: Telegram chat ID for alerts"
}

# ============================================================================
# NAMESPACE
# ============================================================================

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = var.monitoring_namespace
    labels = {
      "app.kubernetes.io/name" = "monitoring"
    }
  }
}

# ============================================================================
# PROMETHEUS (via Helm)
# ============================================================================

resource "helm_release" "prometheus" {
  name             = "${var.name_prefix}-prometheus"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "51.0.0"
  namespace        = kubernetes_namespace.monitoring.metadata[0].name
  create_namespace = false

  values = [yamlencode({
    prometheus = {
      prometheusSpec = {
        # Retention period
        retention = "30d"
        
        # Storage (example: 50Gi persistent volume)
        storageSpec = {
          volumeClaimTemplate = {
            spec = {
              accessModes = ["ReadWriteOnce"]
              resources = {
                requests = {
                  storage = "50Gi"
                }
              }
            }
          }
        }
        
        # Scrape configs
        scrapeConfigs = []
      }
    }
  })]

  depends_on = [kubernetes_namespace.monitoring]
}

# ============================================================================
# LOKI (via Helm)
# ============================================================================

resource "helm_release" "loki_stack" {
  name             = "${var.name_prefix}-loki"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki-stack"
  version          = "2.10.0"
  namespace        = kubernetes_namespace.monitoring.metadata[0].name
  create_namespace = false

  values = [yamlencode({
    loki = {
      enabled = true
      auth_enabled = false
      
      persistence = {
        enabled = true
        size    = "30Gi"
      }
      
      config = {
        limits_config = {
          retention_period = "720h" # 30 days
        }
      }
    }
    
    promtail = {
      enabled = true
    }
  })]

  depends_on = [kubernetes_namespace.monitoring]
}

# ============================================================================
# GRAFANA (via Helm)
# ============================================================================

resource "helm_release" "grafana" {
  name             = "${var.name_prefix}-grafana"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "grafana"
  version          = "6.58.0"
  namespace        = kubernetes_namespace.monitoring.metadata[0].name
  create_namespace = false

  values = [yamlencode({
    replicas = var.env == "prod" ? 2 : 1
    
    adminPassword = var.grafana_admin_password
    
    persistence = {
      enabled = true
      size    = "10Gi"
    }
    
    datasources = {
      "datasources.yaml" = {
        apiVersion = 1
        datasources = [
          {
            name           = "Prometheus"
            type           = "prometheus"
            url            = "http://${var.name_prefix}-prometheus-prometheus:9090"
            access         = "proxy"
            isDefault      = true
          },
          {
            name  = "Loki"
            type  = "loki"
            url   = "http://${var.name_prefix}-loki:3100"
            access = "proxy"
          }
        ]
      }
    }
  })]

  depends_on = [kubernetes_namespace.monitoring, helm_release.prometheus, helm_release.loki_stack]
}

# ============================================================================
# ALERT RULES (Prometheus)
# ============================================================================

resource "kubernetes_config_map" "alert_rules" {
  metadata {
    name      = "${var.name_prefix}-alert-rules"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    "alert-rules.yaml" = <<-EOT
      groups:
        - name: tanda.rules
          interval: 30s
          rules:
            # Application alerts
            - alert: HighErrorRate
              expr: |
                (sum(rate(http_requests_total{status=~"5.."}[5m])) by (job)) 
                / 
                (sum(rate(http_requests_total[5m])) by (job)) > 0.05
              for: 5m
              labels:
                severity: warning
                service: tanda
              annotations:
                summary: "High error rate detected in {{ $labels.job }}"
                description: "Error rate is {{ $value | humanizePercentage }} for the last 5 minutes"

            - alert: ServiceDown
              expr: up{job="tanda-app"} == 0
              for: 1m
              labels:
                severity: critical
                service: tanda
              annotations:
                summary: "Service {{ $labels.job }} is down"
                description: "Service is unreachable"

            # Infrastructure alerts
            - alert: HighCPUUsage
              expr: |
                (100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)) > 80
              for: 5m
              labels:
                severity: warning
              annotations:
                summary: "High CPU usage on {{ $labels.instance }}"
                description: "CPU usage is {{ $value | humanize }}%"

            - alert: HighMemoryUsage
              expr: |
                (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) > 0.85
              for: 5m
              labels:
                severity: warning
              annotations:
                summary: "High memory usage on {{ $labels.instance }}"
                description: "Memory usage is {{ $value | humanizePercentage }}"

            - alert: DiskSpaceRunningOut
              expr: |
                (node_filesystem_avail_bytes{fstype!~"tmpfs|fuse.lego"} / node_filesystem_size_bytes) < 0.15
              for: 5m
              labels:
                severity: warning
              annotations:
                summary: "Disk space running out on {{ $labels.instance }}"
                description: "Available disk space is {{ $value | humanizePercentage }}"

            # Database alerts
            - alert: PostgreSQLDown
              expr: pg_up == 0
              for: 1m
              labels:
                severity: critical
              annotations:
                summary: "PostgreSQL is down"
                description: "PostgreSQL on {{ $labels.instance }} is not responding"

            - alert: PostgreSQLTooManyConnections
              expr: |
                sum by (instance) (pg_stat_activity_count) / pg_settings_max_connections > 0.8
              for: 5m
              labels:
                severity: warning
              annotations:
                summary: "PostgreSQL connection pool near limit"
                description: "Connection usage is {{ $value | humanizePercentage }}"

            - alert: PostgreSQLSlowQueries
              expr: |
                pg_slow_queries > 10
              for: 10m
              labels:
                severity: info
              annotations:
                summary: "Slow queries detected"
                description: "{{ $value }} slow queries in the last interval"

            # Network alerts
            - alert: HighNetworkLatency
              expr: |
                probe_duration_seconds > 0.5
              for: 5m
              labels:
                severity: warning
              annotations:
                summary: "High latency detected"
                description: "Latency is {{ $value | humanizeDuration }}"
    EOT
  }
}

# ============================================================================
# ALERTMANAGER CONFIG
# ============================================================================

resource "kubernetes_secret" "alertmanager_config" {
  metadata {
    name      = "${var.name_prefix}-alertmanager-config"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    "alertmanager.yaml" = base64encode(<<-EOT
      global:
        resolve_timeout: 5m

      route:
        group_by: ['alertname', 'cluster', 'service']
        group_wait: 30s
        group_interval: 5m
        repeat_interval: 12h
        receiver: 'default'
        routes:
          - match:
              severity: critical
            receiver: 'critical'
          - match:
              severity: warning
            receiver: 'warning'

      receivers:
        - name: 'default'
          webhook_configs:
            - url: 'http://localhost:5001/'

        - name: 'critical'
          ${var.slack_webhook_url != "" ? "slack_configs:" : ""}
          ${var.slack_webhook_url != "" ? "  - api_url: '${var.slack_webhook_url}'" : ""}
          ${var.slack_webhook_url != "" ? "    channel: '#alerts-critical'" : ""}
          ${var.slack_webhook_url != "" ? "    send_resolved: true" : ""}

        - name: 'warning'
          ${var.telegram_bot_token != "" ? "telegram_configs:" : ""}
          ${var.telegram_bot_token != "" ? "  - bot_token: '${var.telegram_bot_token}'" : ""}
          ${var.telegram_bot_token != "" ? "    chat_id: '${var.telegram_chat_id}'" : ""}
          ${var.telegram_bot_token != "" ? "    send_resolved: true" : ""}
    EOT
    )
  }
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "prometheus_endpoint" {
  value = "${var.name_prefix}-prometheus-prometheus.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:9090"
}

output "loki_endpoint" {
  value = "${var.name_prefix}-loki.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:3100"
}

output "grafana_endpoint" {
  value = "${var.name_prefix}-grafana.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:80"
}
