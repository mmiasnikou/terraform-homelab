variable "proxmox_api_token" {
  description = "Proxmox API token in format USER@REALM!TOKENID=SECRET"
  type        = string
  sensitive   = true
}

variable "proxmox_endpoint" {
  description = "Proxmox API endpoint URL"
  type        = string
  default     = "https://192.168.188.130:8006/"
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve"
}

variable "template_id" {
  description = "VM template ID for cloning"
  type        = number
  default     = 9000
}

variable "vms" {
  description = "Map of VMs to create"
  type = map(object({
    cores  = number
    memory = number
    disk   = number
  }))
}
