resource "proxmox_lxc" "immich" {
  provider        = proxmox.secondary
  target_node     = var.proxmox_secondary_instance
  hostname        = "immich"
  cores           = 12
  memory          = 8192
  ostemplate      = "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
  unprivileged    = false
  ostype          = "ubuntu"
  ssh_public_keys = file(var.pub_ssh_key)
  start           = true
  onboot          = true
  vmid            = var.immich_lxcid

  features {
    keyctl  = true
    nesting = true
  }

  rootfs {
    storage = "local-lvm"
    size    = "20G"
  }

  network {
    name   = "eth0"
    bridge = "vmbr0"
    gw     = var.gateway_ip
    ip     = var.immich_ip
    ip6    = "auto"
    hwaddr = var.immich_mac
  }

  lifecycle {
    ignore_changes = [
      mountpoint[0].storage
    ]
  }
}
