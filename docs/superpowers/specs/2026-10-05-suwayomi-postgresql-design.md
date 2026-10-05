# Suwayomi H2 → PostgreSQL Migration Design Specification

- **Date:** 2026-10-05
- **Author:** damoreira & opencode
- **Status:** Draft
- **Target Environment:** Proxmox VE LXC 103 (`suwayomi`, `10.0.5.2`)

---

## 1. Executive Summary

Migrate the self-hosted Suwayomi manga reader from its embedded **H2** database (`/var/suwayomi/files/database.mv.db`, ~541 MB) to a **PostgreSQL** instance running as a localhost-only Docker sidecar in the same LXC. Data is moved with Suwayomi's own Tachiyomi-protobuf backup/restore mechanism, because there is no automatic H2→PostgreSQL data migration. The H2 database is **never modified or deleted**, so rollback is a configuration revert rather than a data restore.

The work spans three layers:

1. **Infrastructure (Terraform):** increase LXC memory `4096 → 8192` MiB for JVM + PostgreSQL headroom.
2. **Configuration (Ansible):** add a `postgresql` service and `DATABASE_*` environment variables to the Suwayomi compose; redesign the backup/restore scripts around `pg_dump`/`pg_restore`.
3. **Operations:** a tested, scripted rollback to H2; verification gates; a documented runbook.

Downtime is acceptable for the switch; there is no requirement to stay live during migration.

---

## 2. Current State

| Item | Value |
|---|---|
| LXC | 103 (`suwayomi`) on PVE, privileged, Debian 12 |
| IP / subdomain | `10.0.5.2` / `mangareader.damoreira.ml` |
| Compose dir | `/root/suwayomi/` |
| Data dir | `/var/suwayomi/files` (1.7 GB total) |
| Database | **H2** — `database.mv.db` (~541 MB) at `/var/suwayomi/files/database.mv.db` |
| Downloads | NFSv4 `10.0.10.1:/volume1/codex/applications/suwayomi/downloads` |
| Containers | `suwayomi-suwayomi-1` (`ghcr.io/suwayomi/suwayomi-server:preview`), `flaresolverr` |
| Networking | `network_mode: host` (required: FlareSolverr at `127.0.0.1:8191`) |
| LXC memory | `4096` MiB, `swap 1024` (`terraform/suwayomi.tf`) |
| Auth | `server.authMode = NONE` (API reachable without credentials on localhost) |
| Built-in auto-backup | Daily `.tachibk` into `/var/suwayomi/files/backups/`, TTL 60 days |
| Existing backup | `ansible/roles/backup/templates/backup-suwayomi.sh.j2` — tars `files/` (minus `downloads`) to codex NFS |

### 2.1 Suwayomi database support (researched)

