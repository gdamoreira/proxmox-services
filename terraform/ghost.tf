resource "proxmox_lxc" "ghost" {
  provider        = proxmox.secondary
  target_node     = var.proxmox_secondary_instance
  hostname        = "ghost"
  cores           = 2
  memory          = 2048
  ostemplate      = "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
  unprivileged    = false
  ostype          = "ubuntu"
  ssh_public_keys = file(var.pub_ssh_key)
  start           = true
  onboot          = true
  vmid            = var.ghost_lxcid

  features {
    keyctl  = true
    nesting = true
  }

  rootfs {
    storage = "local-lvm"
    size    = "10G"
  }

  network {
    name   = "eth0"
    bridge = "vmbr0"
    gw     = var.gateway_ip
    ip     = var.ghost_ip
    ip6    = "auto"
    hwaddr = var.ghost_mac
  }

  lifecycle {
    ignore_changes = [
      mountpoint[0].storage
    ]
  }
}
