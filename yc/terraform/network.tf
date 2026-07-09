resource "yandex_vpc_network" "default_network" {
  name = "tf_network"
}

resource "yandex_vpc_subnet" "default_subnet" {
  name           = "tf_subnet"
  zone           = var.zone
  network_id     = yandex_vpc_network.default_network.id
  v4_cidr_blocks = ["192.168.10.0/24"]
}

resource "yandex_vpc_address" "toronto" {
  name = "toronto-static-ip"

  external_ipv4_address {
    zone_id = var.zone
  }
}
