# 44mesh Monitoring

Monitors netclient, netmaker, MQTT, WireGuard tunnels, and DNS health on the inference-public server. Designed to catch the netclient UDP socket leak bug early, before it cascades into system-wide DNS failure.

## Architecture

Two containers deployed alongside the existing monitoring stack:

- **process-exporter** (`:9256`) — Tracks CPU, memory, file descriptors, and threads for `netclient`, `netmaker`, `mosquitto`, and `bird` processes. Joins the external monitoring Docker network (`MONITORING_NETWORK`) so VictoriaMetrics can scrape it by container name.

- **mesh-watchdog** (`:9257`) — Custom collector that checks DNS resolution, WireGuard peer handshakes, Netmaker API health, MQTT connectivity, and system UDP socket count every 15 seconds. Runs in host network mode for accurate DNS testing.

Both are scraped by the existing VictoriaMetrics instance and visualized in Grafana under the **44mesh** folder.

## Configuration

All configuration is provided via environment variables. See `.env.example` for the full list. Key variables:

| Variable | Description |
|----------|-------------|
| `MONITORING_NETWORK` | External Docker network to join for scraping |
| `MONITORING_BASE_DIR` | Base directory for monitoring stack on the server |
| `GRAFANA_CONTAINER` | Grafana container name (for restart) |
| `GRAFANA_DATASOURCE_UID` | VictoriaMetrics datasource UID in Grafana |
| `VM_BRIDGE_GATEWAY` | Docker bridge gateway IP for host-network scraping |
| `VM_PORT` | VictoriaMetrics HTTP port |
| `WATCHDOG_PORT` | mesh-watchdog metrics port |

No defaults are provided — all values must be explicitly set.

## Deployment

Deployed automatically via CI/CD (GitHub Actions on PR to main). The workflow:

1. Loads env vars from `.env.monitoring` on the server
2. Builds and starts the monitoring containers
3. Substitutes placeholders (`${VM_BRIDGE_GATEWAY}`, `${GRAFANA_DATASOURCE_UID}`) in config files via `envsubst`
4. Merges scrape jobs into VictoriaMetrics config
5. Copies the dashboard and alert rules to Grafana
6. Reloads VictoriaMetrics and restarts Grafana

### Manual deployment

```bash
cd deploy/monitoring

# Start containers (pass your env file)
docker compose --env-file /path/to/.env.monitoring up -d --build

# Substitute placeholders in scrape config
export VM_BRIDGE_GATEWAY GRAFANA_DATASOURCE_UID
envsubst '${VM_BRIDGE_GATEWAY}' \
  < vmconfig-scrape-additions.yml > /tmp/scrape-additions-resolved.yml

# Merge scrape config (both env vars required)
ADDITIONS=/tmp/scrape-additions-resolved.yml \
  VM_CONFIG="${MONITORING_BASE_DIR}/vmconfig/scrape.yml" \
  python3 merge-scrape-config.py

# Substitute datasource UID in dashboard and alerts
envsubst '${GRAFANA_DATASOURCE_UID}' \
  < dashboards/44mesh-health.json > /tmp/44mesh-health.json
envsubst '${GRAFANA_DATASOURCE_UID}' \
  < alerting/44mesh-alerts.yml > /tmp/44mesh-alerts.yml

# Copy resolved files to Grafana
sudo mkdir -p "${MONITORING_BASE_DIR}/grafana/dashboards/44mesh"
sudo cp /tmp/44mesh-health.json "${MONITORING_BASE_DIR}/grafana/dashboards/44mesh/"
sudo mkdir -p "${MONITORING_BASE_DIR}/grafana/provisioning/alerting"
sudo cp /tmp/44mesh-alerts.yml "${MONITORING_BASE_DIR}/grafana/provisioning/alerting/"
sudo cp grafana-dashboard-provider.yml \
  "${MONITORING_BASE_DIR}/grafana/provisioning/dashboards/44mesh-provider.yml"

# Reload services
curl -s -X POST "http://127.0.0.1:${VM_PORT}/-/reload"
sudo docker restart "${GRAFANA_CONTAINER}"
```

