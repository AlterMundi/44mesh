# ZeroTier Mesh Node (Docker)

Joins the any89 mesh network using the [AlterMundi/ZeroTierOne](https://github.com/AlterMundi/ZeroTierOne)
fork (`feature/ingress-node` branch). Once authorized, the fork automatically
installs per-node source-based policy routing so your public mesh IP is
reachable from the internet through the border router.

## Prerequisites

- Docker + Docker Compose
- `/dev/net/tun` present on the host
- `net.ipv4.ip_forward=1` enabled:
  ```bash
  sudo sysctl -w net.ipv4.ip_forward=1
  echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-forward.conf
  ```
- The 16-character ZeroTier network ID (ask the network admin)

## Setup

```bash
cd deploy/zerotier
cp .env.example .env
# Edit .env and set ZT_NETWORK_ID=<16-char-network-id>

docker compose up -d
```

> **Note:** The image is built from source (AlterMundi C++ fork). First build
> takes 10–30 minutes depending on hardware. Subsequent starts use the cached
> image.

## Get your Node ID

After the container starts, get your node ID to share with the network admin:

```bash
docker exec zerotier zerotier-cli info
# 200 info <node-id> 1.16.1 ONLINE
```

Share the `<node-id>` (10 hex chars) with the network admin. They will
authorize your node on the controller.

## Verify (after admin authorizes you)

```bash
docker exec zerotier zerotier-cli listnetworks
# Should show: OK  ... <your-mesh-ip>/24
```

Once status is `OK`, the AlterMundi fork installs source routing within ~30s:

```bash
# Policy rule installed by fork
ip rule show | grep 138.255.89

# Routing table — must show default via 138.255.89.1 (border router)
ip route show table <table-number>

# Confirm your public IP is reachable from the internet
curl --interface <your-mesh-ip> https://ifconfig.me
# Should return your mesh IP
```

## For the Admin: Authorizing a New Member

Run this on the border router host (where the controller runs):

```bash
TOKEN=$(docker exec zerotier cat /var/lib/zerotier-one/authtoken.secret)
NWID=<network-id>
MEMBER_ID=<10-hex-node-id>

curl -s -X POST \
  -H "X-ZT1-AUTH: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"authorized": true}' \
  http://localhost:9993/controller/network/$NWID/member/$MEMBER_ID
```

See [../../docs/ZEROTIER.md](../../docs/ZEROTIER.md) for the full procedure
including IP assignment and network configuration.
