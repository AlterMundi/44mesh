# ZeroTier Mesh Node (Docker)

Joins a ZeroTier network using the [AlterMundi/ZeroTierOne](https://github.com/AlterMundi/ZeroTierOne)
fork (`feature/ingress-node` branch). The fork automatically installs per-node
source-based policy routing when `ingressNodeV4` is set on the network.

## Setup

```bash
cd deploy/zerotier
cp .env.example .env
# Set ZT_NETWORK_ID (and optionally ZEROTIER_IDENTITY_* to preserve identity)

docker compose up -d
```

## Authorize Member

Once the node joins, authorize it via the controller API or ztncui:

```bash
TOKEN=$(docker exec zerotier cat /var/lib/zerotier-one/authtoken.secret)
NWID=<your-network-id>
MEMBER_ID=$(docker exec zerotier zerotier-cli info | awk '{print $3}')

curl -s -X POST \
  -H "X-ZT1-AUTH: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"authorized": true}' \
  http://localhost:9993/controller/network/$NWID/member/$MEMBER_ID
```

See [../../docs/ZEROTIER.md](../../docs/ZEROTIER.md) for the full authorization procedure.

## Verify

```bash
docker exec zerotier zerotier-cli info
docker exec zerotier zerotier-cli listnetworks

# Once authorized, source routing should be active within ~30s
ip rule show | grep <mesh-address-range>
ip route show table <auto-table>
# Expected: default via <ingressNodeV4> dev zt*
```
