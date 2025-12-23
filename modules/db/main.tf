/*
  DB module: creates a Managed PostgreSQL cluster.
  - In `prod` we set `ha = true` to create an HA cluster.
  - For `dev`/`stage` leave HA=false to save costs (single host).

  NOTE: The following is an example using the `yandex_mdb_postgresql_cluster` resource family.
  You may want to tune resources, postgres version and backup/maintenance windows to your needs.
*/

resource "yandex_mdb_postgresql_cluster" "pg" {
  name      = var.name
  folder_id = var.folder_id

  environment = "PRODUCTION"

  network_id = var.network_id
  subnet_ids = var.subnet_ids

  config {
    version = "13" // choose desired postgres minor version

    resources {
      resource_preset_id = var.ha ? "s2.micro" : "s1.micro"
      disk_size          = 20
    }

    backup_window_start = var.backup_window
  }

  // Users: create one application user
  user {
    name     = var.postgres_user
    password = var.postgres_pass
  }

  // For HA: define multiple hosts automatically
  // The provider will create hosts based on cluster config.
}

output "db_endpoint" {
  value = yandex_mdb_postgresql_cluster.pg.host[0].address
  description = "Primary DB endpoint (connect string)"
}
