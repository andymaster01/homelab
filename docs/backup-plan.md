# Backup Implementation Plan

## Implementation Status

All 4 steps implemented. Files are at their final state.
Deploy in phases to verify each step before adding complexity:

| Step | What it adds | Verify with |
|---|---|---|
| 1 | Container + source mounts | `borgmatic --dry-run --verbosity 2` |
| 2 | OneDrive plain file sync (`rclone sync`) | `rclone sync ... --dry-run` |
| 3 | OneDrive Borg repo (rclone backend) | `borg list rclone:onedrive:borgbackup/photos` |
| 4 | Hetzner Borg repo + healthchecks.io | `borg list ssh://...` + green on hc dashboard |

> Steps 1–2 require removing the `repositories:` block from the YAML configs and omitting
> the `ssh/` volume from docker-compose while those destinations aren't set up yet.
> Steps 3–4 require the one-time manual setup (repo init, key export) documented below.

---

## Overview

Automated, encrypted, incremental backups for personal photos and videos using
BorgBackup + Borgmatic, deployed as a Docker container on `ubuntu-01` via Ansible,
following the same patterns as Jellyfin, FileBrowser, and Homepage.

Two destinations, three purposes:

| Destination | Tool | Format | Purpose |
|---|---|---|---|
| Hetzner Storage Box | BorgBackup (SSH) | Encrypted repo | Primary disaster recovery, versioned snapshots |
| OneDrive | BorgBackup (rclone backend) | Encrypted repo | Secondary disaster recovery, versioned snapshots |
| OneDrive | rclone sync (after_backup hook) | Plain files | Browsable on OneDrive website |

OneDrive folder layout:
```
onedrive:
├── borgbackup/
│   ├── photos/    ← borg repo (encrypted chunks, not human-browsable)
│   └── videos/    ← borg repo (encrypted chunks, not human-browsable)
├── Photos/        ← plain files (browsable on OneDrive website)
└── Videos/        ← plain files (browsable on OneDrive website)
```

Monitoring: healthchecks.io dead man's switch (no new containers needed).

---

## Architecture

```
bahamut (ZFS)
└── /mnt/photos-videos  ──NFS──►  ubuntu-01
                                       │
                              ┌────────▼─────────┐
                              │ borgmatic         │
                              │ container         │
                              │ /mnt/source/pv    │
                              └──────┬────────────┘
                                     │
               ┌─────────────────────┼──────────────────────┐
               │                     │                       │
        borgmatic create      borgmatic create         rclone sync
        (repo 1)              (repo 2)                 (after_backup hook)
               │                     │                       │
  ┌────────────▼───────────┐  ┌──────▼─────────────┐  ┌─────▼───────────────┐
  │ Hetzner Storage Box    │  │ OneDrive            │  │ OneDrive            │
  │ borgbackup/photos      │  │ borgbackup/photos   │  │ Photos/  Videos/    │
  │ borgbackup/videos      │  │ borgbackup/videos   │  │ (plain files)       │
  │ (encrypted borg repo)  │  │ (encrypted borg repo│  └─────────────────────┘
  └────────────────────────┘  └─────────────────────┘
               │
  healthchecks.io ping (success/failure)
```

Borgmatic natively supports multiple repositories per config. Both Hetzner (SSH)
and OneDrive (rclone backend) are listed in the `repositories:` block — borgmatic
writes archives to all repos on every run. The rclone plain file sync is additive,
running as an `after_backup` hook.

Two borgmatic configs run inside the same container:
- `photos.yaml` — sources the photos subdirectory, two borg repos + rclone sync
- `videos.yaml` — sources the videos subdirectory, two borg repos + rclone sync

---

Plus changes to `.env.example` and `.mise.toml`.

---

## 1. `docker/borgmatic/docker-compose.yml`

```yaml
services:
  borgmatic:
    image: ghcr.io/borgmatic-collective/borgmatic:latest
    container_name: borgmatic
    restart: unless-stopped

    volumes:
      # Borgmatic configs (two configs: photos, videos)
      - ./config:/etc/borgmatic.d:ro

      # SSH key for Hetzner Storage Box
      - ./ssh:/root/.ssh:ro

      # rclone config with OneDrive OAuth token (used for both borg repo + plain sync)
      - ./rclone:/root/.config/rclone:ro

      # Local Borg index cache — rebuildable, speeds up incremental runs
      - borgmatic_cache:/root/.cache/borg

      # Source: entire photos-videos NFS dataset (read-only)
      - /mnt/photos-videos:/mnt/source/pv:ro

    environment:
      # Loaded from .env via Ansible-written .env file
      BORG_PHOTOS_PASSPHRASE: ${BORG_PHOTOS_PASSPHRASE}
      BORG_VIDEOS_PASSPHRASE: ${BORG_VIDEOS_PASSPHRASE}
      BORGMATIC_CRON_SCHEDULE: "0 2 * * *"   # daily at 02:00

volumes:
  borgmatic_cache:
    driver: local
```

