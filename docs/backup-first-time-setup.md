# Restic One-Time Manual Setup

These steps must be done **once before first deployment**. They are not automated
because they require interactive OAuth (OneDrive) and Hetzner panel access.

## Step 1 — SSH key for Hetzner

```bash
# Generate a dedicated key (no passphrase — runs unattended)
ssh-keygen -t ed25519 -C "restic@ubuntu-01" -f ~/.ssh/restic_hetzner -N ""

# Upload the PUBLIC key to Hetzner Storage Box panel:
# → https://robot.hetzner.com → Storage Box → SSH Keys → Add key
cat ~/.ssh/restic_hetzner.pub

# Encode the private key for .env
cat ~/.ssh/restic_hetzner | base64 -w0
# → paste output into RESTIC_SSH_PRIVATE_KEY in .env

# Get known_hosts entry for .env
ssh-keyscan u123456.your-storagebox.de
# → paste single line into RESTIC_SSH_KNOWN_HOSTS in .env
```

## Step 2 — rclone OneDrive auth

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
# → paste into RESTIC_RCLONE_CONF in .env
```

## Step 3 — Initialize restic repos on Hetzner (2 repos)

```bash
export RESTIC_PASSWORD="your-photos-passphrase"
restic -r sftp:u123456@u123456.your-storagebox.de:./restic/photos init \
  -o sftp.command="ssh -i ~/.ssh/restic_hetzner u123456@u123456.your-storagebox.de -s sftp"

export RESTIC_PASSWORD="your-videos-passphrase"
restic -r sftp:u123456@u123456.your-storagebox.de:./restic/videos init \
  -o sftp.command="ssh -i ~/.ssh/restic_hetzner u123456@u123456.your-storagebox.de -s sftp"
```

## Step 4 — Initialize restic repos on OneDrive (2 repos)

```bash
# rclone must be configured first (Step 2)
export RESTIC_PASSWORD="your-photos-passphrase"
restic -r rclone:onedrive:restic/photos init

export RESTIC_PASSWORD="your-videos-passphrase"
restic -r rclone:onedrive:restic/videos init
```

## Step 5 — Store passwords (critical)

> Store both passphrases in your password manager. The passphrase is the only
> way to decrypt your restic repositories. Unlike borg, restic derives the
> encryption key from the password — there is no separate key file to export.

## Step 6 — healthchecks.io

1. Go to [healthchecks.io](https://healthchecks.io) and create four checks:
   - `restic-photos-hetzner` — period: 25 hours, grace: 2 hours
   - `restic-photos-onedrive` — period: 25 hours, grace: 2 hours
   - `restic-videos-hetzner` — period: 25 hours, grace: 2 hours
   - `restic-videos-onedrive` — period: 25 hours, grace: 2 hours
2. Copy each ping URL into `.env`:

| Variable | Check |
|---|---|
| `HEALTHCHECKS_PHOTOS_HETZNER_URL` | `restic-photos-hetzner` |
| `HEALTHCHECKS_PHOTOS_ONEDRIVE_URL` | `restic-photos-onedrive` |
| `HEALTHCHECKS_VIDEOS_HETZNER_URL` | `restic-videos-hetzner` |
| `HEALTHCHECKS_VIDEOS_ONEDRIVE_URL` | `restic-videos-onedrive` |

> The OneDrive checks cover both the restic backup and the rclone plain-file sync.
> A failed rclone sync triggers the `/fail` ping, so one check covers both operations.

## Step 7 — Restic Browser (optional, macOS)

[Restic Browser](https://github.com/emuell/restic-browser) is a desktop GUI for browsing snapshots and restoring files. It connects to your existing repos without changing anything in the server setup.

```bash
brew install --cask restic-browser
```

**Connecting to an OneDrive repo:**

1. Open Restic Browser
2. Click **Open Repository**
3. Set location to `rclone:onedrive:restic_backups/photos` (or `restic_backups/videos`)
4. Set the password to your passphrase (`RESTIC_PHOTOS_PASSPHRASE` / `RESTIC_VIDEOS_PASSPHRASE`)
5. Click **Open**

> Requires rclone to be installed and the `onedrive` remote configured locally (done in Step 2).
> Restic Browser uses whichever `rclone` is on your PATH, so the same config applies.

**Connecting to a Hetzner repo:**

1. Click **Open Repository**
2. Set location to `sftp:u123456@u123456.your-storagebox.de:./restic/photos`
3. Set the password to your passphrase
4. Under **Environment**, add: `RESTIC_RSH=ssh -i ~/.ssh/restic_hetzner`
5. Click **Open**
