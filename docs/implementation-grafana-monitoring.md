# Implementation Plan: Grafana Monitoring Stack for Backup Metrics

> **How this works:** This plan is divided into stages. The agent MUST ask for confirmation before starting each stage and MUST wait for explicit approval before advancing. Never auto-advance.

> **Prerequisite:** Complete the [Terraform Multi-VM setup](implementation-terraform-multi-vm.md) first (provisions the monitoring-01 VM).

---

## Stage 1: Create the Monitoring Ansible Role

**Goal:** Create the full `monitoring` role with Docker Compose for Pushgateway, Prometheus, and Grafana.

### Files to create

**`ansible/roles/monitoring/defaults/main.yml`**:
```yaml
---
state: present
monitoring_dir: /home/ubuntu/monitoring
GRAFANA_ADMIN_PASSWORD: "{{ lookup('env', 'GRAFANA_ADMIN_PASSWORD') }}"
```

**`ansible/roles/monitoring/templates/env.j2`**:
```
GF_SECURITY_ADMIN_PASSWORD={{ GRAFANA_ADMIN_PASSWORD }}
```

**`ansible/roles/monitoring/docker/docker-compose.yml`**:
```yaml
services:
  pushgateway:
    image: prom/pushgateway:latest
    container_name: pushgateway
    restart: unless-stopped
    ports:
      - "9091:9091"

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.retention.time=180d"
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    depends_on:
      - pushgateway

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - ./grafana/dashboards:/var/lib/grafana/dashboards:ro
    env_file:
      - .env
    depends_on:
      - prometheus

volumes:
  prometheus_data:
    driver: local
  grafana_data:
    driver: local
```

**`ansible/roles/monitoring/docker/prometheus/prometheus.yml`**:
```yaml
global:
  scrape_interval: 60s
  evaluation_interval: 60s

scrape_configs:
  - job_name: "pushgateway"
    honor_labels: true
    static_configs:
      - targets: ["pushgateway:9091"]
```

**`ansible/roles/monitoring/docker/grafana/provisioning/datasources/prometheus.yml`**:
```yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
```

**`ansible/roles/monitoring/docker/grafana/provisioning/dashboards/dashboards.yml`**:
```yaml
apiVersion: 1
providers:
  - name: "default"
    orgId: 1
    folder: ""
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: false
```

**`ansible/roles/monitoring/docker/grafana/dashboards/backup-stats.json`** — Grafana dashboard JSON with:
- Template variable `$profile` from `label_values(resticprofile_backup_status, profile)`
- Row 1 (Stat panels): Last Status, Last Duration, Files Added, Data Added
- Row 2 (Time series): Duration Over Time, Files Added Over Time, Data Added Over Time, Status History
- Value mappings: 0→Failed(red), 1→Warning(yellow), 2→Success(green)

**`ansible/roles/monitoring/tasks/main.yml`** — follow the homepage role pattern (`ansible/roles/homepage/tasks/main.yml`):
1. `docker compose down` when `state == "absent"`
2. Create directory structure (monitoring dir + prometheus/ + grafana/provisioning/datasources + grafana/provisioning/dashboards + grafana/dashboards)
3. Copy docker-compose.yml
4. Copy prometheus config directory
5. Copy grafana provisioning directory (with `ansible.builtin.copy`, recursive)
6. Copy grafana dashboards directory
7. Template .env file
8. `docker compose up -d` when `state == "present"`

### STOP — Ask me to confirm before proceeding to Stage 2

---

## Stage 2: Wire Up mise Tasks + fnox Secret

**Goal:** Register the monitoring role's mise tasks and add the Grafana password secret.

### Files to create

