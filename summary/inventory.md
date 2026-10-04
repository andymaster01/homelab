# Infrastructure Inventory

Generated: 2026-10-01. This is a source-based inventory; it does not assert that any listed service or VM is currently running. Explicit configuration is distinguished from documentation-only or inferred data. Sensitive values are omitted.

## 1. Containers and orchestration

The service endpoints below are configured host port mappings or explicitly documented URLs. A port mapping without an explicit host IP binds according to Docker's default behavior; no host bind address is specified in these files. “Management” identifies the repository task or Ansible role when present.

| Service/container | Apparent host/server | Management path | Exposed host port(s)/protocol | Explicit IP/URL or notes |
|---|---|---|---|---|
| Jellyfin (`jellyfin`) | `ubuntu-01` (`192.168.1.130`) | `just deploy-remote jellyfin`; backup: `just backup jellyfin`; `containers/jellyfin/config.json` | `8096/tcp`, `1900/udp`, `7359/udp`; optional `8920/tcp` is commented out | `http://192.168.1.130:8096/` in `containers/homepage/config/bookmarks.yaml`; Compose is `containers/jellyfin/docker-compose.yml` |
| Homepage (`homepage`) | `ubuntu-01` (`192.168.1.130`) | `just deploy-remote homepage` | configured host port defaults to `80/tcp` → container `3000/tcp` | `containers/homepage/config.json`; URL/host inferred from this and `containers/homepage/docker-compose.yml` |
| Homepage data (`homepage-data`, nginx sidecar) | `ubuntu-01`, same Compose project | `just deploy-remote homepage` | none published | Serves static JSON on the internal Compose network; `containers/homepage/docker-compose.yml`, `docs/homepage-custom-data.md` |
| File Browser Quantum (`filebrowser`) | `ubuntu-01` (`192.168.1.130`) | `mise filebrowser:up` / Ansible role `filebrowser_quantum` | `8010/tcp` → `80/tcp` | `http://192.168.1.130:8010/` in `containers/homepage/config/bookmarks.yaml`; role Compose is `ansible/roles/filebrowser_quantum/docker/docker-compose.yaml` |
| Resticprofile (`resticprofile`) | `ubuntu-01` (`192.168.1.130`) | `mise restic:up` / Ansible role `restic` | none published | Ansible Compose `ansible/roles/restic/docker/docker-compose.yml`; backup targets/profile behavior documented in `docs/backup-how-to-restore.md` and `docs/backup-jellyfin.md` |
| Suwayomi (`suwayomi`) | `ubuntu-02` (`192.168.1.131`) | `mise manga:up` / Ansible role `manga` | `4567/tcp` | `http://192.168.1.131:4567/` in `containers/homepage/config/bookmarks.yaml`; Compose `ansible/roles/manga/docker/docker-compose.yml` |
| FlareSolverr/Byparr (`flaresolverr`) | `ubuntu-02` (`192.168.1.131`) | `mise manga:up` / Ansible role `manga` | none published | Internal URL configured for Suwayomi at `http://flaresolverr:8191`; image/service name appears in role Compose |
| Komga (`komga`) | `ubuntu-02` (`192.168.1.131`) | `mise manga:up` / Ansible role `manga` | `25600/tcp` | `http://192.168.1.131:25600/` in `containers/homepage/config/bookmarks.yaml` |
| Vikunja (`vikunja`) | `ubuntu-02` (`192.168.1.131`) | `just deploy-remote vikunja` | configured host port defaults to `3456/tcp` → `3456/tcp` | `http://192.168.1.131:3456/` in Homepage bookmarks; `containers/vikunja/config.json` |
| Kavita (`kavita`) | `ubuntu-02` (`192.168.1.131`) | `just deploy-remote kavita` | configured host port defaults to `5000/tcp` → `5000/tcp` | `http://192.168.1.131:5000/` in Homepage bookmarks; `containers/kavita/config.json` |
| Audiobookshelf (`audiobookshelf`) | `db-pg-01` (`192.168.1.151`) | `just deploy-remote audiobookshelf` | configured host port defaults to `13378/tcp` → container `80/tcp` | `http://192.168.1.151:13378/` in Homepage bookmarks; `containers/audiobookshelf/config.json` |
| PostgreSQL 18 (`postgresql18`) | `db-pg-01` (`192.168.1.151`) | `mise postgresql18:up` / Ansible role `postgresql18` | `5432/tcp` | Ansible Compose `ansible/roles/postgresql18/docker/docker-compose.yml` |
| Pushgateway (`pushgateway`) | Proposed `monitoring-01` (`192.168.1.150`) | **Documentation-only** proposed Ansible role `monitoring`; intended mise task `monitoring:up` | proposed `9091/tcp` | Described in `docs/implementation-grafana-monitoring.md`; role/Compose files are not present |
| Prometheus (`prometheus`) | Proposed `monitoring-01` (`192.168.1.150`) | **Documentation-only** proposed Ansible role `monitoring` | proposed `9090/tcp` | Proposed in `docs/implementation-grafana-monitoring.md`; scrape target Pushgateway `pushgateway:9091` |
| Grafana (`grafana`) | Proposed `monitoring-01` (`192.168.1.150`) | **Documentation-only** proposed Ansible role `monitoring` | proposed `3000/tcp` | Proposed URL `http://192.168.1.150:3000` in `docs/implementation-grafana-monitoring.md` |

