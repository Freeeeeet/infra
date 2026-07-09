terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
}

resource "yandex_compute_disk" "default_disk" {
  name     = var.name
  size     = var.disk_size
  zone     = var.zone
  image_id = var.image_id
  type     = var.disk_type
}

resource "yandex_compute_instance" "default_vm" {
  name        = var.name
  hostname    = var.name
  platform_id = var.platform_id

  resources {
    cores  = var.cores
    memory = var.memory
  }

  boot_disk {
    disk_id     = yandex_compute_disk.default_disk.id
    auto_delete = var.disk_auto_delete
  }

  network_interface {
    subnet_id          = var.subnet_id
    nat                = true
    security_group_ids = var.security_group_ids
    nat_ip_address     = var.nat_ip_address
  }
  metadata = {
    user-data = var.user_data
  }

}

