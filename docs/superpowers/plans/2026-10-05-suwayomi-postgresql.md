# Suwayomi H2 → PostgreSQL Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move Suwayomi (LXC 103, `10.0.5.2`) from embedded H2 to a localhost-only PostgreSQL Docker sidecar without data loss, with scripted rollback and `pg_dump`-based backups.

**Architecture:** Add a `postgresql` service and `DATABASE_*` env vars to the existing Suwayomi compose, controlled by a single `suwayomi_db_type` Ansible var so switching/rolling back is one deterministic config change. Data is transferred with Suwayomi's `.tachibk` export/import API. H2 files are never modified.

**Tech Stack:** Terraform (Proxmox provider), Ansible, Docker Compose, PostgreSQL 18, Suwayomi REST backup API.

**Spec:** `docs/superpowers/specs/2026-10-05-suwayomi-postgresql-design.md`

## Global Constraints

- LXC: **103**, IP **10.0.5.2**, compose dir **/root/suwayomi/**, data dir **/var/suwayomi/files**.
- PostgreSQL image: **`postgres:18`** (pinned major). DB name/user: **suwayomi**. Data dir: **/var/suwayomi/postgres**.
- PG must listen on **127.0.0.1 only** (`-c listen_addresses=127.0.0.1`).
- LXC memory: **8192** MiB (from 4096).
- The H2 DB **`/var/suwayomi/files/database.mv.db` must never be modified or deleted** by this work.
- Backups go to codex: `10.0.10.1:/volume1/codex` mounted at `/mnt/backup`; service backups under `server-backups/suwayomi/`.
- Secrets follow the repo's existing plain-`vars/default.yml` convention.
- Every Terraform/Ansible change requires the matching `../homelab` doc update.
- Push commits to **both** remotes (`origin` and `github`).

## Execution Order

**Run Task 3 (pre-migration backups) FIRST, before Task 1 and Task 2** — a clean H2 snapshot must exist before any LXC resource change (a Terraform memory update can restart the LXC, and H2 corrupts on unclean shutdown). Nominal order: **3 → 1 → 2 → 4 → 5 → 6 → 7 → 8**.

## Review Focus

- Restore accidentally resets `databaseType=H2` from included server settings → active DB must be PostgreSQL after restart.
- PG reachable from the LAN instead of loopback only → must refuse `10.0.5.2:5432`.
- Rollback returns to H2 only if `DATABASE_TYPE=H2` is explicitly set → a stored PG value must not survive the revert.
- Backup silently writes an empty/corrupt dump → assert non-empty + checksum + restore drill.
- `.tachibk` import flakiness → validate before import and keep the raw H2 snapshot.

---

### Task 1: Terraform memory bump

**Files:**
- Modify: `terraform/suwayomi.tf` (memory line)

**Interfaces:**
- Consumes: nothing.
- Produces: LXC 103 with 8192 MiB RAM.

- [ ] **Step 1: Edit `terraform/suwayomi.tf`**

Change `memory = 4096` → `memory = 8192`.

- [ ] **Step 2: Apply**

Run: `terraform apply -auto-approve` (from `terraform/`)
Expected: plan shows only `memory` change on `proxmox_lxc.suwayomi`; apply succeeds. If Proxmox requires a stop/start, accept the brief reboot (data untouched).

- [ ] **Step 3: Verify**

Run: `sshpass -p necro1 ssh root@10.0.0.2 'pct config 103 | grep memory'`
Expected: `memory: 8192`.

- [ ] **Step 4: Commit**

```bash
git add terraform/suwayomi.tf
git commit -m "terraform: bump suwayomi LXC memory to 8192 for postgres"
```

---

### Task 2: Ansible compose + vars for PostgreSQL

**Files:**
- Modify: `ansible/roles/suwayomi/vars/default.yml`
- Modify: `ansible/roles/suwayomi/templates/docker-compose.yml.j2`

