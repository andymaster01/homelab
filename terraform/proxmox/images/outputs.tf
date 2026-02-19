output "ubuntu_cloud_image_id" {
  description = "Proxmox file ID of the Ubuntu 24.04 cloud image"
  value       = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
}
