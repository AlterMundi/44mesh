<!--
SPDX-FileCopyrightText: 2025 AlterMundi

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# 44Mesh

Run your own Autonomous System (AS) with BGP peering and a ZeroTier mesh network.

## Goal

Create an independent AS that:
- Announces your IP block to the Internet via BGP
- Provides connectivity to distributed nodes through a ZeroTier mesh
- Enables you to host services accessible from the public Internet

## Architecture

```
                              INTERNET
                                  │
                                  │ BGP (your AS announced globally)
                                  ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          ISP / IXP (datacenter)                             │
│                          (not under your control)                           │
└─────────────────────────────────────────────────────────────────────────────┘
                                  │
                                  │ BGP peering (eBGP)
                                  ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         BORDER ROUTER (your AS)                             │
│                                                                             │
│   ┌──────────────────────┐     ┌──────────────────────────┐                 │
│   │       BIRD           │     │       ZeroTier           │                 │
│   │  BGP AS ${BORDER_    │     │  controller + client     │                 │
│   │   ROUTER_AS}         │     │                          │                 │
│   │                      │     │  assigns IPs from range  │                 │
│   │  announces           │     │  source-routes return    │                 │
│   │  ${MESH_ADDRESS_     │     │  traffic to ISP          │                 │
│   │   RANGE}             │     │  (policy table 123)      │                 │
│   └──────────────────────┘     └──────────────────────────┘                 │
│                                                                             │
│   Connects your AS to both: Internet (BGP) and your mesh (ZeroTier)         │
└─────────────────────────────────────────────────────────────────────────────┘
                                  │
                                  │ ZeroTier mesh
                                  ▼
┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
│   Mesh Node 1    │    │   Mesh Node 2    │    │   Mesh Node N    │
│   IP from        │    │   IP from        │    │   IP from        │
│   ${MESH_        │    │   ${MESH_        │    │   ${MESH_        │
│    ADDRESS_      │    │    ADDRESS_      │    │    ADDRESS_      │
│    RANGE}        │    │    RANGE}        │    │    RANGE}        │
│   zerotier       │    │   zerotier       │    │   zerotier       │
│   (anywhere)     │    │   (anywhere)     │    │   (anywhere)     │
└──────────────────┘    └──────────────────┘    └──────────────────┘
```

## How It Works

### Outbound (mesh → Internet)

1. A mesh node (IP from `${MESH_ADDRESS_RANGE}`) wants to reach the Internet
2. The AlterMundi ZeroTier fork installs source-based policy routing on the node: traffic sourced from the node's mesh IP is routed via the ZeroTier interface to the border router
3. Border router forwards to the ISP via BGP peering (policy table 123)
4. Response arrives at the border router and is forwarded back through ZeroTier to the node

### Inbound (Internet → mesh)

1. Someone on the Internet wants to reach a mesh node IP
2. BGP routing directs traffic to your ISP (your AS is announced)
3. ISP sends to your **border router**
4. Border router forwards via ZeroTier mesh to the node

### Key Insight: Ingress Node

The border router acts as the **ingress node** for the mesh. It runs the ZeroTier controller and sets `ingressNodeV4` to its own mesh IP. Every node that joins receives this value and the AlterMundi fork automatically installs per-node source-based policy routing, directing return traffic through the border router. The border router then forwards that traffic to the ISP using a dedicated routing table.

See [docs/ZEROTIER.md](docs/ZEROTIER.md) for a full explanation of the ingress routing architecture.

## Components

| Component | Location | Purpose |
|-----------|----------|---------|
| `deploy/bird-border/` | Public server | ZeroTier controller + BGP (BIRD) — the border router |
| `deploy/zerotier-ui/` | Same server | ZeroTier web UI for member management |
| `deploy/zerotier/` | Any location | Mesh node (client) |

### Border Router + Controller (`deploy/bird-border/`)

