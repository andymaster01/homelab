# Komodo installation plan

## Goal

Install Komodo as the management UI for the three existing Docker VMs. Use the active `containers/` deployment format and leave the application stacks in their current locations and deployment workflows.

| Role | Host | Address |
| --- | --- | --- |
| Komodo Core and MongoDB, plus Periphery | `ubuntu-01` | `192.168.1.130` |
| Periphery | `ubuntu-02` | `192.168.1.131` |
| Periphery | `eiko-02-151` | `192.168.1.151` |

This places Core on an existing Docker VM. If that VM is down, Komodo’s dashboard is unavailable until it returns, though the other Docker hosts continue running their containers.

## Preflight results (2026-10-06)

- Docker is responding on all three VMs: Engine `29.8.1` on `ubuntu-01`, and `29.8.2` on `ubuntu-02-131` and `eiko-02-151`.
- `ubuntu-01` has 17 GB free on `/` and the shared `/mnt/containers-data` mount reports 1.3 TB free. It currently runs Homepage on port 80; no process is listening on Komodo’s default port 9120.
- `ubuntu-02-131` has 6.5 GB free on `/`; `eiko-02-151` has 11 GB free. Both mount the same shared data filesystem.
- `ubuntu-02-131` and `eiko-02-151` have routes to and can ping `192.168.1.130`. All three VMs run Ubuntu 24.04.5 LTS on x86_64 with kernel `6.8.0-142-generic`.
- Proposed LAN UI and agent endpoint: `http://192.168.1.130:9120` / `ws://192.168.1.130:9120`. The port is free on the Core VM; check any host or network firewall rule after deployment.
- Pin Core and Periphery to Komodo `2.3.3`, the latest stable release found during this preflight. Pin MongoDB to `8.0.32`; Komodo’s official example uses the unpinned `mongo` tag. The three pinned image manifests are available for this host’s registry access; verify MongoDB starts cleanly during deployment.

Docker and route checks passed. Confirming TCP/UI access from the other VMs and validating the pinned MongoDB image remain deployment checks because Komodo is not running yet.

## Components and choices

- **Komodo Core** provides the web UI and API.
- **MongoDB** is Komodo’s recommended database and holds resource configuration, user accounts, audit logs, and system state.
- **Periphery** runs on each managed Docker host. Use the systemd installation, which Komodo recommends over running Periphery in a container.
- Use Komodo v2 and pin Core, MongoDB, and Periphery to explicit version tags when implementing the Compose and agent setup. Keep Core and Periphery on compatible Komodo releases. Do not use `latest`.
- Use Periphery outbound connections to Core where supported, so the Docker VMs do not need an agent port opened for inbound access. Restrict access to the Core UI to the trusted LAN or existing private access path.

Komodo agents need access to the Docker socket and therefore have broad control over each host’s containers and images. Keep Komodo administration limited to trusted users and do not expose the Docker API publicly.

## Repository changes

Add an active service directory `containers/komodo/` with:

- `docker-compose.yml` for Komodo Core and MongoDB, with persistent database and Core key/config storage.
- `config.json` targeting `ubuntu-01` (`192.168.1.130`) and its compose directory, following the existing container deployment schema.
- `.env.local` and `.env.remote` for non-secret deployment settings, following nearby container conventions. Put credentials and other secrets in the existing `fnox` workflow; do not commit them.

The Core web port should be reachable from the LAN without conflicting with Homepage on port 80. Keep MongoDB internal to the Compose network and do not publish its port. Confirm the chosen Core port and proxy/access path before deployment.

Do not add Periphery as a Compose service to the application hosts; install it there as a systemd service using Komodo’s onboarding flow. Do not store onboarding keys in the repository or shell history.

## Installation sequence

### 1. Preflight

1. Confirm Docker is healthy and there is adequate free space on `ubuntu-01` for Komodo and MongoDB persistent data.
2. Confirm all three VMs can reach `ubuntu-01` over the private network and that the intended UI port is not already in use.
3. Use the Komodo `2.3.3` Core and Periphery versions and MongoDB `8.0.32` recorded above; validate the MongoDB image against Komodo at first startup.
4. Decide the LAN-only URL/port for Core. Configure an existing trusted reverse proxy only if needed; do not expose MongoDB or Docker APIs.

### 2. Deploy Core and MongoDB

1. Add and review the `containers/komodo/` files described above. Persist MongoDB data and Core keys across container recreation.
2. Run the repository’s Compose validation/deploy workflow for Komodo on `ubuntu-01` once implemented.
3. Check `docker compose ps` and startup logs for both services. Confirm the UI loads and create the first administrator account.
4. Configure Komodo’s database backup destination and schedule. Ensure the backup files are covered by the host’s backup plan, and document a restore path before relying on Komodo state.

### 3. Onboard the three Docker servers

1. In Komodo, create a short-lived onboarding key for each host. Keep each key out of Git and remove it from transient notes after use.
2. Install Periphery as a systemd service on `ubuntu-01`, `ubuntu-02-131` (display as `ubuntu-02`), and `eiko-02-151`, passing the reachable Core address and intended Komodo server name.
3. Verify the service is enabled and running after reboot, and verify each server reports a healthy connection in Komodo.
4. Confirm Core can view each host’s Docker containers, images, and container logs. Use Komodo’s UI to inspect image cleanup controls, but do not prune images during installation.

### 4. Acceptance checks

- Komodo Core and MongoDB restart without losing configuration or credentials.
- All three Periphery servers reconnect after a VM reboot.
- Each server’s container list and per-container logs are visible.
- Host disk capacity/free space is visible for each VM.
- Komodo data can be restored from a backup using the documented procedure.
- Verify whether Komodo reports **per-container volume disk usage** at the required level of detail. Host disk statistics and Docker image/container summaries do not necessarily provide a per-volume breakdown; if Komodo does not show it, record that as a separate monitoring requirement rather than assuming it is covered.

Keep the existing `just deploy-remote <container>` workflow as the deployment source of truth during the initial rollout. Add Compose stacks to Komodo only if a later decision is made to manage deployments there.

## Rollback

1. Stop Komodo Core and MongoDB through the Komodo Compose project on `ubuntu-01` if the UI or database is unhealthy.
2. Stop and disable the Periphery systemd service on any host where it causes a problem. Existing application containers should continue to run independently.
3. Preserve the Komodo data directory and database backup for diagnosis. If restoring, use the matching Komodo backup procedure and compatible Core version.

## References

- [Komodo setup](https://komo.do/docs/setup)
- [MongoDB setup](https://komo.do/docs/setup/mongo)
- [Connect more servers](https://komo.do/docs/setup/connect-servers)
- [Komodo v2 release and compatibility notes](https://komo.do/docs/releases/v2.0.0)
- [Backup and restore](https://komo.do/docs/setup/backup)
