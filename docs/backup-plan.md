# Backup Implementation Plan

## Implementation Status

All files implemented. Deploy in phases to verify each step before adding complexity:

| Step | What it adds | Verify with |
|---|---|---|
| 1 | Container + source mounts | `docker exec resticprofile resticprofile snapshots --all` |
| 2 | OneDrive plain file sync (`rclone sync`) | `rclone ls onedrive:Photos \| head -20` |
| 3 | OneDrive restic repo (rclone backend) | `restic -r rclone:onedrive:restic/photos snapshots` |
| 4 | Hetzner restic repo + healthchecks.io | `restic -r sftp:... snapshots` + green on hc dashboard |

---

## Overview

Automated, encrypted, incremental backups for personal photos and videos using
Restic + Resticprofile, deployed as a Docker container on `ubuntu-01` via Ansible,
following the same patterns as Jellyfin, FileBrowser, and Homepage.

Four profiles, three purposes:

| Destination | Profile | Format | Purpose |
|---|---|---|---|
| Hetzner Storage Box | photos-hetzner, videos-hetzner | Encrypted restic repo (SFTP) | Primary disaster recovery, versioned snapshots |
| OneDrive | photos-onedrive, videos-onedrive | Encrypted restic repo (rclone) | Secondary disaster recovery, versioned snapshots |
| OneDrive | (run-after hook on OneDrive profiles) | Plain files (rclone sync) | Browsable on OneDrive website |

OneDrive folder layout:
```
onedrive:
├── restic/
│   ├── photos/    ← restic repo (encrypted chunks, not human-browsable)
│   └── videos/    ← restic repo (encrypted chunks, not human-browsable)
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
                              │ resticprofile      │
                              │ container          │
                              │ /mnt/source/pv     │
                              └──────┬─────────────┘
                                     │
          ┌──────────────────────────┬┴──────────────────────────┐
          │                          │                            │
   photos-hetzner             photos-onedrive              rclone sync
   videos-hetzner             videos-onedrive              (run-after hook)
          │                          │                            │
  ┌───────▼──────────────┐   ┌──────▼─────────────┐   ┌─────────▼──────────┐
  │ Hetzner Storage Box  │   │ OneDrive            │   │ OneDrive           │
  │ restic/photos        │   │ restic/photos       │   │ Photos/  Videos/   │
  │ restic/videos        │   │ restic/videos       │   │ (plain files)      │
  │ (encrypted repo)     │   │ (encrypted repo)    │   └────────────────────┘
  └──────────────────────┘   └─────────────────────┘
          │
  healthchecks.io ping (start/success/fail)
```

Resticprofile manages four independent profiles, each with its own repository
and schedule. The Hetzner profiles include healthchecks.io HTTP hooks. The
OneDrive profiles include a `run-after` hook for plain file sync via rclone.

All four profiles are defined in a single `profiles.toml` config file.

---

Plus changes to `.env.example` and `.mise.toml`.

---

## 1. `docker/restic/docker-compose.yml`

Uses the official `creativeprojects/resticprofile` Docker image which bundles
restic, resticprofile, and rclone. No custom Dockerfile needed.

## 2. `docker/restic/profiles.toml`

Single config with four profiles using inheritance:
- `photos-hetzner` — SFTP to Hetzner, daily at 02:00, healthchecks.io hooks
- `photos-onedrive` — rclone to OneDrive, daily at 02:30, plain file sync hook
- `videos-hetzner` — SFTP to Hetzner, daily at 03:00, healthchecks.io hooks
- `videos-onedrive` — rclone to OneDrive, daily at 03:30, plain file sync hook

Each profile has its own `forget` (retention + prune) running after backup,
and a weekly `check` with `read-data-subset=5%` for rolling integrity verification.

## 3. `ansible/ubuntu-01/restic/restic.yml`

Ansible playbook following the same pattern as Jellyfin/FileBrowser deployments.

## 4. `ansible/ubuntu-01/restic/restic.env.j2`

Environment template with restic-specific variable names.

---

## Backup Schedule

| Time | Profile | Action |
|---|---|---|
| 02:00 | photos-hetzner | restic backup → forget+prune → healthchecks.io ping |
| 02:30 | photos-onedrive | restic backup → forget+prune → rclone sync plain photos |
| 03:00 | videos-hetzner | restic backup → forget+prune → healthchecks.io ping |
| 03:30 | videos-onedrive | restic backup → forget+prune → rclone sync plain videos |
| Sun 04:00–05:30 | all | restic check (read-data-subset=5%, staggered) |

The resticprofile container uses crond internally (`scheduler = "crond"` in config).

---

## Verification After Deployment

```bash
# 1. Deploy
mise run deploy:restic

# 2. Check container is running
mise run deploy:restic:status

# 3. List snapshots (should be empty initially)
ssh ubuntu@192.168.1.130 'docker exec resticprofile resticprofile --no-ansi --config /etc/resticprofile/profiles.toml -n photos-hetzner snapshots'

# 4. Trigger manual backup
mise run deploy:restic:run

# 5. Verify Hetzner repos have snapshots
export RESTIC_PASSWORD="your-photos-passphrase"
restic -r sftp:u123456@u123456.your-storagebox.de:./restic/photos snapshots \
  -o sftp.command="ssh -i ~/.ssh/restic_hetzner u123456@u123456.your-storagebox.de -s sftp"

# 6. Verify OneDrive restic repos have snapshots
restic -r rclone:onedrive:restic/photos snapshots

# 7. Verify OneDrive plain files are browsable
rclone ls onedrive:Photos | head -20
rclone ls onedrive:Videos | head -20

# 8. Check healthchecks.io dashboard → both checks show green
```

---

## Disaster Recovery Reference

### Restore from Hetzner

```bash
export RESTIC_PASSWORD="your-photos-passphrase"

restic -r sftp:u123456@u123456.your-storagebox.de:./restic/photos snapshots \
  -o sftp.command="ssh -i ~/.ssh/restic_hetzner u123456@u123456.your-storagebox.de -s sftp"

restic -r sftp:u123456@u123456.your-storagebox.de:./restic/photos restore latest \
  --target /restore/here \
  -o sftp.command="ssh -i ~/.ssh/restic_hetzner u123456@u123456.your-storagebox.de -s sftp"
```

### Restore from OneDrive restic repo

```bash
export RESTIC_PASSWORD="your-photos-passphrase"

restic -r rclone:onedrive:restic/photos snapshots

restic -r rclone:onedrive:restic/photos restore latest --target /restore/here
```

### Restore plain files from OneDrive

If you only need specific files and don't want to run restic, use rclone directly:

```bash
rclone copy onedrive:Photos/2024/vacation/ /restore/vacation/
```

No container, no config, no cache needed for any of these — just `restic` or `rclone`
+ credentials + passphrase.