---

## 2. `docker/borgmatic/config/photos.yaml`

```yaml
repositories:
  - path: ssh://${HETZNER_BORGBACKUP_USER}@${HETZNER_BORGBACKUP_HOST}/./borgbackup/photos
    label: hetzner-photos
  - path: rclone:onedrive:borgbackup/photos
    label: onedrive-photos

source_directories:
  - /mnt/source/pv/photos

exclude_patterns:
  - "*.DS_Store"
  - "*/.Trash*"

storage:
  compression: none          # JPEG/HEIC/RAW already compressed — skip CPU waste
  encryption_passphrase: ${BORG_PHOTOS_PASSPHRASE}
  archive_name_format: "photos-{now:%Y-%m-%dT%H:%M:%S}"

retention:
  keep_daily: 7
  keep_weekly: 4
  keep_monthly: 12
  keep_yearly: 3

checks:
  - name: repository
    frequency: 1 week
  - name: archives
    frequency: 2 weeks
  - name: extract
    frequency: 1 month
  - name: data
    frequency: 3 months

hooks:
  after_backup:
    # Sync plain files to OneDrive so they're browsable on the website
    - rclone sync /mnt/source/pv/photos onedrive:Photos --transfers=4 --checkers=8

  on_error:
    - curl -fsS --retry 3 "${HEALTHCHECKS_PHOTOS_URL}/fail" > /dev/null

  after_everything:
    # Ping healthchecks.io on full success (create + checks passed)
    - curl -fsS --retry 3 "${HEALTHCHECKS_PHOTOS_URL}" > /dev/null

monitoring:
  healthchecks:
    ping_url: ${HEALTHCHECKS_PHOTOS_URL}
    send_logs: true
```

---

## 3. `docker/borgmatic/config/videos.yaml`

```yaml
repositories:
  - path: ssh://${HETZNER_BORGBACKUP_USER}@${HETZNER_BORGBACKUP_HOST}/./borgbackup/videos
    label: hetzner-videos
  - path: rclone:onedrive:borgbackup/videos
    label: onedrive-videos

source_directories:
  - /mnt/source/pv/videos

exclude_patterns:
  - "*.DS_Store"
  - "*/.Trash*"

storage:
  compression: none          # H.264/H.265 already compressed — no gain
  encryption_passphrase: ${BORG_VIDEOS_PASSPHRASE}
  archive_name_format: "videos-{now:%Y-%m-%dT%H:%M:%S}"

retention:
  keep_daily: 7
  keep_weekly: 4
  keep_monthly: 6            # Videos accumulate slower, shorter history is fine

checks:
  - name: repository
    frequency: 1 week
  - name: archives
    frequency: 2 weeks
  - name: extract
    frequency: 1 month
  - name: data
    frequency: 3 months

hooks:
  after_backup:
    - rclone sync /mnt/source/pv/videos onedrive:Videos --transfers=2 --checkers=4

  on_error:
    - curl -fsS --retry 3 "${HEALTHCHECKS_VIDEOS_URL}/fail" > /dev/null

  after_everything:
    - curl -fsS --retry 3 "${HEALTHCHECKS_VIDEOS_URL}" > /dev/null

monitoring:
  healthchecks:
    ping_url: ${HEALTHCHECKS_VIDEOS_URL}
    send_logs: true
```

---

## 4. `ansible/templates/borgmatic.env.j2`

Follows the same pattern as `jellyfin.env.j2`:

```
BORG_PHOTOS_PASSPHRASE={{ BORG_PHOTOS_PASSPHRASE }}
BORG_VIDEOS_PASSPHRASE={{ BORG_VIDEOS_PASSPHRASE }}
HETZNER_BORGBACKUP_USER={{ HETZNER_BORGBACKUP_USER }}
HETZNER_BORGBACKUP_HOST={{ HETZNER_BORGBACKUP_HOST }}
HEALTHCHECKS_PHOTOS_URL={{ HEALTHCHECKS_PHOTOS_URL }}
HEALTHCHECKS_VIDEOS_URL={{ HEALTHCHECKS_VIDEOS_URL }}
```

