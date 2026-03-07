output "ubuntu_cloud_image_ids" {
  description = "Map of node names to cloud image file ID"
  value       = { for node, img in 
    proxmox_virtual_environment_download_file.ubuntu_cloud_image : node => img.id }
}