Compose sources are `containers/{audiobookshelf,homepage,jellyfin,kavita,vikunja}/docker-compose.yml` and Ansible role Compose files under `ansible/roles/{filebrowser_quantum,manga,postgresql18,restic}/docker/`. The inventory prompt covers role Compose files; these files configure containers, but repository configuration alone does not establish runtime status. Some images use mutable tags (`stable` or `latest`) in role Compose files.

## 2. Managed servers

### Ansible inventory (`ansible/inventory.yml`)

| Name | IP | Role/group | Source |
|---|---|---|---|
| `ubuntu-01` | `192.168.1.130` | `app_servers` | `ansible/inventory.yml` |
| `ubuntu-02` | `192.168.1.131` | `app_servers` | `ansible/inventory.yml` |
| `bahamut` | `192.168.1.101` | `file_servers` | `ansible/inventory.yml` |
| `monitoring-01` | `192.168.1.150` | `monitoring_servers` | `ansible/inventory.yml` |
| `db-pg-01` | `192.168.1.151` | `db_servers` | `ansible/inventory.yml` |

### Terraform VM definitions (`terraform/proxmox/vms/terraform.tfvars`)

| Name | IP | Proxmox node / VM ID | Source |
|---|---|---|---|
| `ubuntu-01` | `192.168.1.130/24` | `bahamut` / 200 | `terraform/proxmox/vms/terraform.tfvars` |
| `ubuntu-02` | `192.168.1.131/24` | `bahamut` / 202 | `terraform/proxmox/vms/terraform.tfvars` |
| `monitoring-01` | `192.168.1.150/24` | `eiko` / 201 | `terraform/proxmox/vms/terraform.tfvars` |
| `db-pg-01` | `192.168.1.151/24` | `eiko` / 203 | `terraform/proxmox/vms/terraform.tfvars` |

**Differences and cross-checks:** `bahamut` exists in Ansible inventory as the file server, but is not a VM in Terraform (it is used as a Proxmox node). The four Terraform VMs match four Ansible hosts by name and address. No Ansible host is absent from the Terraform VM list after accounting for `bahamut` as the physical/hypervisor host. Homepage's static inventory (`containers/homepage/static-data/servers.json`) lists `eiko` at `192.168.1.102` and labels its guests `eiko-01-150` and `eiko-02-151`; those disagree with Terraform/Ansible (`monitoring-01`, `db-pg-01`, IPs `.150`, `.151`). It also lists `dev-01` (`192.168.1.35`, VM ID 105), absent from both management inventories. These Homepage entries are documentation/display data, not Terraform VM definitions.

## 3. Ansible vs Terraform

**Ansible** uses `ansible/inventory.yml` and five playbooks: `bahamut.yml` applies ZFS, NFS, and Samba roles to `file_servers`; `ubuntu-01.yml` applies NFS client, File Browser Quantum, and Restic roles; `ubuntu-02.yml` applies NFS client and Manga; `db-pg-01.yml` applies NFS client, PostgreSQL 18, and PostgreSQL backup; `monitoring-01.yml` currently applies only NFS client. Roles found under `ansible/roles/` configure datasets and file sharing, NFS mounts, Docker Compose applications, and daily PostgreSQL dumps. `ansible/roles/monitoring` is not present; monitoring is only specified as a proposed implementation in `docs/implementation-grafana-monitoring.md`.

**Terraform** has two Proxmox modules. `terraform/proxmox/images/` downloads the Ubuntu 24.04 Noble cloud image to nodes `bahamut` and `eiko` (storage `local`). `terraform/proxmox/vms/` defines four VMs above, creates per-VM cloud-init snippets, and configures guest agent, CPU/memory/disk, `vmbr0` networking, static IPv4/gateway, DNS, and an Ubuntu account/SSH public key. Defaults in `terraform/proxmox/vms/variables.tf` are 2 CPU cores, 4096 MB memory, 16 GB disk, DNS `1.1.1.1`, bridge `vmbr0`, storage `local-lvm`, and username `ubuntu`; per-VM overrides are in the tfvars file. `terraform/proxmox/vms/files/vendor-cloud-init.yaml` installs Docker Engine and Compose plugin and enables the guest agent.

