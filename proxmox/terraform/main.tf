terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.109"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  # api_token = var.proxmox_token
  username = "root@pam"
  password = var.proxmox_password
  insecure = true
}
