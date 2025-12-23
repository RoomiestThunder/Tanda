// Network module: creates VPC, one subnet per provided zone and security groups

resource "yandex_vpc_network" "this" {
  name = var.name
  description = "Custom VPC for ${var.name}"
}

// Create one subnet per zone
resource "yandex_vpc_subnet" "this" {
  for_each = toset(var.zones)

  name           = "${var.name}-subnet-${each.key}"
  zone           = each.key
  v4_cidr_block  = cidrsubnet(var.cidr, 8, index(var.zones, each.key))
  network_id     = yandex_vpc_network.this.id
}

// Security group for web and ssh
resource "yandex_vpc_security_group" "web" {
  name       = "${var.name}-sg-web"
  description = "Allow web (80/443) and restricted SSH"
  network_id = yandex_vpc_network.this.id

  ingress {
    description = "HTTP"
    protocol    = "tcp"
    port        = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    protocol    = "tcp"
    port        = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from admin"
    protocol    = "tcp"
    port        = 22
    cidr_blocks = [var.admin_ip]
  }

  egress {
    description = "Allow all egress"
    protocol    = "all"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "network_id" {
  value = yandex_vpc_network.this.id
}

output "subnet_ids" {
  value = [for s in yandex_vpc_subnet.this : s.id]
}

output "zones" {
  value = var.zones
}
