# Proxmox Services — Overview

## What It Does

This project provisions and configures self-hosted infrastructure services on a Proxmox VE hypervisor using a two-phase pattern:

1. **Terraform** creates LXC containers (LXC IDs 500–503) on the Proxmox host with static IPs, SSH keys, and resource limits.
2. **Ansible** configures each container — installing software, writing configs, and starting services.

Currently deployed services:

| Service | IP | LXC ID | Purpose |
|---------|-----|--------|---------|
| Traefik | 10.0.0.8/16 | 500 | Reverse proxy / TLS termination / API gateway |
| Harbor | 10.0.20.4/16 | 501 | Private container image registry + vulnerability scanner |
| Plex | 10.0.5.1/16 | 503 | Media server |
| Kafka | 10.0.20.11/16 | 502 | Event streaming / message broker |

Traefik acts as the ingress layer, routing to services on the private network via file-based config. The domain `damoreira.ml` is used for external access with Let's Encrypt ACME certificates.

## Architecture & Patterns

### Phase 1: Terraform (Provisioning)

- Uses the `telmate/proxmox` provider to manage LXC containers declaratively
- Static IPs, MAC addresses, and LXC IDs are hardcoded via `variables.tf`
- Resources are split per service (`traefik.tf`, `harbor.tf`, `kafka.tf`, `plex.tf`) for clarity
- Plex follows the same template as Harbor (Ubuntu 22.04, `keyctl` + `nesting` features, 500GB rootfs for media)
- `lifecycle.ignore_changes` avoids diff churn on storage mountpoints

### Phase 2: Ansible (Configuration)

- **Inventory-driven**: `production` file groups hosts by role (`[traefik]`, `[harbor]`, `[kafka]`, `[plex]`)
- **Role-based playbooks**: each service has its own role under `roles/<service>/`
- **Playbooks are modular**: `site.yml` imports playbooks; each playbook applies `common` + service-specific roles
- **Templates + variables**: Jinja2 templates with `vars/default.yml` for version/URL management
- **Handlers**: Notify-based service restarts (traefik has working handlers; harbor/kafka have placeholders)
- **Docker Compose via Ansible**: The `plex` role installs Docker + Compose plugin natively, then deploys the full media stack through `community.docker.docker_compose_v2`. Config files (`.env`, `docker-compose.yml`, `kometa/config.yml`) are rendered from Jinja2 templates.

### Notable observations

- Kafka uses AlmaLinux 9 (dnf) while Traefik, Harbor, and Plex use Ubuntu 22.04 (apt)
- Three different deployment strategies exist side-by-side: Traefik as a binary+systemd, Harbor via its offline installer, Plex via Docker Compose managed by Ansible, and Kafka as a raw tarball
- The Plex LXC runs the entire media stack as Docker containers (Plex, Sonarr, Radarr, qBittorrent, etc.) — the LXC is a Docker host, not a single-service container
- All host_vars files are identical (just `ansible_python_interpreter: /usr/bin/python3`)

---

## Service Inventory

The following tables describe the complete intended service topology for the infrastructure. Services marked with `✅` are already provisioned on the specified hypervisor.

## Cloudflare Tunnel

A token-based Cloudflare Tunnel runs on `10.0.0.7` (LXC "cf", managed via systemd with `cloudflared tunnel run --token`). The tunnel ingress config is managed entirely through the **Cloudflare Zero Trust Dashboard** (not a local config file).

### ingress rules

All services route to Traefik at `10.0.0.8` with `noTLSVerify: true`. The tunnel was originally pointed at `10.0.1.1` (a retired server); during the July 2026 tunnel migration, all rules were updated to target `10.0.0.8` instead.

| Hostname | Service | Notes |
|----------|---------|-------|
| `notes.damoreira.ml` | `https://10.0.0.8` | formerly `http://10.0.0.10:7080` |
| `ifrit.damoreira.ml` | `https://10.0.0.8` | |
| `gitlab.damoreira.ml` | `https://10.0.0.8` | |
| `nexus.damoreira.ml` | `https://10.0.0.8` | |
| `harbor.damoreira.ml` | `https://10.0.0.8` | |
| `idrac.damoreira.ml` | `http_status:404` | intentionally blocked |
| `next.damoreira.ml` | `https://10.0.0.8` | |
| `plex.damoreira.ml` | `https://10.0.0.8` | was missing `noTLSVerify` (fixed July 2026) |
| `sso.damoreira.ml` | `https://10.0.0.8` | |
| `teamcity.damoreira.ml` | `https://10.0.0.8` | |
| `torrent.damoreira.ml` | `https://10.0.0.8` | |
| `pve.damoreira.ml` | `https://10.0.0.8` | |
| `gitlab-ssh.damoreira.ml` | `ssh://10.0.0.66:22` | SSH, not HTTPS |
| `mangareader.damoreira.ml` | `https://10.0.0.8` | |
| `traefik.damoreira.ml` | `https://10.0.0.8` | |
| `virtus.damoreira.ml` | `https://10.0.0.8` | |
| `alfred.damoreira.ml` | `https://10.0.0.8` | |
| `coder.damoreira.ml` | `https://10.0.0.8` | |
| catch-all | `http_status:404` | |

