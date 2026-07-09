output "container_ips" {
  value = { for name, c in module.lxc : name => c.ip_address }
}

output "vm_ips" {
  value = { for name, v in module.vm : name => v.ip_address }
}
