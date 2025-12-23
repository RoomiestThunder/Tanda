output "db_endpoint" {
  description = "Primary DB endpoint"
  value       = try(yandex_mdb_postgresql_cluster.pg.host[0].address, "")
}

output "db_cluster_id" {
  value = yandex_mdb_postgresql_cluster.pg.id
}