**Interfaces:**
- Consumes: Task 1.
- Produces: a compose that renders a `postgresql` service + `DATABASE_*` env when `suwayomi_db_type == 'postgres'`, and `DATABASE_TYPE=H2` when `suwayomi_db_type == 'h2'`. Vars `suwayomi_pg_*` available to later tasks.

- [ ] **Step 1: Add vars to `vars/default.yml`**

```yaml
suwayomi_db_type: "postgres"        # "postgres" | "h2" (h2 = rollback)
suwayomi_pg_image: "postgres:18"
suwayomi_pg_user: "suwayomi"
suwayomi_pg_db: "suwayomi"
suwayomi_pg_password: "<strong-secret>"
suwayomi_pg_port: 5432
suwayomi_pg_data_dir: "/var/suwayomi/postgres"
```

- [ ] **Step 2: Add `DATABASE_TYPE` env to the suwayomi service**

Always render `DATABASE_TYPE`; add URL/creds only in postgres mode:

```jinja
      - DATABASE_TYPE={{ 'POSTGRESQL' if suwayomi_db_type == 'postgres' else 'H2' }}
{% if suwayomi_db_type == 'postgres' %}
      - DATABASE_URL=postgresql://127.0.0.1:{{ suwayomi_pg_port }}/{{ suwayomi_pg_db }}
      - DATABASE_USERNAME={{ suwayomi_pg_user }}
      - DATABASE_PASSWORD={{ suwayomi_pg_password }}
      - USE_HIKARI_CONNECTION_POOL=true
{% endif %}
```

- [ ] **Step 3: Add the `postgresql` service (conditional) and `depends_on`**

```jinja
{% if suwayomi_db_type == 'postgres' %}
  postgresql:
    image: {{ suwayomi_pg_image }}
    network_mode: host
    command: ["-c", "listen_addresses=127.0.0.1", "-p", "{{ suwayomi_pg_port }}"]
    environment:
      - POSTGRES_USER={{ suwayomi_pg_user }}
      - POSTGRES_PASSWORD={{ suwayomi_pg_password }}
      - POSTGRES_DB={{ suwayomi_pg_db }}
      - PGDATA=/data/postgres
      - TZ={{ timezone }}
    volumes:
      - {{ suwayomi_pg_data_dir }}:/data/postgres
    shm_size: 1g
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U {{ suwayomi_pg_user }} -d {{ suwayomi_pg_db }} -p {{ suwayomi_pg_port }}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    restart: unless-stopped
{% endif %}
```

Add to the `suwayomi` service (postgres mode only):
```jinja
{% if suwayomi_db_type == 'postgres' %}
    depends_on:
      postgresql:
        condition: service_healthy
        restart: true
{% endif %}
```

- [ ] **Step 4: Create PG data dir in `tasks/main.yml`**

Add `{{ suwayomi_pg_data_dir }}` to the existing data-directories loop (created always, harmless).

- [ ] **Step 5: Verify template renders**

Run: `ansible-playbook playbooks/suwayomi.yml --check --diff`
Expected: renders without Jinja errors; diff shows the new service/env/dir. (Do NOT let check mode stop production.)

- [ ] **Step 6: Commit**

```bash
git add ansible/roles/suwayomi/vars/default.yml ansible/roles/suwayomi/templates/docker-compose.yml.j2 ansible/roles/suwayomi/tasks/main.yml
git commit -m "ansible: add postgresql sidecar + DATABASE_TYPE toggle to suwayomi"
```

---

### Task 3: Pre-migration backups (data-safety gate)

**Files:** none (operational). Artifacts to codex.

**Interfaces:**
- Consumes: live H2 instance.
- Produces: L1 `.tachibk`, L2 raw tar, L3 compose copy on codex/LXC; recorded pre-migration counts.

- [ ] **Step 1: Record pre-migration counts** (from the running H2 instance)

