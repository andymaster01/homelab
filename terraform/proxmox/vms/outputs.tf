output "vms" {
  description = "Map of VM details"
  value = {
    for name, vm in proxmox_virtual_environment_vm.vm : name => {
      vm_id = vm.vm_id
      name  = vm.name
      ip    = var.vms[name].ip
    }
  }
}
