resource "proxmox_lxc" "gitlab" {
  provider        = proxmox.secondary
  target_node     = var.proxmox_secondary_instance
  hostname        = "gitlab"
  cores           = 4
  memory          = 4096
  ostemplate      = "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
  unprivileged    = true
  ostype          = "ubuntu"
  ssh_public_keys = file(var.pub_ssh_key)
  start           = true
  onboot          = true
  vmid            = var.gitlab_lxcid

  features {
    nesting = true
  }

  rootfs {
    storage = "local-lvm"
    size    = "30G"
  }

  network {
    name   = "eth0"
    bridge = "vmbr0"
    gw     = var.gateway_ip
    ip     = var.gitlab_ip
    ip6    = "auto"
    hwaddr = var.gitlab_mac
  }

  lifecycle {
    ignore_changes = [
      mountpoint[0].storage
    ]
  }
}