Run on `10.0.5.2`: export via API then note manga/category/chapter/history counts (via the WebUI API or DB). Save the numbers in the plan's execution log.

- [ ] **Step 2: L1 — application-consistent export**

```bash
curl -s http://127.0.0.1:4567/api/v1/backup/export -o /var/suwayomi/suwayomi-pre-pg-$(date +%F).tachibk
# validate (expects 200)
curl -s -o /dev/null -w "%{http_code}" -X POST --data-binary @/var/suwayomi/suwayomi-pre-pg-*.tachibk http://127.0.0.1:4567/api/v1/backup/validate
```

- [ ] **Step 3: L2 — raw snapshot (stop the stack first)**

```bash
cd /root/suwayomi && docker compose stop
tar czf /tmp/suwayomi-files-$(date +%F).tar.gz -C /var/suwayomi files
cp /root/suwayomi/docker-compose.yml /tmp/suwayomi-compose-$(date +%F).yml
```

- [ ] **Step 4: Copy artifacts to codex**

```bash
mkdir -p /mnt/backup/server-backups/suwayomi/migration/$(date +%F)
cp /tmp/suwayomi-*.tar.gz /tmp/suwayomi-compose-*.yml /var/suwayomi/suwayomi-pre-pg-*.tachibk /mnt/backup/server-backups/suwayomi/migration/$(date +%F)/
```

- [ ] **Step 5: Verify backups**

Run: `tar tzf /tmp/suwayomi-files-*.tar.gz | grep -c 'database.mv.db'` → `>= 1`.
Confirm `.tachibk` > 100 KB and validate returned **200**.

- [ ] **Step 6: L3 — preserve exact compose**

```bash
cp /root/suwayomi/docker-compose.yml /root/suwayomi/docker-compose.h2.bak
```

(No commit — artifacts live on codex/LXC.)

---

### Task 4: Switch to PostgreSQL and import data

**Files:** deployed by Ansible (Task 2).

**Interfaces:**
- Consumes: Task 2 compose template, Task 3 `.tachibk`.
- Produces: Suwayomi running on PostgreSQL with library data.

- [ ] **Step 1: Deploy new compose**

```bash
ansible-playbook playbooks/suwayomi.yml
```
Expected: compose updated; `postgresql` service created; data dir exists.

- [ ] **Step 2: Start PG, then Suwayomi**

```bash
ssh root@10.0.5.2 'cd /root/suwayomi && docker compose up -d postgresql && sleep 20 && docker compose up -d suwayomi'
```
Expected: `postgresql` healthy; `suwayomi` starts against PG.

- [ ] **Step 3: Confirm PG-only reachability**

```bash
ssh root@10.0.5.2 'ss -ltnp | grep 5432'   # expect LISTEN on 127.0.0.1:5432
nc -zv 10.0.5.2 5432 || echo "LAN refused (expected)"
```

- [ ] **Step 4: Confirm schema created**

```bash
ssh root@10.0.5.2 'docker exec postgresql psql -U suwayomi -d suwayomi -c "\dt" | head'
```
Expected: Suwayomi tables present.

- [ ] **Step 5: Import the L1 backup**

```bash
ssh root@10.0.5.2 'curl -s -X POST --data-binary @/var/suwayomi/suwayomi-pre-pg-*.tachibk http://127.0.0.1:4567/api/v1/backup/import'
```
Expected: JSON success; import completes.

- [ ] **Step 6: Re-assert DB type**

```bash
ssh root@10.0.5.2 'cd /root/suwayomi && docker compose restart suwayomi'
```
Expected: after restart the container's `DATABASE_TYPE=POSTGRESQL` env wins; active DB is PG.

- [ ] **Step 7: Verify data (gate)**

Post-import counts == Task 3 Step 1 counts. Web UI loads library; open 2–3 manga detail pages. `database.mv.db` still present (`ls -l /var/suwayomi/files/database.mv.db`).

---