The central component. Runs the ZeroTier controller and BGP daemon on the same host:
- **ZeroTier controller**: built from [AlterMundi/ZeroTierOne](https://github.com/AlterMundi/ZeroTierOne) (`feature/ingress-node`), manages network membership and distributes `ingressNodeV4` config to all nodes
- **BIRD**: BGP daemon, announces your IP block to the ISP
- **Ingress node**: forwards public IP traffic from the internet to mesh nodes via source-based policy routing

### ZeroTier Web UI (`deploy/zerotier-ui/`)

Web interface for authorizing members and inspecting network state. Built from
the [altermundi/zerotier-ui](https://github.com/altermundi/zerotier-ui) fork, which
adds `ingressNodeV4` configuration support. Reads the controller auth token from
the shared `zerotier_data` volume.

> **Note:** The ZeroTier controller itself runs inside `deploy/bird-border/`, not here.
> This stack only provides the web UI.

### Mesh Nodes (`deploy/zerotier/`)

Simple nodes that join the mesh:
- Run zerotier (AlterMundi fork) to establish overlay
- Receive `ingressNodeV4` config from the controller and install source routing automatically
- Can host services accessible from the Internet

## Network Addressing

| Network | CIDR | Purpose |
|---------|------|---------|
| Your AS block | ${MESH_ADDRESS_RANGE} | Public IPs announced via BGP |
| Mesh overlay | (same as above) | ZeroTier mesh uses your public block |
| BGP peering | ${BGP_NETWORK_RANGE} | Link between you and ISP |

**Note:** In this design, mesh IPs are your public IPs. This means services on mesh nodes are directly reachable from the Internet once BGP is established.

## Deployment

### Prerequisites

1. **IP allocation**: Obtain IP block from RIR (LACNIC, ARIN, etc.) or lease from provider
2. **AS number**: Obtain from RIR or use private AS (64512-65534) for testing
3. **BGP peering**: Agreement with ISP or IXP for BGP session
4. **Public server**: For ZeroTier control plane
5. **Datacenter presence**: For border router (colocation or VPS with BGP support)

### Configuration

Before deploying, copy and customize environment files:

```bash
# Root configuration (optional - for shared values)
cp .env.example .env

# Component-specific configuration
cp deploy/zerotier-ui/.env.example deploy/zerotier-ui/.env
cp deploy/bird-border/.env.example deploy/bird-border/.env
cp deploy/zerotier/.env.example deploy/zerotier/.env
cp deploy/rpi-isp/.env.example deploy/rpi-isp/.env  # if using mock ISP
```

Edit each `.env` file with your specific values. See `.env.example` files for documentation.

### 1. Deploy Border Router (contains the controller)

```bash
cd deploy/bird-border
cp .env.example .env
# Edit .env: set BGP vars; ZT_NETWORK_ID can be added after creating the network

docker compose up -d
```

See [deploy/bird-border/README.md](deploy/bird-border/README.md) for BGP configuration.

### 2. Create Mesh Network

Use the ZeroTier controller API to create the network and configure `ingressNodeV4`.

See **[docs/ZEROTIER.md](docs/ZEROTIER.md)** for the full step-by-step procedure.

### 3. Deploy ZeroTier Web UI (optional)

```bash
cd deploy/zerotier-ui
cp .env.example .env
# Edit .env with your UI password and ports

docker compose up -d --build
```

See [deploy/zerotier-ui/README.md](deploy/zerotier-ui/README.md) for details.

### 4. Deploy Mesh Nodes

```bash
cd deploy/zerotier
cp .env.example .env
# Set ZT_NETWORK_ID

docker compose up -d
```

## Testing with Mock ISP

For development without real BGP peering, use a Raspberry Pi as mock ISP.

See [deploy/rpi-isp/README.md](deploy/rpi-isp/README.md) for full mock ISP setup instructions.

```
┌─────────────────┐                    ┌─────────────────┐
│   RPi (mock)    │◄───── BGP ────────►│  Border Router  │
│ AS ${ISP_AS}    │     ${BGP_         │  AS ${BORDER_   │
│ ${ISP_IP}       │      NETWORK_      │   ROUTER_AS}    │
│                 │      RANGE}        │ ${BORDER_       │
│ announces test  │                    │  ROUTER_IP}     │
│ prefixes        │                    │                 │
│                 │ ingress node       │                 │
└─────────────────┘                    └─────────────────┘
                                              │
                                              │ mesh
                                              ▼
                                       ┌─────────────────┐
                                       │  Mesh Nodes     │
                                       │ ${MESH_         │
                                       │  ADDRESS_       │
                                       │  RANGE}         │
                                       │  zerotier       │
                                       │                 │
                                       └─────────────────┘
```

## Verification

### BGP Session
```bash
docker exec bird-border birdc show protocols
docker exec bird-border birdc show route
```

### Mesh Connectivity
```bash
docker exec zerotier zerotier-cli info
docker exec zerotier zerotier-cli listnetworks
ping <mesh-node-ip>  # other mesh nodes in ${MESH_ADDRESS_RANGE}
```

### End-to-End (from mock ISP)
```bash
# From RPi, should reach any mesh node
ping <mesh-node-ip>  # any IP in ${MESH_ADDRESS_RANGE}
```

## Security Notes

- ZeroTier containers run with `NET_ADMIN` + `SYS_ADMIN` capabilities. `SYS_ADMIN` is
  required for ZeroTier's network namespace and tun/tap device management inside Docker.
  Both capabilities are scoped to the container and do not grant host-level root access.
- Use proper TLS termination (reverse proxy) in front of the web UI for production.
- `ZTNCUI_PASSWD` is stored in plaintext in `.env` files — protect file permissions.
- Configure host firewall to restrict access to zerotier-ui ports.

## References

- [ZeroTier Documentation](https://docs.zerotier.com/)
- [BIRD Internet Routing Daemon](https://bird.network.cz/)
- [BGP RFC 4271](https://datatracker.ietf.org/doc/html/rfc4271)

## License

MIT
