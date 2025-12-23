output "terraform_sa_id" {
  value = yandex_iam_service_account.terraform.id
}

output "terraform_sa_access_key" {
  value     = yandex_iam_service_account_static_access_key.terraform.access_key
  sensitive = true
}

output "terraform_sa_secret_key" {
  value     = yandex_iam_service_account_static_access_key.terraform.secret_key
  sensitive = true
}

output "app_sa_id" {
  value = yandex_iam_service_account.app.id
}

output "app_sa_access_key" {
  value     = yandex_iam_service_account_static_access_key.app.access_key
  sensitive = true
}

output "app_sa_secret_key" {
  value     = yandex_iam_service_account_static_access_key.app.secret_key
  sensitive = true
}

output "db_sa_id" {
  value = yandex_iam_service_account.db.id
}

output "db_password_secret_id" {
  value = yandex_lockbox_secret.db_password.id
}

output "app_env_secret_id" {
  value = yandex_lockbox_secret.app_env.id
}
