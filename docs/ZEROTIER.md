# ZeroTier Mesh — Architecture & Operations Guide

This document describes the ZeroTier-based mesh used in 44mesh, including the
custom ingress routing architecture that makes each mesh node reachable at a
public IP directly announced via BGP.

---

## Architecture Overview

```
                Internet
                    │
        BGP announces 138.255.89.0/24
                    │
         ┌──────────▼──────────┐
         │   Border Router     │  inference.altermundi.net
         │   (inference)       │  131.72.205.6 (public)
         │                     │
         │  zerotier controller│  138.255.89.1 (ZT IP)
         │  bird (BGP AS XXXX) │  10.20.30.1   (BGP peering)
         │                     │
         │  Source routing:    │
         │  from .89/24 → ISP  │
         └──────────┬──────────┘
                    │ ZeroTier overlay
          ┌─────────┴──────────┐
          │                    │
   ┌──────▼──────┐     ┌───────▼─────┐
   │  Node A     │     │  Node B     │
   │138.255.89.10│     │138.255.89.240│
   │             │     │             │
   │ reachable   │     │ reachable   │
   │ from internet     │ from internet
   └─────────────┘     └─────────────┘
```

Each mesh node gets a public IP from the announced range. Inbound traffic for
any node IP arrives at the border router via BGP, is forwarded through the
ZeroTier overlay, and the node's return traffic is source-routed back through
the border router to the ISP — fully transparent to the internet.

---

## Components

| Component | Location | Purpose |
|-----------|----------|---------|
| ZeroTier controller | `deploy/bird-border/` | Manages network membership, distributes config |
| BIRD | `deploy/bird-border/` | BGP daemon, announces mesh prefix to ISP |
| ZeroTier client | `deploy/zerotier/` | Mesh node, receives public IP, sets up ingress routing |
| ztncui | `deploy/zerotier-controller/` | Web UI for controller (member management) |

