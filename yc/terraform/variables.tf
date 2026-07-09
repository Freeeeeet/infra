variable "zone" {
  type    = string
  default = "ru-central1-e"
}

variable "image_id" {
  type    = string
  default = "fd80293ig2816a78q276"
}

variable "disk_size" {
  type    = number
  default = 20
}

variable "disk_type" {
  type    = string
  default = "network-hdd"
}

variable "cores" {
  type    = number
  default = 2
}

variable "memory" {
  type    = number
  default = 2
}

variable "security_group_ids" {
  type    = list(string)
  default = []
}
