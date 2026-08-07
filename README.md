# Proxmox Services

Terraform + Ansible pipeline to provision and configure self-hosted services on Proxmox VE.

## Architecture

Two-phase deployment:

1. **Terraform** — creates LXC containers on Proxmox with static IPs, SSH keys, and resource limits
2. **Ansible** — configures each container (packages, configs, services)

### Services

| Service | IP | LXC ID | Provisioned | Purpose |
|---------|----|--------|-------------|---------|
| Traefik | 10.0.0.8/16 | 500 | ✅ | Reverse proxy / TLS termination |
| Harbor | 10.0.20.4/16 | 501 | ✅ | Private container registry |
| Kafka | 10.0.20.11/16 | 502 | ✅ | Event streaming |
| Plex | 10.0.5.1/16 | 503 | ✅ | Media server + Docker stack |
| Jellyfin | 10.0.5.4/16 | 504 | ❌ | Open-source media server |
| Ghost | 10.0.5.5/16 | 510 | ❌ | Personal blog |
| Immich | 10.0.5.6/16 | 511 | ✅ | Photo/video backup |

### Full Topology

| IP | Hostname | Service | Location |
|----|----------|---------|----------|
| 10.0.0.3 | pihole | Pi-hole | |
| 10.0.0.4 | idrac | iDRAC (Dell R820 mgmt) | Hypervisor 1 |
| 10.0.0.5 | sso | Keycloak | |
| 10.0.0.6 | alfred | Home Assistant | Hypervisor 3 |
| 10.0.0.7 | cf | Cloudflare Tunnel | Hypervisor 2 |
| 10.0.0.8 | traefik | Traefik | Hypervisor 2 |
| 10.0.0.9 | kuma | Uptime Kuma | Hypervisor 2 |
| 10.0.5.1 | plex | Plex + Media Stack | |
| 10.0.5.2 | mangareader | Suwayomi | Hypervisor 2 |
| 10.0.5.3 | torrent | Transmission | Hypervisor 1 |
| 10.0.5.4 | jellyfin | Jellyfin | Hypervisor 1 |
| 10.0.5.5 | ghost | Ghost | Hypervisor 1 |
| 10.0.5.6 | immich | Immich | Hypervisor 1 |
| 10.0.10.1 | codex | Synology NAS | Synology NAS |
| 10.0.10.2 | coder | Coder IDE | Hypervisor 1 |
| 10.0.20.1 | docker | Docker host | |
| 10.0.20.2 | heimdall | Heimdall dashboard | |
| 10.0.20.3 | gitlab | GitLab | |
| 10.0.20.4 | harbor | Harbor | |
| 10.0.20.5 | nexus | Nexus | |
| 10.0.20.6 | teamcity | TeamCity | |
| 10.0.20.7 | trillium | Trillium Notes | |
| 10.0.20.8 | mongo | MongoDB | |
| 10.0.20.9 | postgres | PostgreSQL | |
| 10.0.20.10 | redis | Redis | |
| 10.0.20.11 | kafka | Kafka | |
| 10.0.20.12 | axon | Axon Server | |

## Terraform

Provision LXC containers on Proxmox.

```bash
cd terraform
terraform init
terraform apply
```

Destroy a specific container:

```bash
terraform destroy -target=proxmox_lxc.traefik
```

## Ansible

Configure services after provisioning.

```bash
cd ansible
ansible-playbook ./playbooks/traefik.yml
ansible-playbook ./playbooks/harbor.yml
ansible-playbook ./playbooks/kafka.yml
ansible-playbook ./playbooks/plex.yml
```

Or run all:

```bash
ansible-playbook site.yml
```

## Plex Media Stack

The Plex LXC runs a full Docker Compose media stack managed via Ansible:

- **Plex** — media server (host networking)
- **Tautulli** — monitoring & analytics
- **Sonarr / Radarr** — TV & movie automation
- **Bazarr** — subtitle management
- **Prowlarr** — centralized indexers
- **qBittorrent** — download client
- **Tdarr** — media optimization
- **Overseerr** — media requests
- **Kometa** — collections & overlays
- **Watchtower** — automatic container updates
- **Homepage** — service dashboard
- **Uptime Kuma** — health monitoring
- **Dozzle** — Docker log viewer

Stack deployed to `/srv/media-stack/` on the Plex LXC. Media expected at `/mnt/storage/`.

### Claim Token

Before first run, obtain a Plex claim token:

