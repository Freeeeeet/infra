output "ip_address" {
  # у ВМ адрес лежит в первом сетевом интерфейсе агента; при статике берём заданный
  value = try(proxmox_virtual_environment_vm.this.ipv4_addresses[1][0], split("/", var.ip_address)[0])
}

output "vm_id" {
  value = proxmox_virtual_environment_vm.this.vm_id
}

output "hostname" {
  value = var.hostname
}
