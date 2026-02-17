#!/bin/sh
set -e

NETWORK_ID="$1"

# Copy per-network config if provided and network ID is set
if [ -n "$NETWORK_ID" ] && [ -f /tmp/network.local.conf ]; then
    mkdir -p /var/lib/zerotier-one/networks.d
    cp /tmp/network.local.conf "/var/lib/zerotier-one/networks.d/${NETWORK_ID}.local.conf"
fi

exec zerotier-one "$@"
