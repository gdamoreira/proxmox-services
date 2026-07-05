variable "proxmox_api_url" {
  description = "The Proxmox API URL"
  type        = string
  default     = "https://10.0.30.1:8006/api2/json"
}

variable "proxmox_instance" {
  description = "The Proxmox Instance name"
  type        = string
  default     = "pve"
}

variable "proxmox_user" {
  description = "The Proxmox user"
  type        = string
  default     = "root@pam"
}

variable "proxmox_password" {
  description = "The Proxmox user password"
  type        = string
  default     = "necro1"
}

variable "pub_ssh_key" {
  description = "Public SSH key for passwordless login/Ansible admining"
  type        = string
  default     = "~/.ssh/id_ed25519_damoreira.pub"
}

variable "gateway_ip" {
  description = "LXC gateway IP"
  type        = string
  default     = "10.0.0.1"
}

//
// Services variables
//

// traefik
variable "traefik_lxcid" {
  type    = number
  default = 500
}

variable "traefik_mac" {
  type    = string
  default = "B6:1A:E1:C6:86:03"
}

variable "traefik_ip" {
  type    = string
  default = "10.0.30.4/16"
}

// harbor
variable "harbor_lxcid" {
  type    = number
  default = 501
}

variable "harbor_mac" {
  type    = string
  default = "F0:C3:FC:64:76:4F"
}

variable "harbor_ip" {
  type    = string
  default = "10.0.0.8/16"
}

// kafka
variable "kafka_lxcid" {
  type    = number
  default = 502
}

variable "kafka_mac" {
  type    = string
  default = "3C:04:E2:CB:DB:48"
}

variable "kafka_ip" {
  type    = string
  default = "10.0.20.11/16"
}

// plex
variable "plex_lxcid" {
  type    = number
  default = 503
}

variable "plex_mac" {
  type    = string
  default = "BA:7A:1E:D5:90:12"
}

variable "plex_ip" {
  type    = string
  default = "10.0.5.1/16"
}