# Home Assistant OS — appliance-образ, НЕ ubuntu+cloud-init.
# Поэтому это не module "base/vm", а отдельный ресурс в стеке.
# Миграция данных делается штатным бэкап/restore самого HA (через веб-морду),
# Ansible тут не используется.

resource "proxmox_virtual_environment_vm" "home_assistant" {
  node_name = var.node_name
  vm_id     = 201
  name      = "home-assistant"
  on_boot   = true
  tags      = ["ha", "managed-by-terraform"]

  # HAOS грузится через UEFI
  bios    = "ovmf"
  machine = "q35"

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 4096
  }

  # для UEFI нужен отдельный efi-диск
  efi_disk {
    datastore_id = "local-lvm"
    type         = "4m"
  }

  # импорт образа HAOS, заранее загруженного на ноду (GUI: local -> ISO images)
  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    import_from  = "local:import/${var.haos_image}"
    size         = 32
  }

  network_device {
    bridge = var.bridge
  }

  agent {
    enabled = true # в HAOS есть qemu-guest-agent
  }
}

output "home_assistant_id" {
  value = proxmox_virtual_environment_vm.home_assistant.vm_id
}