**`ansible/roles/monitoring/mise-tasks.toml`**:
```toml
["monitoring:up"]
description = "Deploy monitoring stack to monitoring-01 via Ansible"
dir = "ansible"
run = "ansible-playbook playbooks/monitoring-01.yml --tags monitoring"

["monitoring:down"]
description = "Stop and remove monitoring stack on monitoring-01"
dir = "ansible"
run = "ansible-playbook playbooks/monitoring-01.yml --tags monitoring -e state=absent"

["monitoring:status"]
description = "Check monitoring stack container status on monitoring-01"
run = "ssh ubuntu@192.168.1.150 'docker compose -f /home/ubuntu/monitoring/docker-compose.yml ps'"

["monitoring:logs"]
description = "Tail monitoring stack logs on monitoring-01"
run = "ssh ubuntu@192.168.1.150 'docker compose -f /home/ubuntu/monitoring/docker-compose.yml logs -f'"
```

### Files to modify

**`.mise.toml`** — add to `task_config.includes`:
```
"ansible/roles/monitoring/mise-tasks.toml"
```

**`fnox.toml`** — add new secret (you'll need to run `fnox encrypt` to generate the encrypted value):
```
GRAFANA_ADMIN_PASSWORD = { provider = "age", value = "..." }
```

### Verification

```bash
mise tasks | grep monitoring
```
Expected: shows monitoring:up, monitoring:down, monitoring:status, monitoring:logs.

### STOP — Ask me to confirm before proceeding to Stage 3

---

## Stage 3: Deploy the Monitoring Stack

**Goal:** Deploy Pushgateway, Prometheus, and Grafana to monitoring-01.

### Steps

1. Deploy:
```bash
mise run monitoring:up
```

2. Verify services are running:
```bash
mise run monitoring:status
```

3. Verify endpoints (from your browser or curl):
- Pushgateway: `http://192.168.1.150:9091` — should show the Pushgateway UI
- Prometheus: `http://192.168.1.150:9090` — should show the Prometheus UI
- Grafana: `http://192.168.1.150:3000` — should show the login page (admin / your configured password)

4. In Prometheus UI, go to Status → Targets — should show pushgateway target as "UP"

### STOP — Ask me to confirm before proceeding to Stage 4

---

## Stage 4: Configure Resticprofile Metrics Export

**Goal:** Add `prometheus-push` and `extended-status` to all 3 backup profiles so they push metrics to the Pushgateway.

### Files to modify

**`ansible/roles/restic/docker/profiles.d/photos-onedrive.toml`** — add at profile level:
```toml
[photos-onedrive]
# ... existing lines ...
prometheus-push = "http://192.168.1.150:9091/"
```
And add inside `[photos-onedrive.backup]`:
```toml
extended-status = true
```

**`ansible/roles/restic/docker/profiles.d/videos-onedrive.toml`** — same pattern:
```toml
[videos-onedrive]
prometheus-push = "http://192.168.1.150:9091/"

[videos-onedrive.backup]
extended-status = true
```

**`ansible/roles/restic/docker/profiles.d/jellyfin-onedrive.toml`** — same pattern:
```toml
[jellyfin-onedrive]
prometheus-push = "http://192.168.1.150:9091/"

[jellyfin-onedrive.backup]
extended-status = true
```

### Deploy the changes

```bash
mise run restic:up
```

### STOP — Ask me to confirm before proceeding to Stage 5

---

## Stage 5: End-to-End Verification

**Goal:** Trigger a test backup and confirm metrics flow through the entire pipeline.

### Steps

1. Trigger a test backup:
```bash
mise run restic:exec:backup jellyfin-onedrive
```

2. Check Pushgateway (`http://192.168.1.150:9091`):
   - Should show `resticprofile_backup_*` metrics with labels for `jellyfin-onedrive`

3. Check Prometheus (`http://192.168.1.150:9090`):
   - Query: `resticprofile_backup_status` — should return data
   - Query: `resticprofile_backup_duration_seconds` — should show duration
   - Query: `resticprofile_backup_files_new` — should show file count

4. Check Grafana (`http://192.168.1.150:3000`):
   - Navigate to Dashboards → "Backup Stats"
   - Stat panels should show values for jellyfin-onedrive
   - Time series panels should show at least one data point

### Done!

The monitoring stack is fully operational. Future backups (photos at 02:30, videos at 02:30, jellyfin at 04:00) will automatically push metrics and populate the dashboard over time.