## Production Security Notes

- **No Docker socket**: mesh-watchdog uses `wg show` directly (with `NET_ADMIN` capability) instead of mounting the Docker socket. This eliminates the risk of container escape via Docker API.
- **Bound listen address**: The watchdog HTTP server binds to `LISTEN_ADDR` (typically the Docker bridge gateway) rather than `0.0.0.0`, preventing exposure on public interfaces.
- **Resource limits**: Both containers have CPU and memory limits to prevent runaway processes from affecting other services on the host.
- **Pinned images**: Base images use specific version tags for reproducible builds.
- **Strict env validation**: mesh-watchdog validates all required environment variables at startup and fails fast if any are missing.
- **CI/CD safety**: The workflow uses `envsubst` with explicit variable lists (not `sed`) and `cancel-in-progress: true` to prevent deployment races.

> **Known limitation (C4)**: The CI/CD workflow is triggered on PR open, which means any PR to `main` triggers a production deployment. This requires branch protection rules and/or a manual approval gate to fully mitigate. Address separately.

## Alert Rules

| Alert | Trigger | Severity |
|-------|---------|----------|
| Netclient FD Leak Warning | open FDs > 1,000 for 2m | warning |
| Netclient FD Leak Critical | open FDs > 5,000 for 1m | critical |
| Netclient CPU Spike Warning | CPU > 200% for 2m | warning |
| Netclient CPU Critical | CPU > 500% for 1m | critical |
| DNS Resolution Failed | any DNS target down for 1m | critical |
| WireGuard Handshake Stale | peer handshake > 300s for 5m | warning |
| Netmaker API Down | API unreachable for 2m | critical |
| MQTT Disconnected | broker unreachable for 2m | critical |
| UDP Socket Flood | system UDP sockets > 10,000 for 1m | critical |

Alerts appear in the Grafana UI (no external notifications configured).

## Metrics Reference

### process-exporter metrics (per process group)

| Metric | Description |
|--------|-------------|
| `namedprocess_namegroup_open_filedesc` | Open file descriptor count |
| `namedprocess_namegroup_cpu_seconds_total` | CPU time (use `rate()` for %) |
| `namedprocess_namegroup_memory_bytes` | Memory by type (resident, virtual) |
| `namedprocess_namegroup_num_threads` | Thread count |
| `namedprocess_namegroup_num_procs` | Process count (alive check) |
| `namedprocess_namegroup_worst_fd_ratio` | FD usage / FD limit ratio |

### mesh-watchdog metrics

| Metric | Description |
|--------|-------------|
| `mesh_dns_up` | DNS resolution success (1/0) |
| `mesh_dns_latency_seconds` | DNS query latency |
| `mesh_wg_peers_total` | WireGuard peer count |
| `mesh_wg_peer_handshake_seconds_ago` | Seconds since last handshake |
| `mesh_wg_peer_transfer_rx_bytes` | Bytes received per peer |
| `mesh_wg_peer_transfer_tx_bytes` | Bytes sent per peer |
| `mesh_netmaker_api_up` | API reachability (1/0) |
| `mesh_netmaker_api_latency_seconds` | API response time |
| `mesh_mqtt_up` | MQTT connectivity (1/0) |
| `mesh_udp_sockets_total` | System-wide UDP socket count |

## Files

```
docker-compose.yml              # Container definitions
process-exporter.yml            # Process matching rules
Dockerfile.watchdog             # mesh-watchdog image
mesh-watchdog.sh                # Metric collector + HTTP server
vmconfig-scrape-additions.yml   # VictoriaMetrics scrape jobs (template)
merge-scrape-config.py          # Scrape config merger
grafana-dashboard-provider.yml  # Dashboard folder provider
dashboards/44mesh-health.json   # Grafana dashboard (template)
alerting/44mesh-alerts.yml      # Grafana alert rules (template)
.env.example                    # Required environment variables
```
