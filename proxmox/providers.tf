terraform {
  required_version = ">= 1.5"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.105"
    }
  }
}

provider "proxmox" {
  endpoint  = "https://192.168.188.130:8006/"
  api_token = var.proxmox_api_token
  insecure  = true   # самоподписанный сертификат
  ssh {
    agent    = false
    username = "root"
  }
}
