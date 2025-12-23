output "network_id" {
  description = "ID of created VPC network"
  value = yandex_vpc_network.this.id
}

output "subnet_ids" {
  description = "List of subnet IDs created"
  value = [for s in yandex_vpc_subnet.this : s.id]
}
