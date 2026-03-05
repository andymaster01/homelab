# Learning Roadmap: Grafana Monitoring for Backup Metrics

This document is the companion to the implementation plan. Each section maps to an implementation stage — read the relevant section **before** executing that stage to understand the concepts behind what we're building.

> **Prerequisite:** Read the [Terraform Multi-VM learning roadmap](learning-terraform-multi-vm.md) first for the infrastructure and configuration concepts.

---

## Stage 1: The Monitoring Stack (Prometheus, Pushgateway, Grafana)

### What we're doing
Creating Docker Compose configuration for three interconnected services that collect, store, and visualize backup metrics.

### Key Concepts

#### Prometheus — Time-series database and monitoring system
Prometheus stores **metrics**: numeric measurements with timestamps and labels.

```
resticprofile_backup_duration_seconds{profile="photos-onedrive"} 342.5  @1709337000
resticprofile_backup_duration_seconds{profile="photos-onedrive"} 356.2  @1709423400
```

**How it works:**
1. Prometheus **scrapes** (HTTP GET) metrics from targets at regular intervals (every 60s in our config)
2. Each scrape collects the current value of all metrics the target exposes
3. Values are stored in a local **time-series database** (TSDB) on disk
4. You query historical data using **PromQL**

**Key property: pull-based.** Prometheus reaches out to targets — targets don't push to Prometheus. This is great for always-running services (web servers, databases) but doesn't work for batch jobs that start, run, and exit.

#### Pushgateway — Bridge for batch jobs
The Pushgateway solves Prometheus's blind spot for short-lived processes:

```
                                    Pushgateway
resticprofile ──HTTP POST──►  [holds last value]  ◄──HTTP GET── Prometheus
  (runs 5min,                  (always running)               (scrapes every 60s)
   then exits)
```

1. Resticprofile finishes a backup and pushes metrics to the Pushgateway via HTTP POST
2. The Pushgateway stores the metrics in memory
3. Prometheus scrapes the Pushgateway like any other target
4. When resticprofile runs again, it overwrites the previous values

**Important behavior:** The Pushgateway **never expires** metrics. If a backup stops running entirely, the last pushed value stays forever. This is fine for our use case — healthchecks.io handles failure alerting, Grafana is for historical visibility.

#### Grafana — Visualization layer
Grafana **does not store data**. It connects to data sources (Prometheus in our case) and runs queries in real-time to render dashboards.

Key components:
- **Datasource**: Connection to Prometheus (`http://prometheus:9090`)
- **Dashboard**: A page containing multiple panels
- **Panel**: A single visualization (graph, stat, table) with a PromQL query
- **Variables**: Dropdown filters that modify queries dynamically

#### Grafana provisioning
Instead of manually clicking through the Grafana UI to add datasources and dashboards, you can place config files in specific directories:

```
grafana/
├── provisioning/
│   ├── datasources/prometheus.yml   # Auto-configures the Prometheus datasource
│   └── dashboards/dashboards.yml    # Tells Grafana where to find dashboard JSON files
└── dashboards/
    └── backup-stats.json            # The actual dashboard definition
```

On startup, Grafana reads these files and configures itself automatically. This makes the setup **reproducible** — if you destroy the Grafana container and recreate it, everything comes back. This is infrastructure-as-code applied to dashboards.

#### Docker named volumes
```yaml
volumes:
  prometheus_data:
    driver: local
  grafana_data:
    driver: local
```

Named volumes persist data across container restarts and recreations. Without them:
- Prometheus would lose all historical metrics
- Grafana would lose user-created dashboards, settings, and preferences

Named volumes are stored at `/var/lib/docker/volumes/` on the host. They survive `docker compose down` but not `docker compose down -v` (the `-v` flag explicitly removes volumes).

#### `honor_labels: true` in Prometheus scrape config
When Prometheus scrapes a target, it normally adds its own `job` and `instance` labels (e.g., `job="pushgateway"`, `instance="pushgateway:9091"`). These would **overwrite** any labels with the same name pushed by resticprofile.

With `honor_labels: true`, Prometheus preserves the original labels from the pushed metrics. This is critical because resticprofile pushes a `job` label like `photos-onedrive.backup` that we need for filtering in Grafana.

#### Docker Compose networking
Services in the same Docker Compose file share a **bridge network**. They can reach each other by service name:
- Prometheus reaches Pushgateway at `pushgateway:9091` (not localhost, not IP)
- Grafana reaches Prometheus at `prometheus:9090`

External access (from your browser or from resticprofile on ubuntu-01) uses the host IP + published port: `192.168.1.150:9091`.

