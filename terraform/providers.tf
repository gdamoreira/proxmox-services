provider "proxmox" {
  pm_api_url  = var.proxmox_api_url
  pm_user     = var.proxmox_user
  pm_password = var.proxmox_password
  // Required when using self signed certs
  pm_tls_insecure = true
}

provider "proxmox" {
  alias       = "secondary"
  pm_api_url  = var.proxmox_secondary_api_url
  pm_user     = var.proxmox_secondary_user
  pm_password = var.proxmox_secondary_password
  pm_tls_insecure = true
}
