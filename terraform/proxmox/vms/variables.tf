# ============================================================================
# Proxmox Connection Variables
# ============================================================================

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

# ============================================================================
# VM Variables
# ============================================================================

variable "vm_ssh_public_key" {
  description = "SSH public key for passwordless authentication"
  type        = string
  sensitive   = true
}

variable "vms" {
  description = "Map of VM definitions keyed by hostname"
  type = map(object({
    node_name = string
    vm_id     = number
    ip        = string
    gateway   = string
    cpu_cores = optional(number, 2)
    memory    = optional(number, 4096)
    disk_size = optional(number, 16)
    dns       = optional(string, "1.1.1.1")
    bridge    = optional(string, "vmbr0")
    storage   = optional(string, "local-lvm")
    username  = optional(string, "ubuntu")
  }))
}