### Alternatives worth knowing about
- **Grafana Alloy** (formerly Grafana Agent): A single binary that can scrape metrics, receive pushes, and forward to Prometheus or Grafana Cloud. Replaces both Prometheus and Pushgateway in some setups. Newer, less battle-tested.
- **VictoriaMetrics**: Prometheus-compatible TSDB that's more resource-efficient. Single binary, simpler to operate. Good choice if you outgrow Prometheus's resource usage.
- **Prometheus remote write**: Instead of storing locally, Prometheus can forward metrics to a cloud service. Grafana Cloud's free tier gives 10,000 active series with 14-day retention.

---

## Stage 2: mise and fnox Integration

### What we're doing
Registering operational commands for the monitoring stack and securely storing the Grafana admin password.

### Key Concepts

#### mise task runner
mise is a polyglot tool manager and task runner. In this project, each Ansible role defines its own `mise-tasks.toml` with shorthand commands:

```toml
["monitoring:up"]
description = "Deploy monitoring stack to monitoring-01 via Ansible"
dir = "ansible"
run = "ansible-playbook playbooks/monitoring-01.yml --tags monitoring"
```

The root `.mise.toml` includes all role task files:
```toml
[task_config]
includes = [
  "ansible/roles/monitoring/mise-tasks.toml",
  # ... other roles
]
```

Now `mise run monitoring:up` is equivalent to typing the full ansible-playbook command. This is a **convenience pattern** — it reduces cognitive load and prevents typos.

#### fnox — age-based secrets management
Secrets (passwords, API keys) shouldn't be committed to Git in plaintext. fnox encrypts them using **age**, a modern encryption tool:

1. Each secret is encrypted with your **age public key** (stored in `fnox.toml`)
2. Only the matching **age private key** (on your machine) can decrypt
3. mise's fnox plugin decrypts secrets into environment variables at runtime
4. Ansible reads them via `lookup('env', 'GRAFANA_ADMIN_PASSWORD')`

This means `fnox.toml` is safe to commit — the encrypted values are useless without your private key.

To add a new secret:
```bash
fnox set GRAFANA_ADMIN_PASSWORD "your-password-here"
```
This encrypts the value and writes it to `fnox.toml`.

---

## Stage 3: Deploying and Verifying the Stack

### What we're doing
Running the Ansible playbook to deploy all three services and verifying they work.

### Key Concepts

#### Container orchestration with Docker Compose
`docker compose up -d` does several things:
1. Pulls images if not already cached (prom/pushgateway, prom/prometheus, grafana/grafana)
2. Creates the bridge network
3. Creates named volumes
4. Starts containers in dependency order (`pushgateway` → `prometheus` → `grafana`)
5. `-d` runs in detached mode (background)

`depends_on` controls startup order but **not readiness** — Prometheus starts after Pushgateway's container starts, but doesn't wait for Pushgateway to be fully ready. In practice this is fine because Prometheus retries failed scrapes.

#### Prometheus targets
In the Prometheus UI (Status → Targets), you can see all configured scrape targets and their state:
- **UP**: Prometheus can successfully scrape the target
- **DOWN**: Scrape failed (target unreachable, wrong port, etc.)

This is the first thing to check when debugging metrics issues.

---

## Stage 4: Resticprofile Metrics Configuration

### What we're doing
Adding two configuration lines to each backup profile that enable automatic metrics export.

### Key Concepts

#### Resticprofile `prometheus-push`
A built-in feature of resticprofile. After each command (backup, forget, check), it sends metrics to a Prometheus Pushgateway via HTTP POST. No scripts needed — you just set the URL:

```toml
[photos-onedrive]
prometheus-push = "http://192.168.1.150:9091/"
```

The URL points to the Pushgateway on the monitoring VM. Resticprofile constructs the push URL automatically: `http://192.168.1.150:9091/metrics/job/photos-onedrive.backup`

#### `extended-status = true`
By default, resticprofile only pushes basic metrics: status (success/fail) and duration. With `extended-status`, it parses restic's output to extract detailed metrics:
- `files_new` — new files added to the backup
- `files_changed` — existing files that were modified
- `files_unmodified` — files that didn't change
- `added_bytes` — how much new data was stored

**This is what answers your "number of assets uploaded" requirement.**

#### Gauge vs Counter metric types
Prometheus has several metric types. The two most important:

| Type | Behavior | Example | Query pattern |
|------|----------|---------|---------------|
| **Counter** | Only goes up, resets on restart | Total HTTP requests served | Use `rate()` to get per-second rate |
| **Gauge** | Goes up and down freely | Current temperature, last backup duration | Query directly, no `rate()` |

