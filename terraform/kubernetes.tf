resource "proxmox_vm_qemu" "k8s_node_01" {
  provider    = proxmox.secondary
  name        = "k8s-node-01"
  target_node = var.proxmox_secondary_instance
  vmid        = var.k8s_node_01_vmid
  clone       = "template-ubuntu"
  cores       = 4
  sockets     = 1
  memory      = 8192
  scsihw      = "virtio-scsi-pci"
  os_type     = "cloud-init"
  ipconfig0   = "ip=${var.k8s_node_01_ip},gw=${var.gateway_ip}"

  disk {
    size    = "50G"
    type    = "scsi"
    storage = "local-lvm"
  }

  network {
    model   = "virtio"
    bridge  = "vmbr0"
    macaddr = var.k8s_node_01_mac
  }

  sshkeys = file(var.pub_ssh_key)

  lifecycle {
    ignore_changes = [
      disk[0].storage,
    ]
  }
}

resource "proxmox_vm_qemu" "k8s_node_02" {
  provider    = proxmox.secondary
  name        = "k8s-node-02"
  target_node = var.proxmox_secondary_instance
  vmid        = var.k8s_node_02_vmid
  clone       = "template-ubuntu"
  cores       = 4
  sockets     = 1
  memory      = 8192
  scsihw      = "virtio-scsi-pci"
  os_type     = "cloud-init"
  ipconfig0   = "ip=${var.k8s_node_02_ip},gw=${var.gateway_ip}"

  disk {
    size    = "50G"
    type    = "scsi"
    storage = "local-lvm"
  }

  network {
    model   = "virtio"
    bridge  = "vmbr0"
    macaddr = var.k8s_node_02_mac
  }

  sshkeys = file(var.pub_ssh_key)

  lifecycle {
    ignore_changes = [
      disk[0].storage,
    ]
  }
}

resource "proxmox_vm_qemu" "k8s_node_03" {
  provider    = proxmox.secondary
  name        = "k8s-node-03"
  target_node = var.proxmox_secondary_instance
  vmid        = var.k8s_node_03_vmid
  clone       = "template-ubuntu"
  cores       = 4
  sockets     = 1
  memory      = 8192
  scsihw      = "virtio-scsi-pci"
  os_type     = "cloud-init"
  ipconfig0   = "ip=${var.k8s_node_03_ip},gw=${var.gateway_ip}"

  disk {
    size    = "50G"
    type    = "scsi"
    storage = "local-lvm"
  }

  network {
    model   = "virtio"
    bridge  = "vmbr0"
    macaddr = var.k8s_node_03_mac
  }

  sshkeys = file(var.pub_ssh_key)

  lifecycle {
    ignore_changes = [
      disk[0].storage,
    ]
  }
}