**Apparent handoff:** Terraform provisions the Proxmox VMs, network configuration, cloud-init, and Docker prerequisites; Ansible then targets named hosts and configures OS-level services, mounts, fileserver behavior, and application Compose deployments. This sequence is inferred from the Terraform cloud-init and Ansible inventory/playbooks. The repo provides no evidence here that either tool has been applied successfully or that workloads are currently running.

## 4. Server configuration

| Server | Configured services and settings | Storage, mounts, backups, monitoring, users | Sources |
|---|---|---|---|
| `bahamut` (`192.168.1.101`) | ZFS datasets, NFS server, Samba shares. NFS exports allow `192.168.1.0/24` with read/write, sync, all-squash to UID/GID 1000. Samba shares use a configured account; secret omitted. | Pool `zfs-data`; datasets mounted at `/mnt/media`, `/mnt/photos-videos`, `/mnt/containers-data`, `/mnt/photos-videos-test`, directories owned UID/GID 1000. | `ansible/host_vars/bahamut.yml`; `ansible/roles/fileserver_{zfs,nfs,samba}/`; `docs/storage.md` |
| `ubuntu-01` (`192.168.1.130`) | Jellyfin, Homepage and its Nginx static-data sidecar, File Browser Quantum, Resticprofile. | NFS client mounts `/mnt/photos-videos-test`, `/mnt/media`, `/mnt/containers-data`, and `/mnt/photos-videos` from `192.168.1.101`; consumers include Jellyfin (media read-only), File Browser (multiple shares read/write), Resticprofile (photos/videos and backup roots read-only). Jellyfin config is backed up to `/mnt/containers-data/backups/jellyfin`; docs describe OneDrive restic backup. Photos/Jellyfin schedules and retention are documented; some profiles are explicitly described as disabled. Login account in Ansible inventory: `ubuntu`. | `ansible/playbooks/ubuntu-01.yml`; `ansible/roles/nfs_client/`; `containers/jellyfin/`; `containers/homepage/`; `ansible/roles/filebrowser_quantum/`; `ansible/roles/restic/`; `docs/backup-how-to-restore.md`; `docs/backup-jellyfin.md`; `docs/storage.md` |
| `ubuntu-02` (`192.168.1.131`) | Suwayomi, FlareSolverr/Byparr, Komga. Vikunja and Kavita are assigned here by their deployment metadata and Homepage links. | Manga app data under `/home/ubuntu/manga`; downloads on `/mnt/containers-data/manga-downloads`. NFS client role configures the same four mounts as other clients. Vikunja stores DB/files under `${CONTAINERS_DATA}`; Kavita config and media use configured bind mounts. Login account: `ubuntu`. | `ansible/playbooks/ubuntu-02.yml`; `ansible/roles/manga/`; `containers/vikunja/config.json`; `containers/kavita/config.json`; `containers/homepage/config/bookmarks.yaml`; `ansible/roles/nfs_client/` |
| `monitoring-01` (`192.168.1.150`) | Ansible playbook currently configures NFS client only. Pushgateway, Prometheus, and Grafana stack is proposed in docs only. | Four NFS mounts are configured by role. Terraform specifies Ubuntu account `ubuntu`; Ansible inventory also uses `ubuntu`. | `ansible/playbooks/monitoring-01.yml`; `ansible/roles/nfs_client/`; `terraform/proxmox/vms/terraform.tfvars`; `docs/implementation-grafana-monitoring.md` |
| `db-pg-01` (`192.168.1.151`) | PostgreSQL 18 in Compose; daily `pg_dump` cron scheduled for 02:30, logs to `/home/ubuntu/pg_backup/pg-dump.log`. Audiobookshelf deployment metadata points to this host. | PostgreSQL dumps go to `/mnt/containers-data/backups/postgresql`; NFS client mounts four shares. PostgreSQL data uses named volume `postgresql_data`. Login account: `ubuntu`. | `ansible/playbooks/db-pg-01.yml`; `ansible/roles/postgresql18/`; `ansible/roles/pg_backup/`; `containers/audiobookshelf/config.json`; `ansible/roles/nfs_client/` |
| `eiko` (`192.168.1.102` per Homepage static data) | Proxmox node named by Terraform for monitoring and database VMs; no Ansible host entry or OS-level role for this node. | Image downloads target this node; Homepage's physical-host IP is display data and is not stated in Terraform. | `terraform/proxmox/images/terraform.tfvars`; `terraform/proxmox/vms/terraform.tfvars`; `containers/homepage/static-data/servers.json` |

The root `justfile` exposes local/remote Compose deployment, backup, preparation, and inventory-generation tasks. `.mise.toml` includes role tasks and Terraform init/plan/apply/destroy tasks. These task definitions describe available operations, not evidence that operations have been run. No secret values, credentials, tokens, or private key material are included in this report.
