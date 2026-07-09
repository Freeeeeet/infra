variable "name" {
  type        = string
  description = "The name of the VM"
}

variable "disk_size" {
  type    = number
  default = 20
}

variable "image_id" {
  type    = string
  default = "fd80293ig2816a78q276"
}

variable "cores" {
  type    = number
  default = 2
}

variable "memory" {
  type    = number
  default = 2
}

variable "subnet_id" {
  type = string
}

variable "user_data" {
  type = string
}

variable "zone" {
  type    = string
  default = "ru-central1-e"
}

variable "platform_id" {
  type    = string
  default = "standard-v3"
}

variable "disk_type" {
  type    = string
  default = "network-hdd"
}

variable "security_group_ids" {
  type    = list(string)
  default = []
}

variable "nat_ip_address" {
  type    = string
  default = null
}

variable "disk_auto_delete" {
  type    = bool
  default = true
}
