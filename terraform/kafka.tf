resource "proxmox_lxc" "kafka" {
  provider        = proxmox.secondary
  target_node     = var.proxmox_secondary_instance
  hostname        = "kafka"
  cores           = 4
  memory          = 8192
  ostemplate      = "local:vztmpl/almalinux-9-default_20240911_amd64.tar.xz"
  unprivileged    = false
  ostype          = "centos"
  ssh_public_keys = file(var.pub_ssh_key)
  start           = true
  onboot          = true
  vmid            = var.kafka_lxcid
  password        = "necro1"
  
  features {
    keyctl        = true
    nesting       = true
  }

  // Terraform will crash without rootfs defined
  rootfs {
    storage = "local-lvm"
    size    = "60G"
  }

  network {
    name   = "eth0"
    bridge = "vmbr0"
    gw     = var.gateway_ip
    ip     = var.kafka_ip
    ip6    = "auto"
    hwaddr = var.kafka_mac
  }

  lifecycle {
    ignore_changes = [
      mountpoint[0].storage
    ]
  }
}
