# fnox Implementation Plan

Migration from plain `.env` file to fnox for encrypted secret management.

## Why

The current `.env` file stores all secrets in plain text on a single machine. This creates two problems:

1. **Machine migration** — if this machine dies or you switch laptops, recreating all secrets is painful and error-prone
2. **Pipeline usage** — the `.env` can't be committed to git, making CI/CD secret injection manual and fragile

fnox solves both: secrets are encrypted with age and committed to git in `fnox.toml`. Any machine with the age private key can decrypt them. CI/CD pipelines inject the age key as a single secret.

---

## What is age?

[age](https://age-encryption.org) (pronounced "a-g-e", stands for "Actually Good Encryption") is a modern, simple file encryption tool created by Filippo Valsorda (a Go team member at Google who also maintained Go's cryptography libraries).

### The problem age solves

GPG/PGP has been the standard for file encryption for decades, but it's notoriously complex — key management is confusing, the CLI is full of footguns, and the format carries decades of legacy baggage. age was designed as a modern replacement: small, opinionated, and hard to misuse.

### How it works

age uses **asymmetric encryption** (public-key cryptography):

- **Public key** (the "recipient") — used to *encrypt* data. Safe to share, commit to git, publish anywhere. Looks like: `age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p`
- **Private key** (the "identity") — used to *decrypt* data. Must be kept secret. Looks like: `AGE-SECRET-KEY-1QFWZ...`

Under the hood, age uses X25519 (Elliptic Curve Diffie-Hellman) for key agreement and ChaCha20-Poly1305 for symmetric encryption. These are the same modern primitives used by WireGuard, TLS 1.3, and Signal.

### Key concepts

| Concept | Description |
|---|---|
| **Recipient** | A public key that can encrypt data. You can have multiple recipients — useful for teams where each member has their own key pair |
| **Identity** | A private key that can decrypt data. Stored in a file (e.g., `~/.config/fnox/age-key.txt`) |
| **Key file** | A plain text file containing one or more identities. Created by `age-keygen` |

### How fnox uses age

When you run `fnox set MY_SECRET "value"`:

1. fnox takes the plaintext value `"value"`
2. Encrypts it using the age **public key** (recipient) listed in `fnox.toml`
3. Stores the encrypted ciphertext in `fnox.toml` — safe to commit to git

When you run `fnox get MY_SECRET`:

1. fnox reads the encrypted ciphertext from `fnox.toml`
2. Decrypts it using the age **private key** (identity) from `~/.config/fnox/age-key.txt`
3. Returns the plaintext value

The encrypted blob in `fnox.toml` is useless without the private key. Even if someone gets your entire git repo, they can't read the secrets.

### Multiple recipients (team usage)

age supports encrypting for multiple recipients. Each team member generates their own key pair and adds their public key to `fnox.toml`:

```toml
[providers]
age = { type = "age", recipients = [
  "age1abc...your-key...",
  "age1def...teammate-key...",
] }
```

Each secret gets encrypted for all recipients, so any team member can decrypt with their own private key.

### Why age over GPG?

| | age | GPG |
|---|---|---|
| Key generation | `age-keygen` (one command) | `gpg --full-generate-key` (interactive wizard) |
| Key format | Simple text file | Complex keyring with trust model |
| Key size | ~62 characters | Thousands of characters |
| Algorithm | X25519 + ChaCha20-Poly1305 | Configurable (easy to pick weak options) |
| Simplicity | One way to do things | Dozens of flags and modes |
| Dependencies | Single static binary | Large dependency tree |

---

## Prerequisites

- mise is already installed and configured (you have this)
- An age key pair for encryption (will be generated in step 1)

---

## Step-by-step Implementation

### Step 1: Generate an age key pair

age is the encryption backend that fnox uses by default. You need a key pair — the public key encrypts secrets, the private key decrypts them.

```bash
# Install age
brew install age

# Generate a key pair (stored at ~/.config/fnox/age-key.txt by default)
mkdir -p ~/.config/fnox
age-keygen -o ~/.config/fnox/age-key.txt
```

This outputs something like:

```
# created: 2026-03-01T12:00:00Z
# public key: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
AGE-SECRET-KEY-1QFWZ...
```

**Save the public key** — you'll need it for fnox init. The private key stays in that file.

> **CRITICAL**: Back up `~/.config/fnox/age-key.txt` somewhere safe (e.g., password manager, USB drive, printed copy). If you lose this key, you lose access to all encrypted secrets.

### Step 2: Install fnox via mise

```bash
mise use -g fnox
```

Verify it works:

```bash
fnox --version
```

### Step 3: Initialize fnox in the project

```bash
cd ~/code/home-setup
fnox init
```

This creates a `fnox.toml` file. It will ask you for your age public key (from step 1). The resulting file looks like:

```toml
[providers]
age = { type = "age", recipients = ["age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p"] }
```

### Step 4: Migrate each secret from `.env` to fnox

For every variable in your `.env` file, run `fnox set`. The value gets encrypted with your age public key and stored in `fnox.toml`.

```bash
# ---- Terraform / Proxmox ----
fnox set TF_VAR_proxmox_api_token "user@pam!token-id=actual-secret-value"
fnox set TF_VAR_vm_ssh_public_key "ssh-ed25519 AAAA... user@host"

# ---- Docker / Jellyfin ----
fnox set PUID "1000"
fnox set PGID "1000"
fnox set TZ "America/New_York"

# ---- File Server (Samba + NFS) ----
fnox set FILESERVER_SMB_USER "actual_username"
fnox set FILESERVER_SMB_PASS "actual_password"

# ---- Restic / Resticprofile ----
fnox set RESTIC_PHOTOS_PASSPHRASE "actual-passphrase"
fnox set RESTIC_VIDEOS_PASSPHRASE "actual-passphrase"
fnox set HETZNER_SFTP_USER "u123456"
fnox set HETZNER_SFTP_HOST "u123456.your-storagebox.de"
fnox set HEALTHCHECKS_PHOTOS_HETZNER_URL "https://hc-ping.com/actual-uuid"
fnox set HEALTHCHECKS_PHOTOS_ONEDRIVE_URL "https://hc-ping.com/actual-uuid"
fnox set HEALTHCHECKS_VIDEOS_HETZNER_URL "https://hc-ping.com/actual-uuid"
fnox set HEALTHCHECKS_VIDEOS_ONEDRIVE_URL "https://hc-ping.com/actual-uuid"
fnox set RESTIC_JELLYFIN_PASSPHRASE "actual-passphrase"
fnox set HEALTHCHECKS_JELLYFIN_ONEDRIVE_URL "https://hc-ping.com/actual-uuid"

# ---- Base64-encoded large values ----
# For these, pipe from the current env or file:
fnox set RESTIC_SSH_PRIVATE_KEY "$(cat ~/.ssh/restic_hetzner | base64 -w0)"
fnox set RESTIC_SSH_KNOWN_HOSTS "$(ssh-keyscan u123456.your-storagebox.de 2>/dev/null)"
fnox set RESTIC_RCLONE_CONF "$(cat ~/.config/rclone/rclone.conf | base64 -w0)"

# ---- Jellyfin ----
fnox set JELLYFIN_API_KEY "actual-api-key"
```

After this, `fnox.toml` will contain all secrets as encrypted blobs, safe to commit.

### Step 5: Verify secrets decrypt correctly

Check that each secret round-trips properly:

```bash
# Spot-check a few values
fnox get TF_VAR_proxmox_api_token
fnox get RESTIC_PHOTOS_PASSPHRASE
fnox get FILESERVER_SMB_PASS

# Verify all secrets load as env vars
fnox exec -- env | grep -E "^(TF_VAR|RESTIC|HETZNER|HEALTHCHECKS|FILESERVER|PUID|PGID|TZ|JELLYFIN)"
```

Compare the output against your current `.env` values. They must match exactly.

### Step 6: Update `.mise.toml` to use fnox instead of `.env`

Replace the `_.file = '.env'` line with the fnox plugin configuration.

**Before:**

```toml
[env]
_.file = '.env'
```

**After:**

```toml
[plugins]
fnox-env = "https://github.com/jdx/mise-env-fnox"

[tools]
fnox = "latest"

[env]
_.fnox-env = { tools = true }
```

The `tools = true` parameter tells the plugin to use mise's managed fnox binary.

### Step 7: Verify mise auto-loads fnox secrets

```bash
# Re-enter the directory to trigger mise activation
mise trust
cd ~/code/home-setup

# Check that env vars are populated
echo $RESTIC_PHOTOS_PASSPHRASE
echo $TF_VAR_proxmox_api_token
echo $FILESERVER_SMB_PASS
```

All values should match your original `.env`.

### Step 8: Verify Ansible still works

Ansible roles use `lookup('env', 'VAR')` to read secrets from environment variables. Since fnox injects the same env vars, Ansible should work without any code changes.

```bash
# Dry-run an Ansible playbook to verify variable resolution
# (use --check for dry-run, or a specific task with -t)
fnox exec -- ansible-playbook ansible/playbooks/bahamut.yml --check

# Or verify a specific role's variables resolve correctly
fnox exec -- ansible -m debug -a "var=RESTIC_PHOTOS_PASSPHRASE" localhost \
  -e "RESTIC_PHOTOS_PASSPHRASE={{ lookup('env', 'RESTIC_PHOTOS_PASSPHRASE') }}"
```

If mise integration works (step 7), you don't even need `fnox exec --` — the env vars are already loaded by mise.

### Step 9: Verify Terraform still works

```bash
# Terraform reads TF_VAR_* from environment automatically
cd terraform/proxmox/vms
terraform plan -var-file=../terraform.tfvars
```

The `TF_VAR_proxmox_api_token` and `TF_VAR_vm_ssh_public_key` should be picked up from the environment.

### Step 10: Update `.gitignore`

```gitignore
# Remove or comment out:
# .env          <-- no longer needed, fnox.toml replaces it

# Add:
# fnox age key (should never be committed)
age-key.txt
```

Keep `.env.example` in the repo as documentation for what variables exist and what they're used for.

### Step 11: Commit `fnox.toml` to git

```bash
git add fnox.toml .mise.toml .gitignore
git commit -m "feat: migrate secrets from .env to fnox (age-encrypted)"
```

The encrypted secrets in `fnox.toml` are safe to commit — they can only be decrypted with your age private key.

### Step 12: Clean up the old `.env` file

Once everything is verified:

```bash
# Double-check one last time
fnox exec -- env | grep RESTIC_PHOTOS_PASSPHRASE

# Remove the old .env
rm .env
```

---

## Machine Migration (New Machine Setup)

When you set up a new machine:

1. Clone the repo: `git clone <repo-url>`
2. Install mise: (your usual method)
3. Install fnox: `mise use -g fnox`
4. Copy the age private key to `~/.config/fnox/age-key.txt` (from your backup)
5. `cd` into the project — mise + fnox auto-load all secrets

That's it. No manual `.env` file recreation.

---

## CI/CD Pipeline Usage

For pipelines (GitHub Actions, GitLab CI, etc.):

1. Store the age private key as a pipeline secret (e.g., `FNOX_AGE_KEY`)
2. In the pipeline, write it to a file and use `fnox exec`:

```yaml
# GitHub Actions example
jobs:
  deploy:
    steps:
      - uses: actions/checkout@v4

      - name: Install mise and fnox
        run: |
          curl https://mise.run | sh
          mise use -g fnox

      - name: Set up age key
        run: |
          mkdir -p ~/.config/fnox
          echo "${{ secrets.FNOX_AGE_KEY }}" > ~/.config/fnox/age-key.txt

      - name: Deploy
        run: fnox exec -- ansible-playbook ansible/playbooks/bahamut.yml
```

---

## Rollback Plan

If something goes wrong during migration:

1. Your `.env` file still exists until step 12
2. Revert `.mise.toml` to `_.file = '.env'`
3. Remove `fnox.toml`
4. Everything works as before

Only delete `.env` after you've verified every secret decrypts correctly and all tools (Ansible, Terraform, Docker Compose) work.

---

## Summary of Files Changed

| File | Action | Description |
|---|---|---|
| `fnox.toml` | **Created** | Age-encrypted secrets, committed to git |
| `.mise.toml` | **Modified** | Replace `_.file = '.env'` with fnox plugin |
| `.gitignore` | **Modified** | Add `age-key.txt`, optionally remove `.env` |
| `.env` | **Deleted** | Replaced by `fnox.toml` |
| `.env.example` | **Kept** | Documentation reference for variable names |
| `ansible/roles/*/defaults/main.yml` | **No changes** | Still use `lookup('env', ...)` — works as-is |
| `ansible/roles/*/templates/env.j2` | **No changes** | Still use Ansible variables — works as-is |
| `docker-compose.yml` files | **No changes** | Still use `${VAR}` syntax — works as-is |