### noTLSVerify requirement

Every HTTPS ingress rule targeting `10.0.0.8` must set `noTLSVerify: true`. The tunnel connects to Traefik by IP, but Let's Encrypt certificates are issued for domain names — the certificate will **never** match the IP, so TLS verification must be skipped. If omitted, cloudflared logs:

```
tls: failed to verify certificate: x509: cannot validate certificate for 10.0.0.8 because it doesn't contain any IP SANs
```

### How to update

1. Go to https://one.dash.cloudflare.com/ → Access → Tunnels
2. Find the tunnel (token-based) — it may appear as "Quick Tunnel" or unnamed
3. Click "Configure" or edit the ingress rule for the hostname
4. Under `originRequest`, set `noTLSVerify: true`
5. The tunnel picks up changes automatically (new config version logged)

### Key details

- **Tunnel UUID**: `fd773a47-6b88-4b6b-954b-7a2804d02f09`
- **Account ID**: `f35d4be77ba9baaf6e235e1a0d90b3b1`
- **Config versions**: v48 fixed plex `noTLSVerify`, v49 fixed gitlab, v50-56 migrated all services from `10.0.1.1` → `10.0.0.8`

### 🔐 Essential Services

| Status | Service | Hostname | IP | Description | Subdomain | Location |
| ------ | ------- | -------- | --- | ----------- | --------- | -------- |
| | Pi-hole | pihole | 10.0.0.3 | DNS local e filtro | `pihole.damoreira.ml` | |
| ✅ | iDRAC | idrac | 10.0.0.4 | Gerenciamento do Dell R820 | N/A | Hypervisor 1 |
| | SSO (Keycloak) | sso | 10.0.0.5 | Autenticação centralizada | `sso.damoreira.ml` | |
| ✅ | Home Assistant | alfred | 10.0.0.6 | Automação residencial | `alfred.damoreira.ml` | Hypervisor 3 |
| ✅ | Cloudflare | cf | 10.0.0.7 | Tunnel | N/A | Hypervisor 2 |
| ✅ | Traefik | traefik | 10.0.0.8 | Reverse proxy e gateway | `traefik.damoreira.ml` | Hypervisor 2 |
| ✅ | Uptime Kuma | kuma | 10.0.0.9 | Uptime and monitoring | `kuma.damoreira.ml` | Hypervisor 2 |

### 🛠️ Utility Services

| Status | Service | Hostname | IP | Description | Subdomain | Location |
| ------ | ------- | -------- | --- | ----------- | --------- | -------- |
| ✅ | Plex | plex | 10.0.5.1 | Servidor de mídia | `plex.damoreira.ml` | |
| ✅ | Suwayomi | mangareader | 10.0.5.2 | Leitor de mangás | `mangareader.damoreira.ml` | Hypervisor 2 |
| ✅ | Transmission | torrent | 10.0.5.3 | Cliente torrent (Transmission) | `torrent.damoreira.ml` | Hypervisor 1 |

### 💾 Storage & Development

| Status | Service | Hostname | IP | Description | Subdomain | Location |
| ------ | ------- | -------- | --- | ----------- | --------- | -------- |
| ✅ | Codex Synology | codex | 10.0.10.1 | Servidor de storage | `codex.damoreira.ml` | Synology NAS |
| ✅ | Coder | coder | 10.0.10.2 | IDE self hosted | `coder.damoreira.ml` | Hypervisor 1 |

### 📦 Important Services (10.0.20.x)

