resource "proxmox_lxc" "plex" {
  target_node     = var.proxmox_instance
  hostname        = "plex"
  cores           = 4
  memory          = 8192
  ostemplate      = "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
  unprivileged    = true
  ostype          = "ubuntu"
  ssh_public_keys = file(var.pub_ssh_key)
  start           = true
  onboot          = true
  vmid            = var.plex_lxcid

  features {
    keyctl        = true
    nesting       = true
  }

  // Terraform will crash without rootfs defined
  rootfs {
    storage = "local-lvm"
    size    = "500G"
  }

  network {
    name   = "eth0"
    bridge = "vmbr0"
    gw     = var.gateway_ip
    ip     = var.plex_ip
    ip6    = "auto"
    hwaddr = var.plex_mac
  }

  lifecycle {
    ignore_changes = [
      mountpoint[0].storage
    ]
  }
}
