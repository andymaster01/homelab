# Borgmatic One-Time Manual Setup

These steps must be done **once before first deployment**. They are not automated
because they require interactive OAuth (OneDrive) and Hetzner panel access.

## Step 1 — SSH key for Hetzner

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
# → paste into BORGMATIC_RCLONE_CONF in .env
```

## Step 3 — Initialize Borg repos on Hetzner (2 repos)

```bash
export BORG_RSH="ssh -i ~/.ssh/borgmatic_hetzner"

borg init \
  --encryption=repokey-blake2 \
  ssh://u123456@u123456.your-storagebox.de/./borgbackup/photos

borg init \
  --encryption=repokey-blake2 \
  ssh://u123456@u123456.your-storagebox.de/./borgbackup/videos
```

## Step 4 — Initialize Borg repos on OneDrive (2 repos)

```bash
# rclone must be configured first (Step 2)
borg init --encryption=repokey-blake2 rclone:onedrive:borgbackup/photos
borg init --encryption=repokey-blake2 rclone:onedrive:borgbackup/videos
```

## Step 5 — Export and store all 4 Borg keys (critical)

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

## Step 6 — healthchecks.io

1. Go to [healthchecks.io](https://healthchecks.io) and create two checks:
   - `borgmatic-photos` — period: 25 hours, grace: 2 hours
   - `borgmatic-videos` — period: 25 hours, grace: 2 hours
2. Copy each ping URL into `.env` (`HEALTHCHECKS_PHOTOS_URL`, `HEALTHCHECKS_VIDEOS_URL`)
