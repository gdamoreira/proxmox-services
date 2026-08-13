resource "proxmox_lxc" "coder" {
  provider        = proxmox.secondary
  target_node     = var.proxmox_secondary_instance
  hostname        = "coder"
  cores           = 4
  memory          = 2048
  swap            = 512
  ostemplate      = "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
  unprivileged    = false
  ostype          = "debian"
  start           = true
  onboot          = true
  vmid            = var.coder_lxcid
  tags            = "coding;debian;ide;os;vscode"

  features {
    nesting = true
  }

  rootfs {
    storage = "local-lvm"
    size    = "8G"
  }

  network {
    name   = "eth0"
    bridge = "vmbr0"
    gw     = var.gateway_ip
    ip     = var.coder_ip
    ip6    = "auto"
    hwaddr = var.coder_mac
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