```bash
ansible-playbook ./playbooks/plex.yml -e plex_claim_token=claim-xxxx
```

## Cloudflare Tunnel

All external traffic enters through a Cloudflare Tunnel running on `10.0.0.7` (token-based). The tunnel forwards `https://<hostname>.damoreira.ml` to Traefik at `10.0.0.8:443`.

**Important: every ingress rule targeting Traefik by IP must set `noTLSVerify: true`.**

Since the tunnel connects to Traefik via its IP (`10.0.0.8`) rather than the domain name, the Let's Encrypt certificate (issued for `*.damoreira.ml`) will not match. Without `noTLSVerify`, cloudflared rejects the connection with:

```
tls: failed to verify certificate: x509: cannot validate certificate for 10.0.0.8 because it doesn't contain any IP SANs
```

This is configured per-hostname in the **Cloudflare Zero Trust Dashboard** → Access → Tunnels → tunnel → Edit ingress rule → `noTLSVerify: true`.

## SSL / Certificates

Wildcard certificate for `*.damoreira.ml` via ACME DNS with Let's Encrypt.

```bash
apt install certbot
wget https://github.com/joohoi/acme-dns-certbot-joohoi/raw/master/acme-dns-auth.py -O /etc/letsencrypt/acme-dns-auth2.py
chmod +x /etc/letsencrypt/acme-dns-auth.py
sed -i ''-e '1s:#!/usr/bin/env python:#!/usr/bin/env python3:' /etc/letsencrypt/acme-dns-auth.py
echo "Follow the instructions and update DNS CNAME in CloudFlare..."
certbot certonly --manual --manual-auth-hook /etc/letsencrypt/acme-dns-auth.py --rsa-key-size 4096 --preferred-challenges dns --debug-challenges -d \*.damoreira.ml -d damoreira.ml

_IN=/etc/letsencrypt/live/damoreira.ml/fullchain.pem
_OUT=~/traefik_certificate
cat $_IN | base64 | tr '\n' ' ' | sed --expression='s/\ //g' > $_OUT

_IN=/etc/letsencrypt/live/damoreira.ml/privkey.pem
_OUT=~/traefik_key
cat $_IN | base64 | tr '\n' ' ' | sed --expression='s/\ //g' > $_OUT

echo "Update /etc/traefik/acme.json and add the following certificate:"
echo '{
  "domain": {
    "main": "example.com"
  },
  "certificate": "<certificate>",
  "key": "<key>",
  "Store": "default"
}'
```

## Directory Structure

```
├── terraform/
│   ├── versions.tf          # Provider config
│   ├── providers.tf         # Proxmox connection
│   ├── variables.tf         # IPs, MACs, LXC IDs
│   ├── traefik.tf           # Traefik LXC
│   ├── harbor.tf            # Harbor LXC
│   ├── kafka.tf             # Kafka LXC
│   ├── plex.tf              # Plex LXC
│   ├── coder.tf             # Coder LXC
│   ├── pihole.tf            # Pi-hole LXC
│   ├── sso.tf               # Keycloak LXC
│   ├── gitlab.tf            # GitLab LXC
│   ├── suwayomi.tf          # Suwayomi LXC
│   ├── jellyfin.tf          # Jellyfin LXC
│   ├── ghost.tf             # Ghost LXC
│   └── immich.tf            # Immich LXC
│
├── ansible/
│   ├── ansible.cfg
│   ├── production           # Inventory
│   ├── site.yml             # Master playbook
│   ├── playbooks/
│   │   ├── traefik.yml
│   │   ├── harbor.yml
│   │   ├── kafka.yml
│   │   ├── plex.yml
│   │   ├── coder.yml
│   │   ├── pihole.yml
│   │   ├── sso.yml
│   │   ├── suwayomi.yml
│   │   ├── jellyfin.yml
│   │   ├── ghost.yml
│   │   └── immich.yml
│   ├── roles/
│   │   ├── common/          # OS upgrades + base packages
│   │   ├── traefik/         # Traefik binary + config
│   │   ├── harbor/          # Harbor offline installer
│   │   ├── kafka/           # Kafka tarball
│   │   ├── plex/            # Docker + Compose media stack
│   │   ├── jellyfin/        # Jellyfin Docker Compose
│   │   ├── ghost/           # Ghost Docker Compose
│   │   ├── immich/          # Immich Docker Compose
│   │   ├── backup/          # CIFS backup systemd timer
│   └── host_vars/
│
├── AI.md                    # Project intelligence & roadmap
└── README.md
```
