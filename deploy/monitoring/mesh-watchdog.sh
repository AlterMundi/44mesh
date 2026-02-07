#!/bin/sh
set -eu

# --- Validate required environment variables ---
for var in LISTEN_PORT LISTEN_ADDR COLLECT_INTERVAL NETMAKER_API_URL MQTT_HOST MQTT_PORT DNS_TEST_DOMAIN DNS_TEST_INTERNAL; do
    eval val=\$$var
    [ -n "$val" ] || { echo "ERROR: $var is required"; exit 1; }
done
[ "$COLLECT_INTERVAL" -gt 0 ] 2>/dev/null || { echo "ERROR: COLLECT_INTERVAL must be a positive integer"; exit 1; }

METRICS_FILE="/app/data/metrics.prom"

# Calculate elapsed time in seconds from nanosecond timestamps
elapsed_sec() {
    echo "$1 $2" | awk '{printf "%.6f", ($2 - $1) / 1000000000}'
}

# Get current time in nanoseconds (fallback to seconds * 1e9 if date +%N unsupported)
now_ns() {
    local ns
    ns=$(date +%s%N 2>/dev/null)
    if [ ${#ns} -lt 15 ]; then
        # %N not supported, use seconds
        echo "$(date +%s)000000000"
    else
        echo "$ns"
    fi
}

collect_dns() {
    local target="$1" type="$2" tmpfile="$3"
    local start end

    start=$(now_ns)
    if dig +short +timeout=3 +tries=1 "$target" A 2>/dev/null | grep -q '^[0-9]'; then
        end=$(now_ns)
        echo "mesh_dns_up{target=\"$target\",type=\"$type\"} 1" >> "$tmpfile"
        echo "mesh_dns_latency_seconds{target=\"$target\",type=\"$type\"} $(elapsed_sec "$start" "$end")" >> "$tmpfile"
    else
        echo "mesh_dns_up{target=\"$target\",type=\"$type\"} 0" >> "$tmpfile"
        echo "mesh_dns_latency_seconds{target=\"$target\",type=\"$type\"} 0" >> "$tmpfile"
    fi
}

collect_wireguard() {
    local tmpfile="$1"
    local wg_dump peer_count now

    wg_dump=$(wg show all dump 2>/dev/null || echo "")
    peer_count=0
    now=$(date +%s)

    if [ -n "$wg_dump" ]; then
        # wg show all dump: peer lines have 9 tab-separated fields
        # interface pubkey psk endpoint allowed-ips handshake rx tx keepalive
        peer_count=$(echo "$wg_dump" | awk -F'\t' 'NF==9{n++} END{print n+0}')

        echo "$wg_dump" | awk -F'\t' -v now="$now" 'NF==9 {
            peer = substr($2, 1, 8)
            split($5, ips, ",")
            first_ip = ips[1]
            handshake = $6
            rx = $7
            tx = $8

            if (handshake > 0) {
                age = now - handshake
            } else {
                age = -1
            }
            printf "mesh_wg_peer_handshake_seconds_ago{peer=\"%s\",allowed_ips=\"%s\"} %d\n", peer, first_ip, age
            printf "mesh_wg_peer_transfer_rx_bytes{peer=\"%s\",allowed_ips=\"%s\"} %s\n", peer, first_ip, rx
            printf "mesh_wg_peer_transfer_tx_bytes{peer=\"%s\",allowed_ips=\"%s\"} %s\n", peer, first_ip, tx
        }' >> "$tmpfile"
    fi

    echo "mesh_wg_peers_total $peer_count" >> "$tmpfile"
}

collect_netmaker_api() {
    local tmpfile="$1"
    local start end api_code

    start=$(now_ns)
    api_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$NETMAKER_API_URL/api/server/health" 2>/dev/null || echo "000")
    end=$(now_ns)

    if [ "$api_code" -ge 200 ] 2>/dev/null && [ "$api_code" -lt 500 ] 2>/dev/null; then
        echo "mesh_netmaker_api_up 1" >> "$tmpfile"
    else
        echo "mesh_netmaker_api_up 0" >> "$tmpfile"
    fi
    echo "mesh_netmaker_api_latency_seconds $(elapsed_sec "$start" "$end")" >> "$tmpfile"
}

collect_mqtt() {
    local tmpfile="$1"

    if mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -t '$SYS/#' -C 1 -W 3 >/dev/null 2>&1; then
        echo "mesh_mqtt_up 1" >> "$tmpfile"
    else
        echo "mesh_mqtt_up 0" >> "$tmpfile"
    fi
}

collect_udp_sockets() {
    local tmpfile="$1"
    local udp_inuse=0

    if [ -f /host/proc/net/sockstat ]; then
        udp_inuse=$(awk '/^UDP:/{print $3}' /host/proc/net/sockstat 2>/dev/null || echo "0")
    elif [ -f /proc/net/sockstat ]; then
        udp_inuse=$(awk '/^UDP:/{print $3}' /proc/net/sockstat 2>/dev/null || echo "0")
    fi
    echo "mesh_udp_sockets_total $udp_inuse" >> "$tmpfile"
}

collect_metrics() {
    local tmpfile="/app/data/metrics.prom.tmp"
    local start end duration

    start=$(now_ns)

    cat > "$tmpfile" << 'HEADER'
# HELP mesh_dns_up DNS resolution test result (1=success, 0=failure)
# TYPE mesh_dns_up gauge
# HELP mesh_dns_latency_seconds DNS resolution latency in seconds
# TYPE mesh_dns_latency_seconds gauge
# HELP mesh_wg_peers_total Number of WireGuard peers
# TYPE mesh_wg_peers_total gauge
# HELP mesh_wg_peer_handshake_seconds_ago Seconds since last WireGuard handshake (-1 if never)
# TYPE mesh_wg_peer_handshake_seconds_ago gauge
# HELP mesh_wg_peer_transfer_rx_bytes Bytes received from WireGuard peer
# TYPE mesh_wg_peer_transfer_rx_bytes counter
# HELP mesh_wg_peer_transfer_tx_bytes Bytes sent to WireGuard peer
# TYPE mesh_wg_peer_transfer_tx_bytes counter
# HELP mesh_netmaker_api_up Netmaker API reachable (1=up, 0=down)
# TYPE mesh_netmaker_api_up gauge
# HELP mesh_netmaker_api_latency_seconds Netmaker API response latency in seconds
# TYPE mesh_netmaker_api_latency_seconds gauge
# HELP mesh_mqtt_up MQTT broker reachable (1=up, 0=down)
# TYPE mesh_mqtt_up gauge
# HELP mesh_udp_sockets_total System-wide UDP socket count
# TYPE mesh_udp_sockets_total gauge
# HELP mesh_collector_duration_seconds Time taken to collect all metrics
# TYPE mesh_collector_duration_seconds gauge
# HELP mesh_collector_up Whether the last collection cycle succeeded (1=yes)
# TYPE mesh_collector_up gauge
HEADER

    collect_dns "$DNS_TEST_DOMAIN" "external" "$tmpfile"
    collect_dns "$DNS_TEST_INTERNAL" "internal" "$tmpfile"
    collect_wireguard "$tmpfile"
    collect_netmaker_api "$tmpfile"
    collect_mqtt "$tmpfile"
    collect_udp_sockets "$tmpfile"

    end=$(now_ns)
    duration=$(elapsed_sec "$start" "$end")
    echo "mesh_collector_duration_seconds $duration" >> "$tmpfile"
    echo "mesh_collector_up 1" >> "$tmpfile"

    # Atomic replace
    mv "$tmpfile" "$METRICS_FILE"
}

# --- Background collector loop ---
collect_loop() {
    while true; do
        if ! collect_metrics; then
            echo "mesh_collector_up 0" > "$METRICS_FILE"
        fi
        sleep "$COLLECT_INTERVAL"
    done
}

# Initialize
echo "# mesh-watchdog starting" > "$METRICS_FILE"

# Start collector in background
collect_loop &
COLLECTOR_PID=$!

echo "mesh-watchdog: collector running (pid=$COLLECTOR_PID, interval=${COLLECT_INTERVAL}s)"
echo "mesh-watchdog: starting HTTP server on ${LISTEN_ADDR}:${LISTEN_PORT}"

# --- Python HTTP server for /metrics ---
# exec replaces the shell; Python handles SIGTERM by killing the collector child
exec python3 -c "
import http.server
import os
import signal
import sys

METRICS_FILE = '${METRICS_FILE}'
PORT = ${LISTEN_PORT}
LISTEN_ADDR = '${LISTEN_ADDR}'
COLLECTOR_PID = ${COLLECTOR_PID}

def shutdown(signum, frame):
    try:
        os.kill(COLLECTOR_PID, signal.SIGTERM)
    except ProcessLookupError:
        pass
    sys.exit(0)

class MetricsHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/metrics':
            try:
                with open(METRICS_FILE, 'r') as f:
                    content = f.read()
                self.send_response(200)
                self.send_header('Content-Type', 'text/plain; version=0.0.4; charset=utf-8')
                self.end_headers()
                self.wfile.write(content.encode())
            except FileNotFoundError:
                self.send_response(503)
                self.end_headers()
        elif self.path == '/health':
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'ok')
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass

signal.signal(signal.SIGTERM, shutdown)
signal.signal(signal.SIGINT, shutdown)
server = http.server.HTTPServer((LISTEN_ADDR, PORT), MetricsHandler)
server.serve_forever()
"
