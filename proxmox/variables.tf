variable "proxmox_api_token" {
  description = "Proxmox API token in format USER@REALM!TOKENID=SECRET"
  type        = string
  sensitive   = true
}
