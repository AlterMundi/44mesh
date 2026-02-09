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
│   ┌─────────────┐     ┌─────────────┐     ┌─────────────┐                  │
│   │    BIRD     │     │  zerotier   │     │  Egress GW  │                  │
│   │  AS 65000   │     │  (Mesh)     │     │  announces  │                  │
│   │             │     │             │     │  routes to  │                  │
│   │ announces:  │     │ mesh IP:    │     │  mesh       │                  │
│   │ ${MESH_    │     │ from range  │     │             │                  │
│   │  ADDRESS_   │     │             │     │             │                  │
│   └─────────────┘     └─────────────┘     └─────────────┘                  │
│                                                                             │
│   Connects your AS to both: Internet (BGP) and your mesh (ZeroTier)        │
└─────────────────────────────────────────────────────────────────────────────┘
                                  │
                                  │ ZeroTier mesh
                                  ▼
┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
│   Mesh Node 1    │    │   Mesh Node 2    │    │   Mesh Node N    │
│   IP from        │    │   IP from        │    │   IP from        │
│   ${MESH_       │    │   ${MESH_       │    │   ${MESH_       │
│    ADDRESS_      │    │    ADDRESS_      │    │    ADDRESS_      │
│    RANGE}        │    │    RANGE}        │    │    RANGE}        │
│   zerotier       │    │   zerotier       │    │   zerotier       │
│   (anywhere)     │    │   (anywhere)     │    │   (anywhere)     │
└──────────────────┘    └──────────────────┘    └──────────────────┘
```

## How It Works

### Outbound (mesh → Internet)

1. A mesh node (IP from ${MESH_ADDRESS_RANGE}) wants to reach the Internet
2. Traffic goes to the **border router** (egress gateway)
3. Border router forwards to ISP via BGP peering
4. Response comes back the same path

### Inbound (Internet → mesh)

1. Someone on the Internet wants to reach a mesh node IP
2. BGP routing directs traffic to your ISP (your AS is announced)
3. ISP sends to your **border router**
4. Border router forwards via ZeroTier mesh to the node

### Key Insight: Egress Gateway

The border router must be configured as an **egress gateway** by routing traffic for `${MESH_ADDRESS_RANGE}` via the ZeroTier interface. All mesh nodes receive the route from the controller.

## Components

| Component | Location | Purpose |
|-----------|----------|---------|
| `deploy/zerotier-controller/` | Public server | ZeroTier control plane + UI |
| `deploy/bird-border/` | Datacenter | Border router: BGP + mesh gateway |
| `deploy/zerotier/` | Any location | Standalone mesh node |

### ZeroTier Controller (`deploy/zerotier-controller/`)

Central control plane for the mesh. Runs on a public server with:
- ZeroTier controller (non-free build)
- ztncui web UI

### Border Router (`deploy/bird-border/`)

The critical component that bridges your AS to the Internet:
- **BIRD**: BGP daemon, announces your IP block to the ISP
- **zerotier**: Connects to the mesh
- **Egress Gateway**: Announces routes to mesh nodes

### Mesh Nodes (`deploy/zerotier/`)

Simple nodes that join the mesh:
- Run zerotier to establish overlay
- Receive routes from egress gateway
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
cp deploy/zerotier-controller/.env.example deploy/zerotier-controller/.env
cp deploy/bird-border/.env.example deploy/bird-border/.env
cp deploy/zerotier/.env.example deploy/zerotier/.env
cp deploy/rpi-isp/.env.example deploy/rpi-isp/.env  # if using mock ISP
```

Edit each `.env` file with your specific values. See `.env.example` files for documentation.

### 1. Deploy ZeroTier Controller

```bash
cd deploy/zerotier-controller
cp .env.example .env
# Edit .env with your UI password and ports

docker compose up -d --build
```

See [deploy/zerotier-controller/README.md](deploy/zerotier-controller/README.md) for full instructions.

### 2. Create Mesh Network

Use ztncui UI to:
- Create a network
- Set **Auto-Assign Range** to `${MESH_ADDRESS_RANGE}`
- Add a **Managed Route** for `${MESH_ADDRESS_RANGE}`

### 3. Deploy Border Router

```bash
cd deploy/bird-border
cp .env.example .env
# Add ZT_NETWORK_ID from ztncui

docker compose up -d
```

See [deploy/bird-border/README.md](deploy/bird-border/README.md) for BGP configuration.

### 4. Deploy Mesh Nodes

```bash
cd deploy/zerotier
cp .env.example .env
# Add ZT_NETWORK_ID

docker compose up -d
```

## Testing with Mock ISP

For development without real BGP peering, use a Raspberry Pi as mock ISP.

See [deploy/rpi-isp/README.md](deploy/rpi-isp/README.md) for full mock ISP setup instructions.

```
┌─────────────────┐                    ┌─────────────────┐
│   RPi (mock)    │◄───── BGP ────────►│  Border Router  │
│ AS ${ISP_AS}   │     ${BGP_         │  AS ${BORDER_  │
│ ${ISP_IP}      │      NETWORK_       │   ROUTER_AS}    │
│                 │      RANGE}         │ ${BORDER_      │
│ announces test  │                    │  ROUTER_IP}     │
│ prefixes        │                    │                 │
│                 │ egress gateway      │                 │
└─────────────────┘                    └─────────────────┘
                                              │
                                              │ mesh
                                              ▼
                                       ┌─────────────────┐
                                       │  Mesh Nodes     │
                                       │ ${MESH_        │
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
- Use proper TLS termination (reverse proxy) in front of ztncui for production.
- `ZTNCUI_PASSWD` is stored in plaintext in `.env` files — protect file permissions.
- Configure host firewall to restrict access to ztncui ports.

## References

- [ZeroTier Documentation](https://docs.zerotier.com/)
- [BIRD Internet Routing Daemon](https://bird.network.cz/)
- [BGP RFC 4271](https://datatracker.ietf.org/doc/html/rfc4271)

## License

MIT
