
locals {
  containers = {
    jellyfin = {
      vm_id      = 115
      ip_address = "192.168.1.175/24"
      cores      = 2
      memory     = 2048
      mount_points = [
        {
          volume = "/shared_data"
          path   = "/data"
        },
      ]
    },
    prowlarr = {
      vm_id      = 116
      ip_address = "192.168.1.176/24"
      cores      = 1
      memory     = 512
    },
    proxy-xray = {
      vm_id      = 101
      ip_address = "192.168.1.177/24"
      cores      = 1
      memory     = 512
      disk_size  = 8
      tags       = ["proxy", "xray", "managed-by-terraform"]
      nesting    = true
    }

  }
}

module "lxc" {
  for_each = local.containers
  source   = "../../modules/base/lxc"

  # общее для всех — из переменных стека
  hostname        = each.key
  node_name       = var.node_name
  template        = var.template
  gateway         = var.gateway
  ssh_public_keys = [file("${path.module}/../.ssh/id_proxmox.pub")]

  # частное для экземпляра — из карты, с дефолтами через try()
  vm_id        = try(each.value.vm_id, null)
  ip_address   = try(each.value.ip_address, "dhcp")
  cores        = try(each.value.cores, 2)
  memory       = try(each.value.memory, 512)
  disk_size    = try(each.value.disk_size, 20)
  nesting      = try(each.value.nesting, true)
  tags         = try(each.value.tags, [])
  mount_points = try(each.value.mount_points, [])
}
