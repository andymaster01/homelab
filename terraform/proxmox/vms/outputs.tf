output "vm_id" {
  description = "Proxmox VM ID"
  value       = proxmox_virtual_environment_vm.vm.vm_id
}

output "vm_name" {
  description = "VM hostname and name"
  value       = proxmox_virtual_environment_vm.vm.name
}

output "vm_ip" {
  description = "Static IP address of the VM"
  value       = var.vm_ip
}
