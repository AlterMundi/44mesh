#!/bin/bash
set -e

# Start zerotier-one in the background
/usr/local/sbin/zerotier-one -U /var/lib/zerotier-one &
ZT_PID=$!

# Wait for zerotier to come online
echo "Waiting for ZeroTier to come online..."
while ! /usr/local/bin/zerotier-cli info 2>/dev/null | grep -q ONLINE; do
  sleep 1
done
echo "ZeroTier is ONLINE: $(/usr/local/bin/zerotier-cli info)"

# Join any networks passed as arguments
for network in "$@"; do
  echo "Joining network: $network"
  /usr/local/bin/zerotier-cli join "$network"
done

# Wait for zerotier-one process
wait $ZT_PID