- PostgreSQL is supported via `server.databaseType = POSTGRESQL` + `databaseUrl` / `databaseUsername` / `databasePassword`. **Beta** as of Aug 2025 (PR #1617).
- **No automatic H2→PostgreSQL data migration.** On startup the server only runs schema migrations to create an empty schema in the target database.
- **DB connection settings are excluded from backups**, but general *server settings* ARE included when `autoBackupIncludeServerSettings=true` — restoring such a backup can reset `databaseType` back to `H2`. Mitigation is required (see §5).
- Env vars (e.g. `DATABASE_TYPE`) **override** stored settings on every container start.
- REST API (verified against the live instance): `GET /api/v1/backup/export` returns an octet-stream `.tachibk`; `POST /api/v1/backup/import` accepts one in the body; `POST /api/v1/backup/validate` validates.

---

## 3. Goals & Non-Goals

**Goals**
- Run PostgreSQL locally (Docker sidecar) and configure Suwayomi to use it.
- Preserve all library data: manga, categories, chapters, tracking, history, client data, server/user settings.
- Guarantee **no data loss** on failure and provide **easy, scripted rollback**.
- Update backup and restore scripts and the Ansible restore path to the new database.
- Keep everything reproducible via Terraform + Ansible.

**Non-Goals**
- No dedicated standalone PostgreSQL service/LXC (roadmap `10.0.20.9`) — a sidecar is chosen.
- No change to FlareSolverr, downloads/NFS, extensions, or web UI.
- No migration of the *built-in* `.tachibk` auto-backup schedule (it stays as a supplementary layer).

---

## 4. Target Architecture

### 4.1 Compose additions (`/root/suwayomi/docker-compose.yml`)

A `postgresql` service added to the existing compose (host networking preserved):

- Image: `postgres:18` (pin major; do not use a floating tag).
- `PGDATA=/data/postgres`; volume `/var/suwayomi/postgres:/data/postgres`.
- `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` from env (secrets in Ansible vars, repo convention).
- `shm_size: 1g`.
- `command: ["-c", "listen_addresses=127.0.0.1"]` → reachable only via loopback.
- Healthcheck: `pg_isready -U $POSTGRES_USER -d $POSTGRES_DB`, interval 10s, retries 5.
- `restart: unless-stopped`.

Suwayomi service gains:

| Variable | Value |
|---|---|
| `DATABASE_TYPE` | `POSTGRESQL` |
| `DATABASE_URL` | `postgresql://127.0.0.1:5432/suwayomi` |
| `DATABASE_USERNAME` | `suwayomi` |
| `DATABASE_PASSWORD` | (secret var) |
| `USE_HIKARI_CONNECTION_POOL` | `true` |

`depends_on: postgresql: {condition: service_healthy, restart: true}`.

### 4.2 Terraform

`terraform/suwayomi.tf`: `memory = 4096 → 8192` (swap unchanged at `1024` or raised if needed).

### 4.3 Variables (Ansible)

`ansible/roles/suwayomi/vars/default.yml` gains: `suwayomi_pg_image`, `suwayomi_pg_user`, `suwayomi_pg_password`, `suwayomi_pg_db`, `suwayomi_pg_data_dir`, `suwayomi_pg_port`. Password stored per existing repo convention (plain var; note in docs).

---

## 5. Migration Procedure (in-place, downtime accepted)

All steps run from the PVE host via `pct exec 103` or SSH to `10.0.5.2`.

**Phase A — Protect (no changes yet)**
1. **L1 — application-consistent export:** `curl -s http://127.0.0.1:4567/api/v1/backup/export -o /var/suwayomi/suwayomi-pre-pg-<date>.tachibk`; validate with `POST /api/v1/backup/validate` (or `curl` body import on a scratch check). Copy to codex (`codex/server-backups/suwayomi/migration/<date>/`).
2. **L2 — raw snapshot:** stop the stack (`docker compose stop`); `tar` the entire `/var/suwayomi/files` (including `database.mv.db`) + `server.conf` + `docker-compose.yml` → codex; then `docker compose start` again (or leave stopped until Phase B).
3. **L3 — exact-state copy:** copy the current `docker-compose.yml` to `docker-compose.h2.bak` on the LXC.
4. Record **pre-migration counts** via the API/DB (manga, categories, chapters, history) into the spec/plan for later comparison.
5. Verify each backup's size and readability; confirm `database.mv.db` is present in the tar.

**Phase B — Switch**
6. Stop the stack (`docker compose down`).
7. Apply Terraform memory bump and `terraform apply`.
8. Deploy the updated compose (with PG service + `DATABASE_*` env) via Ansible; pull images.
9. `docker compose up -d postgresql`; wait for healthcheck.
10. `docker compose up -d suwayomi` → Suwayomi connects to empty PG and runs schema migrations.
11. Wait until the API is up (`curl http://127.0.0.1:4567/api/v1/backup/export` returns 200).

**Phase C — Restore data**
12. Import the L1 export: `curl -s -X POST --data-binary @suwayomi-pre-pg-<date>.tachibk http://127.0.0.1:4567/api/v1/backup/import`.
13. **Re-assert DB type (chosen approach):** the L1 export is created with **default flags** (server settings included), which may carry `databaseType=H2`. Immediately after import, restart the Suwayomi container so the `DATABASE_TYPE=POSTGRESQL` env var overrides the stored value on startup. Confirm via `server.conf` / settings API that the active DB is PostgreSQL. (If a backup flag to exclude server settings is confirmed available, prefer it and import settings separately — but the restart remains mandatory as a safety net.)

**Phase D — Verify (gates)**
14. Post-import counts match pre-migration counts (§5 step 4).
15. Web UI at `mangareader.damoreira.ml` loads the library; spot-check several manga detail pages and reading history.
16. `database.mv.db` is still present and untouched.

---

## 6. Rollback

### 6.1 Mechanism
Because the H2 database and its config are never modified, rollback is a **configuration revert + restart**:

1. Stop the stack.
2. Restore `docker-compose.h2.bak` → `docker-compose.yml` (removes `DATABASE_*` env and the PG service from Suwayomi's path).
3. Stop/remove the `postgresql` container. **Keep the volume** (`/var/suwayomi/postgres`) for post-mortem.
4. `docker compose up -d` → Suwayomi starts on the original H2 file.
5. Verify library loads (same gates as §5 Phase D).

If the H2 files were somehow affected, restore the L2 tar back into `/var/suwayomi/files`.

### 6.2 Automation
- Committed script `ansible/roles/suwayomi/templates/rollback-suwayomi-h2.sh.j2` deployed to `/usr/local/bin/rollback-suwayomi-h2.sh` implementing steps 1–4, with a confirmation prompt and clear output.
- **Rollback drill:** before the production switch, run the rollback script once and confirm Suwayomi returns on H2. The drill is part of the verification, not optional.

---

## 7. Backup & Restore Redesign (post-migration)

### 7.1 `backup-suwayomi.sh.j2`
- **Database:** `docker exec postgresql pg_dump -Fc -U suwayomi suwayomi > /tmp/suwayomi-db-<date>.dump`; copy to `codex/server-backups/suwayomi/`.
- **Config/data:** `tar` `/var/suwayomi/files` **excluding** `downloads/`, `database.mv.db*`, and `backups/`; copy to codex.
- Retain existing daily cron (03:00) / NFS mount pattern.
- Add a checksum and a non-empty assertion before declaring success.
- Apply the `backup_retention_days` (56) pruning convention where practical.

### 7.2 New `restore-suwayomi.sh.j2`
- Inputs: a `.dump` and a config tar (default: latest on codex; overridable).
- Steps: stop Suwayomi → `dropdb`/`createdb` (or drop schema) → `pg_restore -Fc` the dump → restore config tar → start → health check.
- Destructive-action confirmation.

### 7.3 Ansible restore path
- Update `ansible/roles/suwayomi/tasks/main.yml` `--tags restore` tasks: replace the "unarchive H2 into files/" logic with the PG restore flow (`pg_restore`) and config tar placement.
- New vars: `suwayomi_restore_dump_src`, `suwayomi_restore_config_src`.

### 7.4 Docs
- Update `../homelab/docs/utilities/suwayomi.md`: database section (PostgreSQL, localhost sidecar, version), data table, backup/restore scripts, rollback runbook, and the H2→PG migration note.
- Update `proxmox-services/README.md` and `../homelab/README.md` service tables if they reference the database.

---

## 8. Verification Summary

| Gate | How |
|---|---|
| Backups valid | `.tachibk` validates; tar extracts; H2 file present |
| PG reachable only locally | connect from LXC loopback works; LAN `10.0.5.2:5432` refused |
| Schema created | PG `\dt` shows Suwayomi tables after first start |
| Data fidelity | post-import counts == pre-migration counts |
| App health | Web UI library + detail pages load |
| Settings not reverted | active DB is PostgreSQL after restart |
| Backup works | `pg_dump` file produced and restores into a scratch DB |
| Restore works | scratch restore drill passes |
| **Rollback works** | rollback drill returns Suwayomi to H2 |

---

## 9. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| PostgreSQL support is beta | Verify app thoroughly (§8); rollback is one script away; H2 intact |
| Restore resets `databaseType` to H2 | Exclude server settings from export, or restart to re-assert env; env overrides on start |
| Disk pressure (1.7 GB data + PG) | 77 GB free on LXC; clean stale H2 backups after verification |
| Memory pressure (JVM + PG on 4 GB) | Terraform bump to 8192 MiB; `shm_size 1g` |
| `.tachibk` import corruption (known flaky reports) | Validate before import; retain L2 raw snapshot |
| Secret handling | Follow existing repo convention (plain `vars/default.yml`); document it |
| LXC stop/start not needed | Memory change may require LXC restart — schedule within the same window |

---

## 10. Decisions Deferred to Implementation

- **Export flags:** start with the default `.tachibk` export (server settings included) and rely on the mandatory post-import restart to re-assert `DATABASE_TYPE=POSTGRESQL`. If the running API exposes a server-settings exclusion flag, adopt it as an improvement; it is not required for correctness.
- **H2 file retirement:** keep `database.mv.db*` in place for at least 30 days after a successful switch; then archive-only to codex (never delete from the LXC without an explicit decision).

---

## 11. References

- Suwayomi-Server config docs: `docs/Configuring-Suwayomi‐Server.md`
- Suwayomi-Server-docker example: `docker-compose-postgresql.yml`
- Suwayomi backup/restore API: `BackupController.kt`, `BackupMutation.kt`
- CHANGELOG: "PostgreSQL Support!" (beta)
