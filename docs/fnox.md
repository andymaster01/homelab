# fnox Quick Reference

## Setup (new machine)

### 1. Install age and generate a key pair

```bash
brew install age

mkdir -p ~/.config/fnox
age-keygen -o ~/.config/fnox/age.txt
```

Note the public key from the output (`age1...`). Back up the private key file somewhere safe (password manager, USB drive) — losing it means losing access to all encrypted secrets.

### 2. Install fnox

```bash
mise use -g fnox
```

### 3. Initialize fnox in the project

```bash
cd ~/code/home-setup
fnox init
```

Paste your age public key when prompted. This creates `fnox.toml`.

### 4. Restore secrets (existing repo)

If cloning onto a new machine, just copy `~/.config/fnox/age.txt` from your backup. The secrets are already in `fnox.toml` in the repo — mise auto-loads them when you `cd` into the project.

---

## Managing secrets

| Command | Description |
|---|---|
| `fnox set KEY "value"` | Add or update a secret |
| `fnox get KEY` | Decrypt and print a single secret |
| `fnox list` | List all stored secret keys |
| `fnox exec -- command` | Run a command with all secrets injected as env vars |

### Examples

```bash
# Add a new secret
fnox set RESTIC_PHOTOS_PASSPHRASE "my-passphrase"

# Update an existing secret (same command)
fnox set RESTIC_PHOTOS_PASSPHRASE "new-passphrase"

# Check a secret's value
fnox get RESTIC_PHOTOS_PASSPHRASE

# List all secret keys
fnox list

# Run a command with secrets injected
fnox exec -- ansible-playbook ansible/playbooks/bahamut.yml

# Verify secrets are loaded as env vars
fnox exec -- env | grep RESTIC
```

### Storing large/binary values

Base64-encode them before storing:

```bash
fnox set RESTIC_SSH_PRIVATE_KEY "$(cat ~/.ssh/restic_hetzner | base64 -w0)"
fnox set RESTIC_RCLONE_CONF "$(cat ~/.config/rclone/rclone.conf | base64 -w0)"
```
