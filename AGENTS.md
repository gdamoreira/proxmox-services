# Proxmox Services — Project Context

## Two-Repo Architecture

This repo (**proxmox-services**) contains the **Terraform + Ansible** provisioning pipeline. The sibling repo **homelab** (`../homelab`) is the **documentation layer** — service docs, hardware inventory, and network topology.

### Repo responsibilities

- **proxmox-services** — Terraform (.tf) per service, Ansible roles + playbooks, `AI.md` with roadmap
- **homelab** — service docs under `docs/`, hardware inventory (`hardware.md`), network topology tables

## Service Provisioning Status

Current services defined in `terraform/`:

| Service | LXC ID | IP | Terraform | Ansible | Docs (in homelab) |
|---|---|---|---|---|---|
| Traefik | 500 | 10.0.0.8 | ✅ traefik.tf | ✅ | ✅ essentials/traefik.md |
| Harbor | 501 | 10.0.20.4 | ✅ harbor.tf | ✅ | ✅ core-services/harbor.md |
| Kafka | 502 | 10.0.20.11 | ✅ kafka.tf | ✅ | ✅ core-services/kafka.md |
| Plex | 503 | 10.0.5.1 | ✅ plex.tf | ✅ | ✅ utilities/plex.md |
| Kuma | 504 | 10.0.0.9 | ✅ kuma.tf | ✅ | ✅ essentials/kuma.md |
| Mangareader | 505 | 10.0.5.2 | ✅ suwayomi.tf | ✅ | ✅ utilities/suwayomi.md |
| Coder | 506 | 10.0.10.2 | ✅ coder.tf | ✅ | ✅ utilities/coder.md |
| Pihole | 507 | 10.0.0.3 | ✅ pihole.tf | pending | ❌ |
| SSO (Keycloak) | 508 | 10.0.0.5 | ✅ sso.tf | pending | ✅ essentials/keycloak.md |
| GitLab | 509 | 10.0.20.3 | ✅ gitlab.tf | pending | ✅ core-services/gitlab.md |

### Next services to implement (docs exist in homelab, no provisioning yet)

- Docker (10.0.20.1), Heimdall (10.0.20.2), Nexus (10.0.20.5), TeamCity (10.0.20.6)
- Trillium (10.0.20.7), MongoDB (10.0.20.8), PostgreSQL (10.0.20.9), Redis (10.0.20.10), Axon Server (10.0.20.12)

## Documentation Sync Rule

Whenever you change Terraform or Ansible, the matching doc in `../homelab/docs/` must be updated.

| If you change... | Then update in ../homelab... |
|---|---|
| `terraform/*.tf` (IP, LXC ID, resources) | `docs/<category>/<service>.md` (IP, hostname, location) |
| `ansible/playbooks/*.yml` or `roles/*/` (config, ports, vars) | `docs/<category>/<service>.md` (setup flow, env vars) |
| `README.md` service tables | `../homelab/README.md` service tables |
| `AI.md` (new shipped feature) | `../homelab/README.md` (update status) |

### Implementation checklist for a new service

1. Create `terraform/<service>.tf` (copy pattern from an existing one like `kuma.tf`)
2. Add static IP, MAC, LXC ID to `variables.tf`
3. Create `ansible/playbooks/<service>.yml` and `ansible/roles/<service>/`
4. Add host to `ansible/production` inventory
5. Run `terraform apply` then `ansible-playbook`
6. Create/update `../homelab/docs/<category>/<service>.md`
7. Update service tables in both `README.md` files

## Patterns

- Most services follow: Terraform (Ubuntu 22.04 LXC) → Ansible (Docker Compose via `community.docker.docker_compose_v2`)
- Exceptions: Traefik (binary+systemd), Harbor (offline installer), Kafka (tarball+KRaft+systemd)
- VM-based services (GitLab Omnibus) need special treatment — not a simple LXC template
- All host_vars are identical — consider `group_vars/all.yml`
