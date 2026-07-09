terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  zone = var.zone
}


module "toronto" {
  source             = "./modules/vm"
  name               = "toronto"
  subnet_id          = yandex_vpc_subnet.default_subnet.id
  image_id           = var.image_id
  disk_size          = 50
  disk_type          = var.disk_type
  cores              = 4
  memory             = 8
  user_data          = file("${path.module}/cloud_ssh_user_data")
  security_group_ids = [yandex_vpc_security_group.web.id]
  nat_ip_address     = yandex_vpc_address.toronto.external_ipv4_address[0].address
  disk_auto_delete   = false
}

module "winnipeg" {
  source             = "./modules/vm"
  name               = "winnipeg"
  subnet_id          = yandex_vpc_subnet.default_subnet.id
  image_id           = var.image_id
  disk_size          = var.disk_size
  disk_type          = var.disk_type
  cores              = var.cores
  memory             = var.memory
  user_data          = file("${path.module}/cloud_ssh_user_data")
  security_group_ids = [yandex_vpc_security_group.web.id]
}
