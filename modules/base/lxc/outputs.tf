output "ip_address" {
  value = try(proxmox_virtual_environment_container.this.ipv4["eth0"], var.ip_address)
}

output "container_id" {
  value = proxmox_virtual_environment_container.this.vm_id
}

output "hostname" {
  value = var.hostname
}
