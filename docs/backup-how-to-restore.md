# Backup — How to Restore

## Current Backup Strategy

```
Source files (ubuntu-01 NFS mount)
    │
    ├──► OneDrive — restic repo (rclone:onedrive:restic_backups/photos)
    │         └──► rclone plain-file sync → onedrive:PhotosPlain
    │
    └──► Hetzner Storage Box — restic repo (sftp:u123456@.../restic/photos)
         [disabled — enable once OneDrive is stable]
```

**Active profiles:** `photos-onedrive` only. Videos and Hetzner profiles are disabled
and will be enabled progressively.

**Schedule (photos-onedrive):**

| Time | Job |
|---|---|
| 02:30 daily | backup + rclone sync to OneDrive |
| 02:45 daily | forget (prune old snapshots) |
| Sun 05:00 | check (verify 5% of repo data) |

**Retention:** 7 daily, 4 weekly, 12 monthly, 3 yearly.

---

## What Happens If You Lose a Repo?

If **one remote** goes down:
- Your other remote still has a complete, independent repo
- Restore from that one

If **both remotes** go down simultaneously:
- You have no backup — this is why two remotes matter
- The source files on the server are still intact (original data)

If you lose **the source AND one remote** but still have the other:
- You can fully restore from the surviving repo

---

## Local Setup (Required Before Restoring)

### Install restic and rclone

```bash
brew install restic rclone
```

### Configure rclone for OneDrive

rclone is required to access the OneDrive restic repo. If you're on a new machine and don't have it configured yet:

```bash
rclone config
```

Follow the interactive prompts:
- **New remote** → name it `onedrive`
- **Storage type** → `Microsoft OneDrive`
- Leave client ID and secret blank (uses rclone's defaults)
- Follow the OAuth browser flow
- Select your OneDrive type (personal or business)
- Confirm the detected root

Test it works:

```bash
rclone ls onedrive:restic_backups/photos
# → should list restic pack files (data/, index/, snapshots/, etc.)
```

> If you already have rclone configured from the initial setup (`backup-setup.md` Step 2),
> this step can be skipped.

---

## Restore From Scratch (Worst Case)

Scenario: container gone, cache gone, but an OneDrive or Hetzner repo is intact.
You only need: `restic` + `rclone` (for OneDrive) or SSH key (for Hetzner) + passphrase.

### Restore from OneDrive

```bash
# List snapshots
RESTIC_PASSWORD="your-photos-passphrase" \
  restic -r rclone:onedrive:restic_backups/photos snapshots

# Restore a specific snapshot
RESTIC_PASSWORD="your-photos-passphrase" \
  restic -r rclone:onedrive:restic_backups/photos restore SNAPSHOT_ID \
  --target /restore/here

# Or restore the latest snapshot
RESTIC_PASSWORD="your-photos-passphrase" \
  restic -r rclone:onedrive:restic_backups/photos restore latest \
  --target /restore/here
```

### Restore from Hetzner

```bash
# List snapshots
RESTIC_PASSWORD="your-photos-passphrase" \
  restic -r sftp:u123456@u123456.your-storagebox.de:./restic/photos snapshots \
  -o sftp.command="ssh -i ~/.ssh/restic_hetzner u123456@u123456.your-storagebox.de -s sftp"

# Restore latest snapshot
RESTIC_PASSWORD="your-photos-passphrase" \
  restic -r sftp:u123456@u123456.your-storagebox.de:./restic/photos restore latest \
  --target /restore/here \
  -o sftp.command="ssh -i ~/.ssh/restic_hetzner u123456@u123456.your-storagebox.de -s sftp"
```

### Restore specific files only

```bash
# Restore only a subfolder
restic restore latest --target /restore/here --include /path/inside/snapshot

# Browse snapshots interactively (mounts repo as a FUSE filesystem)
restic mount /mnt/restic
# → browse /mnt/restic/snapshots/<id>/... like a normal directory
# → ctrl+c to unmount
```

### Using Restic Browser (GUI, macOS)

For browsing and selective file restore without the CLI, use
[Restic Browser](https://github.com/emuell/restic-browser) — see `backup-setup.md` Step 7.

---

## Passwords

Both passphrases are in your password manager:
- `RESTIC_PHOTOS_PASSPHRASE` — photos repos (both Hetzner and OneDrive)
- `RESTIC_VIDEOS_PASSPHRASE` — videos repos (both Hetzner and OneDrive)

> Unlike borg, restic derives the encryption key directly from the password.
> There is no separate key file to export or back up.

---

## Check Routine

Resticprofile runs a weekly `check` that reads and verifies 5% of the repo data.
Over ~20 weeks this cycles through the full repository.

To run a check manually:

```bash
docker exec resticprofile resticprofile --no-ansi \
  --config /etc/resticprofile/profiles.toml \
  -n photos-onedrive check
```

---

## The Full Safety Picture (target state, once all profiles enabled)

```
Source files (ubuntu-01)
    │
    ├──► photos-hetzner  ──► Sun 04:00 check
    ├──► photos-onedrive ──► Sun 05:00 check
    │         └──► plain-file sync → onedrive:PhotosPlain
    │
    ├──► videos-hetzner  ──► Sun 04:30 check
    └──► videos-onedrive ──► Sun 05:30 check
              └──► plain-file sync → onedrive:Videos
```

You have (once fully enabled):
- **2 independent encrypted repos** per dataset, on different services
- **Incremental runs** — only new/changed data is uploaded
- **Automatic pruning** with a defined retention policy
- **Integrity checks** every week on a rotating 5% of the repo
- **Zero dependency on the container** for restore — any machine with restic + passphrase is enough
- **Plain-file sync** to OneDrive as a browseable fallback (no restic needed to access those files)
