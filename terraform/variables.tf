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

variable "proxmox_secondary_api_url" {
  description = "The secondary Proxmox API URL"
  type        = string
  default     = "https://10.0.0.2:8006/api2/json"
}

variable "proxmox_secondary_instance" {
  description = "The secondary Proxmox node name"
  type        = string
  default     = "pve"
}

variable "proxmox_secondary_user" {
  description = "The secondary Proxmox user"
  type        = string
  default     = "root@pam"
}

variable "proxmox_secondary_password" {
  description = "The secondary Proxmox user password"
  type        = string
  default     = "necro1"
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
  default = "10.0.0.8/16"
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
  default = "10.0.20.4/16"
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

// kuma
variable "kuma_lxcid" {
  type    = number
  default = 504
}

variable "kuma_mac" {
  type    = string
  default = "8A:3B:F1:29:47:CE"
}

variable "kuma_ip" {
  type    = string
  default = "10.0.0.9/16"
}

// mangareader
variable "mangareader_lxcid" {
  type    = number
  default = 505
}

variable "mangareader_mac" {
  type    = string
  default = "7A:2B:E0:18:36:DA"
}

variable "mangareader_ip" {
  type    = string
  default = "10.0.5.2/16"
}

// coder
variable "coder_lxcid" {
  type    = number
  default = 506
}

variable "coder_mac" {
  type    = string
  default = "4C:9A:FD:27:51:BF"
}

variable "coder_ip" {
  type    = string
  default = "10.0.10.2/16"
}

// pihole
variable "pihole_lxcid" {
  type    = number
  default = 507
}

variable "pihole_mac" {
  type    = string
  default = "1E:5F:73:3B:AC:88"
}

variable "pihole_ip" {
  type    = string
  default = "10.0.0.3/16"
}

// sso
variable "sso_lxcid" {
  type    = number
  default = 508
}

variable "sso_mac" {
  type    = string
  default = "9D:8C:42:11:E6:64"
}

variable "sso_ip" {
  type    = string
  default = "10.0.0.5/16"
}

// gitlab
variable "gitlab_lxcid" {
  type    = number
  default = 509
}

variable "gitlab_mac" {
  type    = string
  default = "6A:3E:2C:18:47:AB"
}

variable "gitlab_ip" {
  type    = string
  default = "10.0.20.3/16"
}