| Status | Service | Hostname | IP | Description | Subdomain | Location |
| ------ | ------- | -------- | --- | ----------- | --------- | -------- |
| | Docker | docker | 10.0.20.1 | Host de containers | `docker.damoreira.ml` | |
| | Heimdall | heimdall | 10.0.20.2 | Dashboard de aplicações | `apps.damoreira.ml` | |
| | GitLab | gitlab | 10.0.20.3 | Plataforma DevOps completa | `gitlab.damoreira.ml` | |
| ✅ | Harbor | harbor | 10.0.20.4 | Registro de containers | `harbor.damoreira.ml` | |
| | Nexus | nexus | 10.0.20.5 | Gerenciador de artefatos | `nexus.damoreira.ml` | |
| | TeamCity | teamcity | 10.0.20.6 | Integração contínua | `ci.damoreira.ml` | |
| | Trillium | trillium | 10.0.20.7 | Notes / Personal Wiki | `notes.damoreira.ml` | |
| | MongoDB | mongo | 10.0.20.8 | Banco de dados NoSQL | `mongo.damoreira.ml` | |
| | PostgreSQL | postgres | 10.0.20.9 | Banco de dados relacional | `postgres.damoreira.ml` | |
| | Redis | redis | 10.0.20.10 | Cache e filas pub/sub | `redis.damoreira.ml` | |
| | Kafka | kafka | 10.0.20.11 | Plataforma de mensageria | `kafka.damoreira.ml` | |
| | Axon Server | axon | 10.0.20.12 | Event store para microsserviços | `axon.damoreira.ml` | |

---

## Recommended TODO

### Security
- [ ] **Move secrets out of source**: Passwords (`necro1`) are hardcoded in `variables.tf`, `harbor.yml.j2`, and `traefik.yml.j2`. Use Ansible Vault or Terraform variables with `sensitive = true`.
- [ ] **Remove hardcoded SSH key path** in `variables.tf:28` (`~/.ssh/id_ed25519_damoreira.pub`) — makes the repo machine-specific.
- [ ] **Disable Traefik debug/insecure API** (`api.insecure: true`, `log.level: DEBUG`) in `traefik.yml.j2` for production.
- [ ] **Harden Harbor passwords**: DB and admin passwords should not be `necro1`.

### Reliability
- [ ] **Fix Harbor handlers** (`roles/harbor/handlers/main.yml`): `docker_container` module usage is incorrect (no `name` field; `loop` references undefined `docker_images.stdout_lines`).
- [ ] **Remove duplicate Harbor template**: `roles/kafka/templates/harbor.yml.j2` — kafka should not have a harbor config template.
- [ ] **Add Kafka systemd service / handlers** — Kafka currently has no startup configuration; it's only downloaded and extracted.
- [ ] **Complete Kafka service configuration** (e.g., `server.properties` template) — only the binary is downloaded.
- [ ] **Fix inventory**: `10.0.0.8` is listed under both `[traefik]` and `[harbor]` in `production`. Should be aligned with actual LXC assignment.
- [ ] **Provide `plex_claim_token` and `kometa_plex_token`** at runtime or via Ansible Vault — these are required for Plex claim and Kometa to work.
- [ ] **Provision remaining services** from the service tables above, starting with the `10.0.20.x` subnet (Docker, Heimdall, GitLab, Nexus, TeamCity, etc.).

### Maintainability
- [ ] **Standardize OS images**: Mix of Ubuntu 22.04 and AlmaLinux 9 increases maintenance burden. Consider unifying.
- [ ] **Terraform state exposure**: `terraform.tfstate` in repo root should be `.gitignored` or moved to remote state (S3/backend).
- [ ] **Extract IP/MAC/LXC ID mapping** into a structured variable (e.g., `locals` map) instead of flat variables per service.
- [ ] **Consolidate host_vars**: All host_vars are identical — consider using `group_vars/all.yml` instead.
- [ ] **Idempotency for Harbor install**: `shell: ./harbor/install.sh` runs every time; add a `when: not harbor_downloaded.stat.exists` guard or use `creates`.
- [ ] **YAML linting**: Add `.yamllint` config and run `yamllint` in CI (`.yamllint` file exists but is unconfigured).
- [ ] **Keep AI.md in sync** with the actual state of the repo — update as new services are added or IPs change.

### CI / Automation
- [ ] **Add terraform fmt / validate** check in CI.
- [ ] **Add ansible-lint** check in CI.
- [ ] **Pin Ansible collection versions** in `requirements.yml`.
- [ ] **Add Makefile or Justfile** for common commands (`terraform apply`, `ansible-playbook`, lint, etc.).

### Documentation
- [ ] **Document network topology** — what IP ranges exist, VLANs, gateway, etc.
- [ ] **Add architecture diagram** (ascii or mermaid) showing how Traefik routes to services.
- [ ] **Document certbot / ACME DNS setup** in a self-contained script instead of README comments.
