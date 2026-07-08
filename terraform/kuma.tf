resource "proxmox_lxc" "kuma" {
  target_node     = var.proxmox_instance
  hostname        = "kuma"
  ostemplate      = "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
  unprivileged    = true
  ostype          = "ubuntu"
  ssh_public_keys = file(var.pub_ssh_key)
  start           = true
  onboot          = true
  vmid            = var.kuma_lxcid

  features {
    nesting = true
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
    ip6    = "auto"
    hwaddr = var.kuma_mac
  }

  lifecycle {
    ignore_changes = [
      mountpoint[0].storage
    ]
  }
}
