#!/bin/bash
set -euo pipefail

MAX_WAIT="${MAX_WAIT:-60}"

echo "=== BIRD Border Router ==="
echo "AS: ${BORDER_ROUTER_AS:-unknown}, Router ID: ${BORDER_ROUTER_IP:-unknown}"
echo "Peering with ISP at ${ISP_IP:-unknown} (AS ${ISP_AS:-unknown})"

# Find ZeroTier interface (zt*)
find_interface() {
    ip -o link show | awk -F': ' '{print $2}' | grep -E '^zt' | head -1
}

echo "Waiting for ZeroTier interface..."

waited=0
while true; do
    INTERFACE=$(find_interface)
    if [ -n "$INTERFACE" ]; then
        break
    fi
    if [ $waited -ge $MAX_WAIT ]; then
        echo "ERROR: No zt* interface found after ${MAX_WAIT}s"
        ip link show
        exit 1
    fi
    sleep 2
    waited=$((waited + 2))
    echo "  waiting... (${waited}s)"
done

echo "Found interface: $INTERFACE"
ip addr show "$INTERFACE" | grep -E "inet |link/"

# Source-based policy routing for ZeroTier mesh ingress
# Packets arriving from ZeroTier nodes (src in MESH_ADDRESS_RANGE) must be
# routed back out via the ISP BGP peer, not the default route. Without this,
# return traffic for connections originating from mesh nodes goes out the
# wrong interface and is dropped or RPF-rejected by the ISP.
MESH_ROUTE_TABLE="${MESH_ROUTE_TABLE:-123}"
echo "Setting up source routing: from ${MESH_ADDRESS_RANGE} via ${ISP_IP} (table ${MESH_ROUTE_TABLE})"
ip rule add from "${MESH_ADDRESS_RANGE}" lookup "${MESH_ROUTE_TABLE}" 2>/dev/null \
    && echo "  added: ip rule from ${MESH_ADDRESS_RANGE} lookup ${MESH_ROUTE_TABLE}" \
    || echo "  already present: ip rule from ${MESH_ADDRESS_RANGE} lookup ${MESH_ROUTE_TABLE}"
ip route replace default via "${ISP_IP}" table "${MESH_ROUTE_TABLE}" \
    && echo "  added: ip route default via ${ISP_IP} table ${MESH_ROUTE_TABLE}" \
    || echo "  failed: ip route default via ${ISP_IP} table ${MESH_ROUTE_TABLE}"

# Generate BIRD configuration from template
echo "Generating BIRD configuration from template..."
envsubst < /etc/bird/bird.conf.template > /etc/bird/bird.conf

# Verify generated configuration
echo "Verifying BIRD configuration..."
bird -p -c /etc/bird/bird.conf || {
    echo "ERROR: Invalid BIRD configuration generated!"
    echo "--- Generated config ---"
    cat /etc/bird/bird.conf
    exit 1
}

# Prepare BIRD runtime directory
mkdir -p /run/bird
chown bird:bird /run/bird

echo "Starting BIRD..."
exec bird -f -c /etc/bird/bird.conf
