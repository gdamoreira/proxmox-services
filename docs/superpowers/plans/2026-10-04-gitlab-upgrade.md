# GitLab EE Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** ✅ COMPLETE — upgraded to **GitLab EE 18.11.12** (PG 16.14). All per-step backups sent to `codex` share.

**Goal:** Upgrade the self-hosted GitLab EE instance from `17.1.8` to the latest supported release following GitLab's official required upgrade path, with backups and verification at every stage.

**Architecture:** Single-node Omnibus (Linux package) install running as LXC 509 on Proxmox. Upgrade via the GitLab repo (`apt`) in staged jumps through each required upgrade stop. GitLab imposes required stop versions; you cannot skip them. Each stop = upgrade the package, let background migrations finish, verify, then proceed.

**Tech Stack:** GitLab EE Omnibus (apt), `gitlab-ctl`, `gitlab-rake`, PostgreSQL (bundled), systemd, Proxmox LXC.

**Spec:** Based on GitLab docs: [Plan your upgrade path](https://docs.gitlab.com/update/upgrade_paths/) and [GitLab 18 upgrade notes](https://docs.gitlab.com/update/versions/gitlab_18_changes/).

## Current State (verified)

- Version: **GitLab EE 17.1.8**
- Install: Omnibus (Linux package), apt-managed, on **Ubuntu 22.04** LXC 509
- Disk: 78G free of 98G (17% used) — sufficient
- SSH: root on **port 2223** (OpenSSH); git via **gitlab-sshd on port 22** (verified working)
- Old backups exist (`/var/opt/gitlab/backups/`) but are stale (Apr 2025)

## Global Constraints

- Follow the **required upgrade stops** exactly. From `17.1.8`: `17.3.7` → `17.5.z` → `17.8.z` → `17.11.z` → `18.2.z` → `18.5.z` → `18.8.z` → `18.11.z`.
- Use the **latest patch** of each minor stop (e.g. `17.3.7`, `17.11.7`), not the `.0`.
- **`17.1.8` stop is conditional** — only required if the `ci_pipeline_messages` table is large (>1.5M rows). Check before skipping; current is already 17.1.8 so this is satisfied.
- Let **background migrations finish** after each stop before the next. Verify with `gitlab-ctl status` and background migration checks.
- **Back up before every stop.** Run `gitlab-backup create` and a config backup before the first upgrade and before the major-version jump (17→18).
- **Every step backs up to the codex share.** After `gitlab-backup create`, copy the resulting `*_gitlab_backup.tar` + `/etc/gitlab/gitlab-secrets.json` to the network share `/mnt/pve/codex/gitlab/<version>/` (mounted on PVE host; `pct pull 509 <src> /mnt/pve/codex/gitlab/<version>/<file>`).
- `18.11.z` **automatically upgrades bundled PostgreSQL** to 17.7 — expect extra downtime on the final step.
- Do not touch SSH config mid-upgrade; root access is via port 2223.

## Review Focus

- **apt repo still points at the right channel** (`ee` not `ce`) — wrong channel silently "upgrades" to CE.
- **Disk fills mid-migration** (background migrations + PG upgrade are heavy) — verify free space after each stop.
- **gitlab-ctl reconfigure is not run** — package upgrades need `reconfigure`/`pcheck` to finish config generation.
- **A stale gitlab-shell AuthorizedKeysCommand / port change** breaks SSH after reconfigure — confirm git+ssh still works at the end of each task.
- **DB migration left in `down` state** — `gitlab-rake db:migrate:status` must show all `up`.

---
## Task 1: Snapshot + baseline backup

**Files:** none (ops only)

- [ ] **Step 1: Create a Proxmox snapshot of LXC 509** (rollback point)

Run (on PVE host `10.0.0.2`):
```
pct snapshot 509 pre-upgrade-17.1.8
```

- [ ] **Step 2: Create a full GitLab backup**

Run (inside LXC 509, via `pct exec 509`):
```
gitlab-backup create
cp /etc/gitlab/gitlab-secrets.json /var/opt/gitlab/backups/gitlab-secrets.json.$(date +%F)
```
Expected: backup tar created in `/var/opt/gitlab/backups/`, secrets file copied.

- [ ] **Step 3: Verify baseline works**

Run: `gitlab-ctl status`
Expected: all services `run:` (or listed as down that are expected). git+ssh still returns `Welcome to GitLab`.

- [ ] **Step 4: Record current version**

Run: `cat /opt/gitlab/version-manifest.txt | grep gitlab-ee`
Expected: `gitlab-ee 17.1.8`

---
## Task 2: Upgrade to 17.3.7 (required stop)

**Files:** none

- [ ] **Step 1: Confirm the target is the latest 17.3 patch**

Run: `apt-cache policy gitlab-ee | grep -A2 17.3`
Expected: a `17.3.7` (or newer `17.3.x`) candidate exists.

- [ ] **Step 2: Install 17.3.7**

Run:
```
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y gitlab-ee=17.3.7-ee.0
sudo gitlab-ctl reconfigure
```
Expected: install completes, reconfigure finishes, services healthy.

- [ ] **Step 3: Wait for background migrations**

Run:
```
sudo gitlab-ctl status
sudo gitlab-rake db:migrate:status | grep -c "^down"
```
Expected: `gitlab-ctl` all `run:`; `grep -c "^down"` returns `0`.

- [ ] **Step 4: Verify upgrade**

Run: `cat /opt/gitlab/version-manifest.txt | grep gitlab-ee`
Expected: `gitlab-ee 17.3.7`; git+ssh still `Welcome to GitLab`.

- [ ] **Step 5: Commit / record progress**

Note the version in the runbook. (No git commit — this is live infra.)

---
## Task 3: Upgrade to 17.5.z (required stop)

**Files:** none

- [ ] **Step 1: Install latest 17.5 patch**

Run:
```
sudo apt-get update
sudo apt-get install -y gitlab-ee=17.5.<latest>-ee.0
sudo gitlab-ctl reconfigure
```
Expected: install + reconfigure succeed.

- [ ] **Step 2: Wait for background migrations**

Run: `gitlab-rake db:migrate:status | grep -c "^down"`
Expected: `0`.

- [ ] **Step 3: Verify + record**

Run: `gitlab-ctl status; gitlab-rake db:migrate:status | grep -c "^down"`
Expected: healthy, `0` down. Record version `17.5.x`.

---
## Task 4: Upgrade to 17.8.z (required stop)

**Files:** none

- [ ] **Step 1: Install latest 17.8 patch**

Run:
```
sudo apt-get update
sudo apt-get install -y gitlab-ee=17.8.<latest>-ee.0
sudo gitlab-ctl reconfigure
```
Expected: install + reconfigure succeed.

- [ ] **Step 2: Wait for background migrations**

Run: `gitlab-rake db:migrate:status | grep -c "^down"`
Expected: `0`.

- [ ] **Step 3: Verify + record**

Expected: healthy, `0` down. Record version `17.8.x`.

---
## Task 5: Upgrade to 17.11.z (required stop)

**Files:** none

- [ ] **Step 1: Install latest 17.11 patch (e.g. 17.11.7)**

Run:
```
sudo apt-get update
sudo apt-get install -y gitlab-ee=17.11.7-ee.0
sudo gitlab-ctl reconfigure
```
Expected: install + reconfigure succeed.

- [ ] **Step 2: Wait for background migrations**

Run: `gitlab-rake db:migrate:status | grep -c "^down"`
Expected: `0`.

- [ ] **Step 3: Verify + record**

Expected: healthy, `0` down. Record version `17.11.x`. **This is the last 17.x stop before the 17→18 major jump.**

- [ ] **Step 4: Take a snapshot before the major jump**

Run (PVE host): `pct snapshot 509 pre-18`
Expected: snapshot created.

---
## Task 6: Upgrade to 18.2.z (major version 17→18, required stop)

**Files:** none

- [ ] **Step 1: Backup before major upgrade**

Run: `gitlab-backup create` (full backup), copy `gitlab-secrets.json` again.

- [ ] **Step 2: Install 18.2.z**

Run:
```
sudo apt-get update
sudo apt-get install -y gitlab-ee=18.2.<latest>-ee.0
sudo gitlab-ctl reconfigure
```
Expected: install + reconfigure succeed (major upgrade runs DB migrations).

- [ ] **Step 3: Wait for background migrations**

Run: `gitlab-rake db:migrate:status | grep -c "^down"`
Expected: `0`.

- [ ] **Step 4: Verify**

Run: `gitlab-ctl status; gitlab-rake db:migrate:status | grep -c "^down"; ssh git+ssh check`
Expected: healthy, `0` down, git+ssh `Welcome to GitLab`. Record `18.2.x`.

- [ ] **Step 5: Verify git+ssh after reconfigure**

Run: `ssh -p 22 git@<gitlab> -T`
Expected: `Welcome to GitLab, @guilherme!` (confirm SSH survived the reconfigure).

---
## Task 7: Upgrade to 18.5.z (required stop)

**Files:** none

- [ ] **Step 1: Install 18.5.z**

Run: `apt-get install -y gitlab-ee=18.5.<latest>-ee.0 && sudo gitlab-ctl reconfigure`
Expected: success.

- [ ] **Step 2: Wait for background migrations**

Run: `gitlab-rake db:migrate:status | grep -c "^down"`
Expected: `0`.

- [ ] **Step 3: Verify + record**

Expected: healthy, `0` down. Record `18.5.x`.

---
## Task 8: Upgrade to 18.8.z (required stop)

**Files:** none

- [ ] **Step 1: Install 18.8.z**

Run: `apt-get install -y gitlab-ee=18.8.<latest>-ee.0 && sudo gitlab-ctl reconfigure`
Expected: success.

- [ ] **Step 2: Wait for background migrations**

Run: `gitlab-rake db:migrate:status | grep -c "^down"`
Expected: `0`.

- [ ] **Step 3: Verify + record**

Expected: healthy, `0` down. Record `18.8.x`.

---
## Task 9: Upgrade to 18.11.z (latest, final)

**Files:** none

- [ ] **Step 1: Install 18.11.z**

Run: `apt-get update && apt-get install -y gitlab-ee=18.11.<latest>-ee.0 && sudo gitlab-ctl reconfigure`
Expected: success. **Expect a longer downtime — this step auto-upgrades bundled PostgreSQL to 17.7.**

- [ ] **Step 2: Wait for background migrations + PG upgrade to finish**

Run: `gitlab-ctl status; gitlab-rake db:migrate:status | grep -c "^down"`
Expected: all `run:` (except down-by-design), `0` down migrations.

- [ ] **Step 3: Verify version + services + git+ssh**

Run:
```
cat /opt/gitlab/version-manifest.txt | grep gitlab-ee
gitlab-ctl status
ssh -p 22 git@<gitlab> -T
```
Expected: `gitlab-ee 18.11.x`, healthy services, `Welcome to GitLab`.

- [ ] **Step 4: Confirm the instance is the latest**

Run: `sudo gitlab-rake gitlab:check` 
Expected: `Checking ... Finished` with no `F` failures.

---
## Post-Upgrade

- Update `../homelab/docs/.../gitlab.md` (or relevant doc) with the new version.
- Update the AGENTS.md/README version references if present.
- Create a fresh backup at the new version.
- Optionally remove the pre-upgrade LXC snapshots after confirming stability.

## Rollback

- If a stop fails: restore the prior version by reinstalling the previous `gitlab-ee` package and restoring the backup created at that stop:
```
sudo apt-get install -y gitlab-ee=<previous>-ee.0
sudo gitlab-ctl reconfigure
sudo gitlab-rake gitlab:backup:restore BACKUP=<timestamp>
```
- Or roll back the whole LXC to the `pre-upgrade-17.1.8` (or `pre-18`) snapshot on the PVE host.