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
  description = "Skip TLS verification for Proxmox API (recommended for self-signed certs)"
  type        = bool
  default     = true
}

variable "proxmox_node" {
  description = "Proxmox node name where the VM will be created"
  type        = string
}

variable "proxmox_storage_iso" {
  description = "Proxmox storage ID for ISO/image files"
  type        = string
  default     = "local"
}

variable "proxmox_storage_vm" {
  description = "Proxmox storage ID for VM disk storage"
  type        = string
  default     = "local-lvm"
}

# ============================================================================
# VM Identity Variables
# ============================================================================

variable "vm_name" {
  description = "VM hostname and name in Proxmox"
  type        = string
}

variable "vm_id" {
  description = "Unique VM ID in Proxmox (100-999 typically)"
  type        = number
}

variable "vm_username" {
  description = "Default user account for cloud-init"
  type        = string
  default     = "ubuntu"
}

variable "vm_ssh_public_key" {
  description = "SSH public key for passwordless authentication"
  type        = string
  sensitive   = true
}

# ============================================================================
# VM Networking Variables
# ============================================================================

variable "vm_ip" {
  description = "Static IP address in CIDR notation (e.g., 192.168.1.50/24)"
  type        = string
}

variable "vm_gateway" {
  description = "Default gateway IP address"
  type        = string
}

variable "vm_dns" {
  description = "DNS server IP address"
  type        = string
  default     = "1.1.1.1"
}

variable "vm_bridge" {
  description = "Proxmox network bridge (vmbr0, vmbr1, etc.)"
  type        = string
  default     = "vmbr0"
}