---

## 5. `ansible/borgmatic.yml`

Follows the Jellyfin playbook pattern (`ansible/jellyfin.yml`) exactly:

```yaml
---
- name: Deploy Borgmatic
  hosts: ubuntu-01
  become: true

  vars:
    state: present
    borgmatic_dir: /home/ubuntu/borgmatic
    BORG_PHOTOS_PASSPHRASE: "{{ lookup('env', 'BORG_PHOTOS_PASSPHRASE') }}"
    BORG_VIDEOS_PASSPHRASE: "{{ lookup('env', 'BORG_VIDEOS_PASSPHRASE') }}"
    HETZNER_BORGBACKUP_USER: "{{ lookup('env', 'HETZNER_BORGBACKUP_USER') }}"
    HETZNER_BORGBACKUP_HOST: "{{ lookup('env', 'HETZNER_BORGBACKUP_HOST') }}"
    HEALTHCHECKS_PHOTOS_URL: "{{ lookup('env', 'HEALTHCHECKS_PHOTOS_URL') }}"
    HEALTHCHECKS_VIDEOS_URL: "{{ lookup('env', 'HEALTHCHECKS_VIDEOS_URL') }}"

  tasks:
    - name: Run docker compose down
      ansible.builtin.command:
        cmd: docker compose down
        chdir: "{{ borgmatic_dir }}"
      when: state == "absent"

    - name: Create borgmatic directory structure
      ansible.builtin.file:
        path: "{{ borgmatic_dir }}/{{ item }}"
        state: directory
        owner: ubuntu
        group: ubuntu
        mode: "0755"
      loop:
        - ""
        - config
        - ssh
        - rclone
      when: state == "present"

    - name: Copy docker-compose.yml
      ansible.builtin.copy:
        src: ../docker/borgmatic/docker-compose.yml
        dest: "{{ borgmatic_dir }}/docker-compose.yml"
        owner: ubuntu
        group: ubuntu
        mode: "0644"
      register: compose_file
      when: state == "present"

    - name: Copy borgmatic config files
      ansible.builtin.copy:
        src: "../docker/borgmatic/config/{{ item }}"
        dest: "{{ borgmatic_dir }}/config/{{ item }}"
        owner: ubuntu
        group: ubuntu
        mode: "0644"
      loop:
        - photos.yaml
        - videos.yaml
      register: config_files
      when: state == "present"

    - name: Template .env file
      ansible.builtin.template:
        src: templates/borgmatic.env.j2
        dest: "{{ borgmatic_dir }}/.env"
        owner: ubuntu
        group: ubuntu
        mode: "0600"
      register: env_file
      when: state == "present"

    # SSH private key for Hetzner — base64-encoded in .env, decoded here
    - name: Write SSH private key
      ansible.builtin.copy:
        content: "{{ lookup('env', 'BORGMATIC_SSH_PRIVATE_KEY') | b64decode }}"
        dest: "{{ borgmatic_dir }}/ssh/id_ed25519"
        owner: ubuntu
        group: ubuntu
        mode: "0600"
      register: ssh_key
      when: state == "present"

    - name: Write SSH known_hosts for Hetzner
      ansible.builtin.copy:
        content: "{{ lookup('env', 'BORGMATIC_SSH_KNOWN_HOSTS') }}"
        dest: "{{ borgmatic_dir }}/ssh/known_hosts"
        owner: ubuntu
        group: ubuntu
        mode: "0644"
      register: known_hosts
      when: state == "present"

    # rclone.conf with OneDrive OAuth token — base64-encoded in .env
    # Used for both the borg rclone backend and the plain file sync hook
    - name: Write rclone.conf
      ansible.builtin.copy:
        content: "{{ lookup('env', 'BORGMATIC_RCLONE_CONF') | b64decode }}"
        dest: "{{ borgmatic_dir }}/rclone/rclone.conf"
        owner: ubuntu
        group: ubuntu
        mode: "0600"
      register: rclone_conf
      when: state == "present"

    - name: Run docker compose up
      ansible.builtin.command:
        cmd: docker compose up -d
        chdir: "{{ borgmatic_dir }}"
      when: >
        state == "present" and (
          compose_file.changed or
          config_files.changed or
          env_file.changed or
          ssh_key.changed or
          rclone_conf.changed
        )
```