### Task 5: Backup script redesign

**Files:**
- Modify: `ansible/roles/backup/templates/backup-suwayomi.sh.j2`
- Modify: `ansible/roles/backup/vars/default.yml` (add `suwayomi_pg_user`, `suwayomi_pg_db`, `suwayomi_pg_container`)
- Modify: `ansible/playbooks/backup-suwayomi.yml` (deploy only — logic is in the script)

**Interfaces:**
- Consumes: running PG sidecar named `postgresql`, DB `suwayomi`, user `suwayomi`.
- Produces: daily `suwayomi-db-<date>.dump` + `suwayomi-config-<date>.tar.gz` on codex.

**Note:** the backup playbook loads `roles/backup/vars/default.yml`, NOT the suwayomi role vars, so the PG user/db/container must be defined there too (or hardcoded).

- [ ] **Step 1: Rewrite `backup-suwayomi.sh.j2`**

```bash
#!/bin/bash
set -euo pipefail
BACKUP_BASE="{{ backup_mount }}/{{ backup_cifs_base }}/suwayomi"
DATE=$(date +%Y-%m-%d-%H%M%S)

echo "=== Suwayomi backup $DATE ==="
mkdir -p "$BACKUP_BASE"

# Database (logical, custom format)
DUMP="/tmp/suwayomi-db-$DATE.dump"
docker exec postgresql pg_dump -Fc -U {{ suwayomi_pg_user }} -d {{ suwayomi_pg_db }} > "$DUMP"
[ -s "$DUMP" ] || { echo "ERROR: empty dump"; exit 1; }
sha256sum "$DUMP" > "$DUMP.sha256"
cp "$DUMP" "$DUMP.sha256" "$BACKUP_BASE/"

# Config/data (exclude downloads, H2 files, built-in backups)
CFG="/tmp/suwayomi-config-$DATE.tar.gz"
tar czf "$CFG" --warning=no-file-changed \
  --exclude='files/downloads' --exclude='files/database.mv.db*' \
  --exclude='files/backups' -C /var/suwayomi files 2>/dev/null || true
cp "$CFG" "$BACKUP_BASE/"

rm -f "$DUMP" "$CFG"
echo "=== Suwayomi backup complete: $(ls -1 "$BACKUP_BASE" | wc -l) files ==="
```

Note: confirm the PG container name is `postgresql` (compose adds the project prefix; verify with `docker ps` and adjust the exec target to the actual name, e.g. `suwayomi-postgresql-1`).

- [ ] **Step 2: Deploy and run manually**

```bash
ansible-playbook playbooks/backup-suwayomi.yml
ansible-playbook playbooks/backup-suwayomi.yml --tags backup   # runs the "Run backup immediately" task
```
Expected: dump + sha256 + config tar on codex.

- [ ] **Step 3: Verify dump restores into scratch DB**

```bash
ssh root@10.0.5.2 'docker exec postgresql createdb -U suwayomi scratch_restore \
 && docker exec -i postgresql pg_restore -U suwayomi -d scratch_restore < /mnt/backup/server-backups/suwayomi/suwayomi-db-*.dump \
 && docker exec postgresql psql -U suwayomi -d scratch_restore -c "select count(*) from manga" \
 && docker exec postgresql dropdb -U suwayomi scratch_restore'
```
Expected: count matches library; dropdb succeeds.

- [ ] **Step 4: Commit**

```bash
git add ansible/roles/backup/templates/backup-suwayomi.sh.j2 ansible/playbooks/backup-suwayomi.yml
git commit -m "ansible: suwayomi backup via pg_dump + config tar"
```

---

### Task 6: Restore + rollback scripts and role wiring

**Files:**
- Create: `ansible/roles/backup/templates/restore-suwayomi.sh.j2`
- Create: `ansible/roles/suwayomi/templates/rollback-suwayomi-h2.sh.j2`
- Modify: `ansible/roles/suwayomi/tasks/main.yml` (deploy rollback; replace H2 restore tags)

