resource "proxmox_lxc" "kafka" {
  target_node     = var.proxmox_instance
  hostname        = "kafka"
  cores           = 4
  memory          = 8192
  ostemplate      = "storage:vztmpl/almalinux-9-sshd-enabled_20221108_amd64.tar.gz"
  unprivileged    = true
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
