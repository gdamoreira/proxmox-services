resource "proxmox_lxc" "kuma" {
  target_node     = var.proxmox_instance
  hostname        = "kuma"
  cores           = 1
  memory          = 256
  ostype          = "debian"
  swap            = 512
  unprivileged    = true
  ostemplate      = "local:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst"
  start           = true
  onboot          = true
  vmid            = var.kuma_lxcid

  features {
    nesting = true
    keyctl  = true
    fuse    = true
  }

  rootfs {
    storage = "local-lvm"
    size    = "4G"
  }

  network {
    name   = "eth0"
    bridge = "vmbr0"
    gw     = var.gateway_ip
    ip     = var.kuma_ip
    hwaddr = var.kuma_mac
  }

  lifecycle {
    ignore_changes = [
      ostemplate,
      description,
      tags,
      cmode,
      mountpoint[0].storage,
    ]
  }
}
