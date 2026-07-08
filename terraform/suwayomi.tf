resource "proxmox_lxc" "suwayomi" {
  target_node     = var.proxmox_instance
  hostname        = "suwayomi"
  cores           = 2
  memory          = 4096
  ostype          = "debian"
  swap            = 1024
  ostemplate      = "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
  start           = true
  onboot          = true
  vmid            = var.suwayomi_lxcid
  unprivileged    = false
  tags            = "debian;docker;essentials;manga;media;suwayomi"

  features {
    nesting = true
    keyctl  = true
    fuse    = true
  }

  rootfs {
    storage = "local-lvm"
    size    = "100G"
  }

  network {
    name   = "eth0"
    bridge = "vmbr0"
    gw     = var.gateway_ip
    ip     = var.suwayomi_ip
    hwaddr = var.suwayomi_mac
  }

  lifecycle {
    ignore_changes = [
      ostemplate,
      description,
      cmode,
      mountpoint[0].storage,
    ]
  }
}
