variable "node_name" {
  type    = string
  default = "glass"
}

variable "template" {
  type    = string
  default = "local:vztmpl/ubuntu-26.04-standard_26.04-1_amd64.tar.zst"
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
  default = 512
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

variable "ssh_public_keys" {
  type    = list(string)
  default = []
}

variable "unprivileged" {
  type    = bool
  default = true
}

variable "gateway" {
  type    = string
  default = "192.168.1.1"
}

variable "nesting" {
  type    = bool
  default = true
}

variable "start_on_boot" {
  type    = bool
  default = true
}

variable "tags" {
  type    = list(string)
  default = []
}

variable "mount_points" {
  type = list(object({
    volume = string
    path   = string
  }))
  default = []
}