All ZeroTier binaries are built from the
[AlterMundi/ZeroTierOne](https://github.com/AlterMundi/ZeroTierOne) fork
(`feature/ingress-node` branch), which adds source-based policy routing driven
by a per-network `ingressNodeV4` configuration field.

---

## How the Ingress Routing Works

When a network has `ingressNodeV4` set, the AlterMundi fork automatically
configures source-based policy routing on every node that joins:

**On the border router (controller):**
- `allowDefault=0` is pre-seeded by `controller-entrypoint.sh` — the border
  router does NOT accept a default route from the mesh it controls (doing so
  would create a routing loop back to itself).
- `bird/entrypoint.sh` installs host-level policy rules:
  ```
  ip rule add from 138.255.89.0/24 lookup 123
  ip route add default via <ISP_BGP_PEER> table 123
  ```
  Any traffic arriving from mesh nodes (source in mesh range) is routed out via
  the ISP BGP peer — not the default route.

**On each mesh node (client):**
- `allowDefault=1` is pre-seeded by the client `entrypoint.sh` via
  `network.local.conf`.
- The AlterMundi fork reads `ingressNodeV4` from the controller-pushed network
  config and installs:
  ```
  ip rule add from <node-ip>/32 lookup <auto-table>
  ip route add default via <ingressNodeV4> dev zt* table <auto-table>
  ```
  All traffic sourced from the node's mesh IP is routed through the ZeroTier
  interface toward the border router, which forwards it to the internet.

The result: from the internet, each node IP is reachable directly; replies
follow the correct asymmetric path back through the border router.

---

## Creating a New Mesh Network

This is a one-time operation per deployment. Networks persist in the controller
volume; as long as the volume is preserved the network ID and all member
assignments survive redeployments.

### Prerequisites

- Controller running (`deploy/bird-border/` deployed and healthy)
- Controller node has joined and received a ZT IP on the new network
- `TOKEN=$(docker exec zerotier cat /var/lib/zerotier-one/authtoken.secret)`

### Step 1 — Create the network

Create an empty network and note the assigned ID:

```bash
TOKEN=$(docker exec zerotier cat /var/lib/zerotier-one/authtoken.secret)
NODE_ID=$(docker exec zerotier zerotier-cli info | awk '{print $3}')

# POST to controller-id______ to auto-generate a network ID
curl -s -X POST \
  -H "X-ZT1-AUTH: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}' \
  http://localhost:9993/controller/network/${NODE_ID}______

# Note the returned "nwid" — that is your ZT_NETWORK_ID
```

### Step 2 — Join the network from the controller

```bash
NWID=<your-network-id>
docker exec zerotier zerotier-cli join $NWID
```

Wait for the controller to assign itself an IP (it's both controller and member):

```bash
docker exec zerotier zerotier-cli listnetworks
# Wait until status shows OK and an IP appears in the last column
```

### Step 3 — Apply full network configuration

Edit `deploy/zerotier-controller/network-config-example.json`: replace
`138.255.89` with your actual public `/24` block, update `name` and `dns.domain`
as needed, and set `ingressNodeV4` to the ZT IP the controller received
(e.g. `138.255.89.1`).

```bash
ZT_IP=$(docker exec zerotier zerotier-cli get $NWID ip 2>/dev/null | head -1 | cut -d/ -f1)
echo "Controller ZT IP: $ZT_IP  → set as ingressNodeV4"

# Edit the example JSON, then apply:
curl -s -X POST \
  -H "X-ZT1-AUTH: $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$(cat deploy/zerotier-controller/network-config-example.json | python3 -c \
    'import sys,json; d=json.load(sys.stdin); d.pop("_comment",None); print(json.dumps(d))')" \
  http://localhost:9993/controller/network/$NWID | python3 -m json.tool
```

Verify `ingressNodeV4` is stored:

```bash
curl -s -H "X-ZT1-AUTH: $TOKEN" \
  http://localhost:9993/controller/network/$NWID | python3 -m json.tool | grep ingressNode
```

### Step 4 — Update `.env` with the network ID

In both `deploy/bird-border/.env` and `deploy/zerotier/.env`:

```
ZT_NETWORK_ID=<your-network-id>
```

---

## Authorizing a New Node

When a new node joins, it appears in the controller as unauthorized. Authorize
it via the API or ztncui, and enable **Allow Global** so the node accepts
the public IP range:

```bash
MEMBER_ID=<10-hex-char-node-id>

# Authorize + set allowGlobal
curl -s -X POST \
  -H "X-ZT1-AUTH: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"authorized": true, "activeBridge": false}' \
  http://localhost:9993/controller/network/$NWID/member/$MEMBER_ID

# Verify
curl -s -H "X-ZT1-AUTH: $TOKEN" \
  http://localhost:9993/controller/network/$NWID/member/$MEMBER_ID \
  | python3 -m json.tool | grep -E 'authorized|ipAssign'
```

The controller auto-assigns an IP from the pool. The node does not need manual
IP assignment unless a specific address is required.

---

## Deploying a Mesh Node (Client)

```bash
cd deploy/zerotier
cp .env.example .env
# Set ZT_NETWORK_ID (and optionally ZEROTIER_IDENTITY_* to preserve identity)

docker compose up -d --build
```

Once the node is authorized, the AlterMundi fork installs source routing
automatically within ~30 seconds. Verify:

```bash
# Policy rule should appear (from <node-ip>/32 lookup <table>)
ip rule show | grep 138.255.89

# Custom table should have default via border router ZT IP
ip route show table <table-number>
# Expected:
#   0.0.0.0/1   via 138.255.89.1 dev zt* ...
#   128.0.0.0/1 via 138.255.89.1 dev zt* ...

# Confirm public IP as seen from internet
curl --interface <node-ip> https://ifconfig.me
# Should return the node's mesh IP
```

---

## Deploying the Border Router

See `deploy/bird-border/README.md` for the full BGP setup. Key additional
requirements for the ingress architecture:

1. **`ingressNodeV4` must be set** on the network (Step 3 above) before nodes
   join — or existing nodes must restart/re-fetch config after it is set.

2. **Source routing is automatic** — `bird/entrypoint.sh` installs the
   `ip rule` and `ip route` entries at startup using `$ISP_IP` and
   `$MESH_ADDRESS_RANGE` from the environment.

3. **`allowDefault=0`** is pre-seeded by `controller-entrypoint.sh` for every
   network the controller joins, preventing the routing loop that would occur if
   the border router accepted its own default route advertisement.

---

## Troubleshooting

### Node IP not reachable from internet

1. Check BGP is established and exporting the prefix:
   ```bash
   docker exec bird-border birdc show protocols
   docker exec bird-border birdc show route export isp
   ```

2. Check source routing is active on the border router:
   ```bash
   ip rule show | grep <mesh-range>
   ip route show table 123
   ```

3. Check the node has applied source routing:
   ```bash
   ip rule show | grep <node-ip>
   ip route show table <auto-table>
   # Must show: default via <ingressNodeV4> dev zt*
   ```
   If missing, `ingressNodeV4` was not set when the node joined. Set it on the
   network (Step 3) then restart the node container.

4. Check `allowDefault=1` on the node:
   ```bash
   cat /var/lib/zerotier-one/networks.d/<nwid>.local.conf
   # Must have: allowDefault=1
   ```
   The client container entrypoint sets this automatically via `network.local.conf`.
   Native (non-Docker) installs must set it manually.

### BGP session not establishing

```bash
docker exec bird-border birdc show protocols all isp
ping $ISP_IP   # must be reachable on the peering interface
```

### Controller API returns 401

```bash
TOKEN=$(docker exec zerotier cat /var/lib/zerotier-one/authtoken.secret)
```

Token rotates on container restart; always read it fresh.

---

## Fork: AlterMundi/ZeroTierOne

The `feature/ingress-node` branch adds:

- **`ingressNodeV4` network field**: controller distributes a public IP address
  to all members as the designated ingress node.
- **Per-node source routing**: when `ingressNodeV4` is set and `allowDefault=1`,
  the fork installs `/32` policy rules and a default route via the ingress node
  in a dedicated routing table. Traffic from the node's mesh IP always exits via
  the border router — even when the node is behind NAT.
- **Deadlock fix** (`_networks_m`): the upstream code deadlocked on network join
  when the `ZT_VIRTUAL_NETWORK_CONFIG_OPERATION_UP` callback tried to re-acquire
  a mutex already held by `Node::join()`. Fixed with a `canQueryNode` guard in
  `syncManagedStuff()`.