---

## 6. `.env.example` additions

```bash
# -----------------------------------------------------------
# Borgmatic / BorgBackup
# -----------------------------------------------------------
BORG_PHOTOS_PASSPHRASE=your-strong-passphrase-for-photos
BORG_VIDEOS_PASSPHRASE=your-strong-passphrase-for-videos
HETZNER_BORGBACKUP_USER=u123456
HETZNER_BORGBACKUP_HOST=u123456.your-storagebox.de
HEALTHCHECKS_PHOTOS_URL=https://hc-ping.com/your-photos-uuid
HEALTHCHECKS_VIDEOS_URL=https://hc-ping.com/your-videos-uuid

# Base64-encoded SSH private key for Hetzner Storage Box
# Generate: cat ~/.ssh/borgmatic_hetzner | base64 -w0
BORGMATIC_SSH_PRIVATE_KEY=

# SSH known_hosts entry for Hetzner (one line)
# Generate: ssh-keyscan u123456.your-storagebox.de
BORGMATIC_SSH_KNOWN_HOSTS=

# Base64-encoded rclone.conf with OneDrive OAuth token
# Used for both borg rclone backend and plain file sync
# Generate: cat ~/.config/rclone/rclone.conf | base64 -w0
BORGMATIC_RCLONE_CONF=
```

---

## 7. `.mise.toml` additions

Following the `deploy:jellyfin` / `deploy:jellyfin:down` / `deploy:jellyfin:status` pattern:

```toml
[tasks."deploy:borgmatic"]
description = "Deploy Borgmatic to ubuntu-01 via Ansible"
dir = "ansible"
run = "ansible-playbook borgmatic.yml"

[tasks."deploy:borgmatic:down"]
description = "Stop and remove Borgmatic containers on ubuntu-01"
dir = "ansible"
run = "ansible-playbook borgmatic.yml -e state=absent"

[tasks."deploy:borgmatic:status"]
description = "Check Borgmatic container status on ubuntu-01"
run = "ansible ubuntu-01 -m command -a 'docker compose -f /home/ubuntu/borgmatic/docker-compose.yml ps'"

[tasks."deploy:borgmatic:logs"]
description = "Tail Borgmatic logs on ubuntu-01"
run = "ssh ubuntu@192.168.1.130 'docker compose -f /home/ubuntu/borgmatic/docker-compose.yml logs -f'"

[tasks."deploy:borgmatic:run"]
description = "Trigger a manual backup run now (both configs)"
run = "ssh ubuntu@192.168.1.130 'docker exec borgmatic borgmatic --verbosity 1'"
```

---

## One-Time Manual Setup

These steps must be done **once before first deployment**. They are not automated
because they require interactive OAuth (OneDrive) and Hetzner panel access.

### Step 1 — SSH key for Hetzner

```bash
# Generate a dedicated key (no passphrase — runs unattended)
ssh-keygen -t ed25519 -C "borgmatic@ubuntu-01" -f ~/.ssh/borgmatic_hetzner -N ""

# Upload the PUBLIC key to Hetzner Storage Box panel:
# → https://robot.hetzner.com → Storage Box → SSH Keys → Add key
cat ~/.ssh/borgmatic_hetzner.pub

# Encode the private key for .env
cat ~/.ssh/borgmatic_hetzner | base64 -w0
# → paste output into BORGMATIC_SSH_PRIVATE_KEY in .env

# Get known_hosts entry for .env
ssh-keyscan u123456.your-storagebox.de
# → paste single line into BORGMATIC_SSH_KNOWN_HOSTS in .env
```

### Step 2 — rclone OneDrive auth

```bash
# Install rclone locally if not present
brew install rclone   # macOS

# Interactive OAuth setup (opens browser)
rclone config
# → New remote → name: onedrive → type: onedrive → follow OAuth flow
# → Creates ~/.config/rclone/rclone.conf

# Test it works
rclone ls onedrive:

# Encode for .env
cat ~/.config/rclone/rclone.conf | base64 -w0
# → paste into BORGMATIC_RCLONE_CONF in .env
```

### Step 3 — Initialize Borg repos on Hetzner (2 repos)

