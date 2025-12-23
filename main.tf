// Root module — wires network, db, compute, security, monitoring and backup modules per environment

locals {
  tags = {
    env = var.env
  }
}

module "network" {
  source      = "./modules/network"
  name        = "${var.name_prefix}-${var.env}-net"
  folder_id   = var.folder_id
  cloud_id    = var.cloud_id
  cidr        = "10.10.0.0/16"
  zones       = ["ru-central1-a"]
  admin_ip    = var.admin_ip
  tags        = local.tags
}

module "db" {
  source         = "./modules/db"
  name           = "${var.name_prefix}-${var.env}-db"
  folder_id      = var.folder_id
  network_id     = module.network.network_id
  subnet_ids     = module.network.subnet_ids
  postgres_user  = "tanda_app"
  postgres_pass  = var.db_password
  ha             = var.env == "prod" ? true : false
  backup_window  = "01:00"
  tags           = local.tags
}

module "app" {
  source = "./modules/compute"
  name   = "${var.name_prefix}-${var.env}-app"
  folder_id  = var.folder_id
  network_id = module.network.network_id
  subnet_id  = module.network.subnet_ids[0]
  zone       = module.network.zones[0]
  public_ip  = true
  image_family = var.image_family
  tags = local.tags
}

module "security" {
  source        = "./modules/security"
  env           = var.env
  folder_id     = var.folder_id
  name_prefix   = var.name_prefix
  db_password   = var.db_password
  db_host       = module.db.db_endpoint
}

module "backup" {
  source                   = "./modules/backup"
  env                      = var.env
  folder_id                = var.folder_id
  name_prefix              = var.name_prefix
  snapshot_schedule_hour   = 2
  snapshot_retention_days  = var.env == "prod" ? 60 : 30
  db_backup_window         = "01:00"
  rto_minutes              = var.env == "prod" ? 30 : 60
  rpo_minutes              = var.env == "prod" ? 5 : 15
}

output "network_id" {
  value = module.network.network_id
}

output "db_endpoint" {
  value = module.db.db_endpoint
}

output "app_instance_id" {
  value = module.app.instance_id
}

output "terraform_sa_id" {
  value = module.security.terraform_sa_id
}

output "app_sa_id" {
  value = module.security.app_sa_id
}

output "db_password_secret_id" {
  value = module.security.db_password_secret_id
}

output "backup_bucket" {
  value = module.backup.backup_bucket_name
}

output "rto_target" {
  value = module.backup.rto_minutes
}
