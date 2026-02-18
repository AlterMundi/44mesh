#!/bin/bash
set -e

ZT_DIR=/var/lib/zerotier-one

# Pre-seed identity files if env vars are provided
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

# Pre-seed controller-safe per-network settings for each network we will join.
# allowDefault=0 is critical: the controller IS the mesh gateway (ingressNodeV4 points
# here), so accepting a default route from the network it controls creates a routing loop.
mkdir -p "$ZT_DIR/networks.d"
for network in "$@"; do
  if [ -n "$network" ]; then
    conf="$ZT_DIR/networks.d/${network}.local.conf"
    if [ ! -f "$conf" ]; then
      printf 'allowManaged=1\nallowGlobal=1\nallowDefault=0\nallowDNS=0\n' > "$conf"
      echo "Pre-seeded $conf (allowDefault=0)"
    fi
  fi
done

# Start zerotier-one in the background
/usr/local/sbin/zerotier-one -U "$ZT_DIR" &
ZT_PID=$!

# Wait for zerotier to come online
echo "Waiting for ZeroTier to come online..."
while ! /usr/local/bin/zerotier-cli info 2>/dev/null | grep -q ONLINE; do
  sleep 1
done
echo "ZeroTier is ONLINE: $(/usr/local/bin/zerotier-cli info)"

# Join any networks passed as arguments (skip empty strings)
for network in "$@"; do
  if [ -n "$network" ]; then
    echo "Joining network: $network"
    /usr/local/bin/zerotier-cli join "$network"
  fi
done

# Wait for zerotier-one process
wait $ZT_PID