```bash
export BORG_RSH="ssh -i ~/.ssh/borgmatic_hetzner"

borg init \
  --encryption=repokey-blake2 \
  ssh://u123456@u123456.your-storagebox.de/./borgbackup/photos

borg init \
  --encryption=repokey-blake2 \
  ssh://u123456@u123456.your-storagebox.de/./borgbackup/videos
```

### Step 4 — Initialize Borg repos on OneDrive (2 repos)

```bash
# rclone must be configured first (Step 2)
borg init --encryption=repokey-blake2 rclone:onedrive:borgbackup/photos
borg init --encryption=repokey-blake2 rclone:onedrive:borgbackup/videos
```

### Step 5 — Export and store all 4 Borg keys (critical)

```bash
export BORG_RSH="ssh -i ~/.ssh/borgmatic_hetzner"

borg key export \
  ssh://u123456@u123456.your-storagebox.de/./borgbackup/photos \
  ~/borg-hetzner-photos.key

borg key export \
  ssh://u123456@u123456.your-storagebox.de/./borgbackup/videos \
  ~/borg-hetzner-videos.key

borg key export rclone:onedrive:borgbackup/photos ~/borg-onedrive-photos.key
borg key export rclone:onedrive:borgbackup/videos ~/borg-onedrive-videos.key
```

> Store all 4 key files + both passphrases in your password manager. If a repo's
> `repokey` is damaged, the exported key + passphrase is the only way to recover.

### Step 6 — healthchecks.io

1. Go to [healthchecks.io](https://healthchecks.io) and create two checks:
   - `borgmatic-photos` — period: 25 hours, grace: 2 hours
   - `borgmatic-videos` — period: 25 hours, grace: 2 hours
2. Copy each ping URL into `.env` (`HEALTHCHECKS_PHOTOS_URL`, `HEALTHCHECKS_VIDEOS_URL`)

---

## Backup Schedule

| Time | Action |
|---|---|
| Daily 02:00 | `borgmatic create` → both borg repos (Hetzner + OneDrive) → `rclone sync` plain files → healthchecks.io ping |
| Weekly | `borgmatic check --only repository` (fast index integrity scan, all repos) |
| Monthly | `borgmatic check --only archives` + `--only extract` (end-to-end restore test) |
| Quarterly | `borgmatic check --only data` (full bitrot scan, slow) |

The borgmatic Docker image manages this schedule internally via its built-in cron
(`BORGMATIC_CRON_SCHEDULE` env var). No external cron or systemd timer needed.

---

## Verification After Deployment

```bash
# 1. Deploy
mise run deploy:borgmatic

# 2. Check container is running
mise run deploy:borgmatic:status

# 3. Dry-run (no data written, verifies all 4 repos are reachable)
ssh ubuntu@192.168.1.130 'docker exec borgmatic borgmatic --dry-run --verbosity 1'

# 4. Manual backup run
mise run deploy:borgmatic:run

# 5. Verify Hetzner repos have snapshots
export BORG_RSH="ssh -i ~/.ssh/borgmatic_hetzner"
borg list ssh://u123456@u123456.your-storagebox.de/./borgbackup/photos
borg list ssh://u123456@u123456.your-storagebox.de/./borgbackup/videos

# 6. Verify OneDrive borg repos have snapshots
borg list rclone:onedrive:borgbackup/photos
borg list rclone:onedrive:borgbackup/videos

# 7. Verify OneDrive plain files are browsable
rclone ls onedrive:Photos | head -20
rclone ls onedrive:Videos | head -20

# 8. Check healthchecks.io dashboard → both checks show green
```

---

## Disaster Recovery Reference

See `docs/backup.md` for full details. Quick reference:

### Restore from Hetzner

```bash
export BORG_RSH="ssh -i ~/.ssh/borgmatic_hetzner"

borg list ssh://u123456@u123456.your-storagebox.de/./borgbackup/photos

borg extract \
  ssh://u123456@u123456.your-storagebox.de/./borgbackup/photos::photos-2025-01-15T02:00:00 \
  /restore/here
```

### Restore from OneDrive borg repo

```bash
borg list rclone:onedrive:borgbackup/photos

borg extract \
  rclone:onedrive:borgbackup/photos::photos-2025-01-15T02:00:00 \
  /restore/here
```

### Restore plain files from OneDrive

If you only need specific files and don't want to run borg, use rclone directly:

```bash
rclone copy onedrive:Photos/2024/vacation/ /restore/vacation/
```

No container, no config, no cache needed for any of these — just `borg` or `rclone`
+ credentials + passphrase.
