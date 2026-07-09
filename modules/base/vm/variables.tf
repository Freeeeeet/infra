variable "node_name" {
  type    = string
  default = "glass"
}

variable "hostname" {
  type = string
}

variable "vm_id" {
  type    = number
  default = null
}

variable "cores" {
  type    = number
  default = 2
}

variable "memory" {
  type    = number
  default = 2048
}

variable "disk_size" {
  type    = number
  default = 20
}

variable "datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "bridge" {
  type    = string
  default = "vmbr0"
}

variable "ip_address" {
  type    = string
  default = "dhcp"
}

variable "gateway" {
  type    = string
  default = "192.168.1.1"
}

variable "username" {
  type    = string
  default = "ubuntu"
}

variable "ssh_public_keys" {
  type    = list(string)
  default = []
}

variable "start_on_boot" {
  type    = bool
  default = true
}

variable "tags" {
  type    = list(string)
  default = []
}

variable "cloud_image" {
  type    = string
  default = "local:import/ubuntu-26.04-server-cloudimg-amd64.img.qcow2"
}

variable "snippets_datastore_id" {
  type    = string
  default = "local"
}
