#!/bin/bash

# SPDX-FileCopyrightText: 2025 AlterMundi
#
# SPDX-License-Identifier: GPL-3.0-only

set -Eeo pipefail

if [ ! -e /dev/net/tun ]; then
    echo 'FATAL: cannot start ZeroTier One in container: /dev/net/tun not present.'
    exit 1
fi

NETWORK_ID="$1"

# Pre-seed identity files if env vars are provided
ZT_DIR=/var/lib/zerotier-one
mkdir -p "$ZT_DIR"
if [ -n "$ZEROTIER_IDENTITY_SECRET" ]; then
    echo "$ZEROTIER_IDENTITY_SECRET" > "$ZT_DIR/identity.secret"
    chmod 600 "$ZT_DIR/identity.secret"
fi
if [ -n "$ZEROTIER_IDENTITY_PUBLIC" ]; then
    echo "$ZEROTIER_IDENTITY_PUBLIC" > "$ZT_DIR/identity.public"
    chmod 644 "$ZT_DIR/identity.public"
fi
if [ -n "$ZEROTIER_API_SECRET" ]; then
    echo "$ZEROTIER_API_SECRET" > "$ZT_DIR/authtoken.secret"
    chmod 600 "$ZT_DIR/authtoken.secret"
fi

# Copy per-network config if provided and network ID is set
if [ -n "$NETWORK_ID" ] && [ -f /tmp/network.local.conf ]; then
    mkdir -p /var/lib/zerotier-one/networks.d
    cp /tmp/network.local.conf "/var/lib/zerotier-one/networks.d/${NETWORK_ID}.local.conf"
    # Empty .conf file tells the daemon to join this network on startup.
    # Without it, ZeroTier starts but never joins (only .local.conf is not enough).
    touch "/var/lib/zerotier-one/networks.d/${NETWORK_ID}.conf"
fi

exec zerotier-one -U /var/lib/zerotier-one
