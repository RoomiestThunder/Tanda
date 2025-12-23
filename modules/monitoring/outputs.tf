output "prometheus_endpoint" {
  value = "prometheus.monitoring:9090"
}

output "loki_endpoint" {
  value = "loki.monitoring:3100"
}

output "grafana_endpoint" {
  value = "grafana.monitoring:80"
}
