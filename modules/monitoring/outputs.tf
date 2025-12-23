output "prometheus_endpoint" {
  value       = "http://monitoring-vm:9090"
  description = "Prometheus endpoint for VM deployment"
}

output "loki_endpoint" {
  value       = "http://monitoring-vm:3100"
  description = "Loki endpoint for VM deployment"
}

output "grafana_endpoint" {
  value       = "http://monitoring-vm:3000"
  description = "Grafana endpoint for VM deployment"
}

output "alertmanager_endpoint" {
  value       = "http://monitoring-vm:9093"
  description = "Alertmanager endpoint for VM deployment"
}

output "node_exporter_endpoint" {
  value       = "http://monitoring-vm:9100"
  description = "Node Exporter endpoint for VM deployment"
}