Resticprofile pushes **gauges**. Each push is the value from the latest backup run. You query them directly: `resticprofile_backup_files_new` gives you the file count from the most recent run.

#### Push vs Pull monitoring patterns
| Pattern | How it works | Best for |
|---------|-------------|----------|
| **Pull** | Prometheus periodically fetches `/metrics` from running services | Long-running processes (web servers, databases) |
| **Push** | Jobs send metrics to a gateway when they finish | Batch jobs, cron jobs, short-lived processes |

Backups are batch jobs — they run for minutes then exit. Pull-based monitoring would miss them entirely because there's nothing to scrape between runs. The push pattern (resticprofile → Pushgateway → Prometheus) bridges this gap.

### Alternatives worth knowing about
- **`prometheus-save-to-file`**: Resticprofile can write metrics to a file instead of pushing. Prometheus then reads the file via a node_exporter textfile collector. Useful when the Pushgateway is unreachable, but requires shared volumes.
- **Log parsing with Loki**: Instead of structured metrics, you could ship resticprofile's log output to Loki and parse it with LogQL. More flexible but significantly more complex and fragile.
- **Webhooks + custom API**: Resticprofile's `run-after` hooks can execute arbitrary commands. You could `curl` a custom REST API that stores metrics in any database. Maximum flexibility but you'd build and maintain custom code.

---

## Stage 5: Grafana Dashboard and PromQL

### What we're doing
Verifying the full pipeline: backup → push → scrape → dashboard.

### Key Concepts

#### PromQL (Prometheus Query Language)
The query language for retrieving metrics from Prometheus. Basic syntax:

```
metric_name{label1="value1", label2="value2"}
```

Examples used in our dashboard:
```promql
# Latest backup status for all profiles
resticprofile_backup_status

# Duration for a specific profile
resticprofile_backup_duration_seconds{profile="photos-onedrive"}

# Files added, filtered by dashboard variable
resticprofile_backup_files_new{profile=~"$profile"}
```

The `=~` operator uses regex matching. When `$profile` is "All", Grafana substitutes a regex that matches everything.

Common PromQL functions (for future reference):
- `rate(counter[5m])` — per-second rate of a counter over 5 minutes
- `sum by (label)(metric)` — aggregate across instances
- `avg_over_time(gauge[1h])` — average of a gauge over 1 hour
- `increase(counter[24h])` — total increase of a counter over 24 hours

We don't need these for our dashboard because our metrics are simple gauges, but they're essential for monitoring web services.

#### Grafana panel types
| Panel | Best for | Our usage |
|-------|----------|-----------|
| **Stat** | Single prominent number with color | Last backup status, last duration |
| **Time series** | Trends over time (line/bar charts) | Duration history, files added over time |
| **Status history** | State timeline with colored blocks | Backup success/failure over days |
| **Table** | Tabular data | Not used, but useful for listing snapshots |
| **Gauge** | Current value against min/max | Not used, but useful for disk usage |

#### Grafana template variables
Variables create dynamic dashboards. Instead of hardcoding `profile="photos-onedrive"`:

1. Define variable `$profile` with query: `label_values(resticprofile_backup_status, profile)`
2. Grafana queries Prometheus and finds all unique values of `profile` label
3. A dropdown appears at the top of the dashboard
4. All panels use `{profile=~"$profile"}` in their queries
5. Selecting a profile in the dropdown filters all panels simultaneously

#### Value mappings
Prometheus stores numbers. Grafana value mappings translate them for humans:
```
0 → "Failed"  (red background)
1 → "Warning" (yellow background)
2 → "Success" (green background)
```

This turns a raw `resticprofile_backup_status` value of `2` into a green "Success" badge on the dashboard.

---

## Summary: Concept Map

```
┌─ Monitoring Layer ────────────────────────────────────┐
│  Resticprofile (prometheus-push, extended-status)     │
│  → Pushgateway (batch job metrics buffer)             │
│  → Prometheus (TSDB, scraping, PromQL)                │
│  → Grafana (dashboards, panels, variables, mappings)  │
└───────────────────────────────────────────────────────┘
         │
         ▼
┌─ Configuration Layer ─────────────────────────────────┐
│  Ansible (inventory, playbooks, roles, tags)          │
│  → Docker Compose (services, volumes, networks)       │
│  → fnox/age (secrets management)                      │
│  → mise (task runner)                                 │
└───────────────────────────────────────────────────────┘
```
