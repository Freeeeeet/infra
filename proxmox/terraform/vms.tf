locals {
  vms = {
    k3s-master = {
      vm_id      = 202
      ip_address = "192.168.1.200/24"
      cores      = 2
      memory     = 4096
      disk_size  = 150
      tags       = ["k3s", "master", "managed-by-terraform"]
      node_name  = "glass"
    }
    k3s-worker-1 = {
      vm_id      = 203
      ip_address = "192.168.1.201/24"
      cores      = 4
      memory     = 8192
      disk_size  = 150
      tags       = ["k3s", "worker", "managed-by-terraform"]
      node_name  = "glass"
      extra_disks = [
        {
          interface = "virtio1"
          size      = 80
          backup    = false
        }
      ]
    }
    k3s-worker-2 = {
      vm_id      = 204
      ip_address = "192.168.1.202/24"
      cores      = 2
      memory     = 8192
      disk_size  = 150
      tags       = ["k3s", "worker", "managed-by-terraform"]
      node_name  = "glass"

      extra_disks = [
        {
          interface = "virtio1"
          size      = 80
          backup    = false
        }
      ]
    },
    media-storage = {
      vm_id      = 205
      ip_address = "192.168.1.205/24"
      cores      = 2
      memory     = 2048
      disk_size  = 20
      node_name  = "glass"

      extra_disks = [
        {
          interface = "virtio1"
          size      = 800
          backup    = false
        }
      ]

      tags = ["media", "managed-by-terraform"]
    },
    k3s-worker-3 = {
      vm_id      = 206
      ip_address = "192.168.1.203/24"
      cores      = 2
      memory     = 4096
      disk_size  = 75
      tags       = ["k3s", "worker", "managed-by-terraform", "low-resource"]
      node_name  = "node1-home"

      extra_disks = [
        {
          interface = "virtio1"
          size      = 100
          backup    = false
        }
      ]
    },
  }
}

module "vm" {
  for_each = local.vms
  source   = "../../modules/base/vm"

  hostname        = each.key
  node_name       = try(each.value.node_name, var.node_name)
  cloud_image     = var.vm_cloud_image
  gateway         = var.gateway
  username        = var.vm_username
  ssh_public_keys = [file("${path.module}/../.ssh/id_proxmox.pub")]

  vm_id       = try(each.value.vm_id, null)
  ip_address  = try(each.value.ip_address, "dhcp")
  cores       = try(each.value.cores, 2)
  memory      = try(each.value.memory, 2048)
  disk_size   = try(each.value.disk_size, 20)
  extra_disks = try(each.value.extra_disks, [])
  tags        = try(each.value.tags, [])
}
