variable "proxmox_endpoint" {
  description = "Proxmox API endpoint (e.g., https://192.168.1.x:8006/)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token (user@pam!token-id=secret)"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS verification for Proxmox API"
  type        = bool
  default     = true
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
}

variable "proxmox_storage_iso" {
  description = "Proxmox storage ID for ISO/image files"
  type        = string
  default     = "local"
}
