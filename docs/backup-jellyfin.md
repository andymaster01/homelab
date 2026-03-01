# Jellyfin Backup

Jellyfin's built-in `POST /Backup/Create` API is used instead of direct volume access
because the Jellyfin container owns its config directory. Accessing that volume from a
separate backup container risks file corruption and requires privileged access. The API
approach lets Jellyfin write a clean, consistent ZIP to a shared host path that
resticprofile can then read safely.

## Architecture

```mermaid
graph TD
    subgraph ubuntu-01["VM: ubuntu-01"]
        host["/mnt/containers-data/backups/jellyfin\n(shared directory on host)"]
    end

    subgraph jellyfin["Jellyfin container"]
        jf_mount["/config/data/backups\n← bind mount →"]
    end

    subgraph restic["resticprofile container"]
        rs_mount["/mnt/source/backups\n← bind mount →"]
    end

    jf_mount <-->|bind mount| host
    rs_mount <-->|bind mount| "/mnt/containers-data/backups"
    host -->|parent dir| "/mnt/containers-data/backups"

    restic -->|"POST :8096/Backup/Create\n(via extra_hosts: host-gateway)"| jellyfin
    restic -->|"rclone:onedrive:restic_backups/jellyfin"| onedrive["OneDrive"]
```

## Backup flow

1. resticprofile `jellyfin-onedrive` profile triggers at **04:00**
2. `run-before`: curl sends `POST http://host-gateway:8096/Backup/Create` with `JELLYFIN_API_KEY`
3. Jellyfin writes a fresh `.zip` to `/config/data/backups/` — visible on the host at
   `/mnt/containers-data/backups/jellyfin/`
4. restic reads from `/mnt/source/backups/jellyfin`, encrypts with `RESTIC_JELLYFIN_PASSPHRASE`
5. Encrypted snapshot is uploaded to `rclone:onedrive:restic_backups/jellyfin`
6. `run-after`: local ZIP is deleted from the host path
7. healthchecks.io is pinged at start, on success, and on failure

## Host directory & NFS context

- `/mnt/containers-data/backups/jellyfin` must exist on **ubuntu-01** before the first deploy
- The parent `/mnt/containers-data` is an NFS mount managed by `ansible/roles/nfs_client`
- Create the directory once manually (or via an Ansible task):

```bash
mkdir -p /mnt/containers-data/backups/jellyfin
```

> The directory must be present before starting either container. Docker will create it
> automatically if missing, but it will be owned by root and may not be reachable over NFS
> as expected.

## Key configuration files

| File | Purpose |
|---|---|
| `ansible/roles/jellyfin/docker/docker-compose.yml` | Bind-mounts backup dir into Jellyfin container |
| `ansible/roles/restic/docker/docker-compose.yml` | Mounts host backup dir into resticprofile; sets `extra_hosts` and `JELLYFIN_API_KEY` |
| `ansible/roles/restic/docker/profiles.d/jellyfin-onedrive.toml` | Defines source, run-before curl, cleanup, schedule, retention |
| `ansible/roles/restic/templates/env.j2` | Renders `.env` file with `JELLYFIN_API_KEY` |
| `ansible/roles/restic/defaults/main.yml` | Ansible default: reads `JELLYFIN_API_KEY` from environment |

## Environment variables

| Variable | Used by | Purpose |
|---|---|---|
| `JELLYFIN_API_KEY` | resticprofile | Authenticates `POST /Backup/Create` |
| `RESTIC_JELLYFIN_PASSPHRASE` | resticprofile | Encrypts restic repository |
| `HEALTHCHECKS_JELLYFIN_ONEDRIVE_URL` | resticprofile | healthchecks.io ping URL |

## Schedule & retention

| Job | Schedule | Details |
|---|---|---|
| Backup | Daily 04:00 | Trigger API → upload ZIP to OneDrive |
| Forget | Daily 04:15 | 7 daily / 4 weekly / 6 monthly |
| Check | Sundays 06:00 | Verify 5% of data |

## First-time setup checklist

1. Create `/mnt/containers-data/backups/jellyfin` on ubuntu-01
2. Generate API key: Jellyfin Dashboard → Admin → API Keys
3. Add `JELLYFIN_API_KEY` to Ansible secrets
4. `mise run jellyfin:up` — redeploy with new bind mount
5. `mise run restic:up` — redeploy resticprofile

## Useful commands

```bash
# Trigger a manual backup run
mise run restic:exec:backup jellyfin-onedrive

# View logs
mise run restic:logs

# List snapshots
mise run restic:list:snapshots jellyfin-onedrive
```