**Interfaces:**
- Consumes: Task 2 toggle, Task 5 artifacts.
- Produces: `/usr/local/bin/restore-suwayomi.sh`, `/usr/local/bin/rollback-suwayomi-h2.sh`.

- [ ] **Step 1: Write `restore-suwayomi.sh.j2`**

Behavior: stop suwayomi → drop/recreate DB → `pg_restore` given dump → restore config tar → start → health check. Inputs via args/env with defaults to latest codex artifacts. Include a confirmation prompt.

- [ ] **Step 2: Write `rollback-suwayomi-h2.sh.j2`**

Behavior:
```bash
# 1. stop stack
cd /root/suwayomi && docker compose down
# 2. restore original compose (or set suwayomi_db_type=h2 and redeploy)
cp /root/suwayomi/docker-compose.h2.bak /root/suwayomi/docker-compose.yml
# 3. ensure explicit H2 env
# (edit/append DATABASE_TYPE=H2 so a stored PG value cannot win)
# 4. remove PG container but KEEP /var/suwayomi/postgres volume
# 5. start
docker compose up -d
```
Ensure `DATABASE_TYPE=H2` is set in the restored compose.

- [ ] **Step 3: Wire `tasks/main.yml`**

- Deploy `rollback-suwayomi-h2.sh` to `/usr/local/bin/` (mode 0700).
- Replace the `--tags restore` unarchive-H2 tasks with PG restore (`suwayomi_restore_dump_src`, `suwayomi_restore_config_src`).

- [ ] **Step 4: Deploy**

```bash
ansible-playbook playbooks/suwayomi.yml
```

- [ ] **Step 5: Commit**

```bash
git add ansible/roles/backup/templates/restore-suwayomi.sh.j2 ansible/roles/suwayomi/templates/rollback-suwayomi-h2.sh.j2 ansible/roles/suwayomi/tasks/main.yml
git commit -m "ansible: suwayomi postgres restore + H2 rollback scripts"
```

---

### Task 7: Rollback drill (mandatory)

**Files:** none.

**Interfaces:**
- Consumes: Task 6 rollback script; H2 files intact.
- Produces: proof rollback works; returns to PostgreSQL afterward.

- [ ] **Step 1: Run rollback script**

```bash
ssh root@10.0.5.2 'bash /usr/local/bin/rollback-suwayomi-h2.sh'
```
Expected: Suwayomi comes up on H2; library loads.

- [ ] **Step 2: Confirm H2 active**

Check `/var/suwayomi/files/server.conf` `databaseType` and that the UI shows the library.

- [ ] **Step 3: Return to PostgreSQL**

```bash
cd ansible && ansible-playbook playbooks/suwayomi.yml
ssh root@10.0.5.2 'cd /root/suwayomi && docker compose up -d'
```
Expected: PG container healthy; Suwayomi on PG; data still present.

- [ ] **Step 4: Record drill result** in the plan's execution log.

---

### Task 8: Documentation + push

**Files:**
- Modify: `../homelab/docs/utilities/suwayomi.md`
- Modify: `proxmox-services/README.md`, `../homelab/README.md` (tables as needed)

**Interfaces:**
- Consumes: all prior tasks.
- Produces: docs matching the new reality.

- [ ] **Step 1: Update `suwayomi.md`**

Database = PostgreSQL 18 (localhost sidecar), data table (`/var/suwayomi/postgres`), new backup/restore scripts, rollback runbook, H2→PG migration note, secret location.

- [ ] **Step 2: Update both README service tables** if they reference the DB.

- [ ] **Step 3: Commit and push both repos**

```bash
cd ../homelab && git add -A && git commit -m "docs: suwayomi postgresql migration" && git push
cd ../proxmox-services && git add -A && git commit -m "docs: suwayomi postgresql migration" && git push origin master && git push github master
```
