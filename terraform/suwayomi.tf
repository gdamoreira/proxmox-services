resource "proxmox_lxc" "suwayomi" {
  target_node     = var.proxmox_instance
  hostname        = "suwayomi"
  cores           = 2
  memory          = 4096
  ostype          = "alpine"
  swap            = 1024
  ostemplate      = "local:vztmpl/alpine-3.19-default_20240101_amd64.tar.zst"
  start           = true
  onboot          = true
  vmid            = var.suwayomi_lxcid

  features {
    nesting = true
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
      tags,
      cmode,
      mountpoint[0].storage,
    ]
  }
}
