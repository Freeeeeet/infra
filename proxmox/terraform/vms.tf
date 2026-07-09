locals {
  vms = {
    k3s-master = {
      vm_id      = 202
      ip_address = "192.168.1.200/24"
      cores      = 2
      memory     = 2048
      disk_size  = 30
      tags       = ["k3s", "master"]
    }
    k3s-worker-1 = {
      vm_id      = 203
      ip_address = "192.168.1.201/24"
      cores      = 4
      memory     = 8192
      disk_size  = 40
      tags       = ["k3s", "worker"]
    }
    k3s-worker-2 = {
      vm_id      = 204
      ip_address = "192.168.1.202/24"
      cores      = 2
      memory     = 8192
      disk_size  = 40
      tags       = ["k3s", "worker"]
    }
  }
}

module "vm" {
  for_each = local.vms
  source   = "../../modules/base/vm"

  hostname        = each.key
  node_name       = var.node_name
  cloud_image     = var.vm_cloud_image
  gateway         = var.gateway
  username        = var.vm_username
  ssh_public_keys = [file("${path.module}/../.ssh/id_proxmox.pub")]

  vm_id      = try(each.value.vm_id, null)
  ip_address = try(each.value.ip_address, "dhcp")
  cores      = try(each.value.cores, 2)
  memory     = try(each.value.memory, 2048)
  disk_size  = try(each.value.disk_size, 20)
  tags       = try(each.value.tags, [])
}
