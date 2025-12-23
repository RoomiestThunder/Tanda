/*
  Compute module: creates a VM (Compute Cloud) and prepares Docker via startup script.
  - Uses a generic linux image by family (default ubuntu-22-04). Swap to CoI by changing image_family.
  - Attaches a public (ephemeral) IP when `public_ip = true`.
*/

data "yandex_compute_image" "base" {
  family = var.image_family
}

resource "yandex_vpc_address" "nat_ip" {
  count = var.public_ip ? 1 : 0
  name  = "${var.name}-ip"
}

resource "yandex_compute_instance" "vm" {
  name        = var.name
  folder_id   = var.folder_id
  zone        = var.zone

  resources {
    memory   = var.instance_memory
    cores    = var.instance_cpu
    core_fraction = 100
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.base.id
      size     = 50
    }
  }

  network_interface {
    subnet_id = var.subnet_id
    nat       = var.public_ip
  }

  metadata = {
    user-data = <<-EOF
      #cloud-config
      package_update: true
      runcmd:
        - [ bash, -lc, "apt-get update && apt-get install -y ca-certificates curl gnupg lsb-release" ]
        - [ bash, -lc, "curl -fsSL https://get.docker.com | sh" ]
        - [ bash, -lc, "systemctl enable docker --now" ]
        - [ bash, -lc, "docker run --restart unless-stopped -d -p 80:80 nginx:stable" ]
    EOF
  }
}

output "instance_id" {
  value = yandex_compute_instance.vm.id
}
