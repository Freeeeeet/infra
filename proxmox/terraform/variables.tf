variable "proxmox_endpoint" {
  type    = string
  default = "https://192.168.1.122:8006"
}

variable "proxmox_token" {
  type      = string
  sensitive = true
}

variable "proxmox_password" {
  type      = string
  sensitive = true
}

variable "node_name" {
  type    = string
  default = "glass"
}

variable "template" {
  type    = string
  default = "local:vztmpl/ubuntu-26.04-standard_26.04-1_amd64.tar.zst"
}

variable "gateway" {
  type    = string
  default = "192.168.1.1"
}

variable "bridge" {
  type    = string
  default = "vmbr0"
}

# --- Home Assistant ---

variable "haos_image" {
  type        = string
  description = "Имя загруженного на ноду образа HAOS, напр. haos_ova-15.2.qcow2"
}

# --- для ВМ ---

variable "vm_cloud_image" {
  type        = string
  description = "local:import/ubuntu-26.04-server-cloudimg-amd64.img.qcow2"
}

variable "vm_username" {
  type    = string
  default = "ubuntu"
}
