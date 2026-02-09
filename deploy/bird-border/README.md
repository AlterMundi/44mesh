# Border Router Setup

> [← Back to main README](../../README.md)

Border node that connects the ZeroTier mesh to external networks via BGP.

## Components

| Service | Purpose | Network |
|---------|---------|---------|
| zerotier | Mesh client | host (creates zt* interface) |
| bird | BGP daemon (AS ${BORDER_ROUTER_AS}) | host (peers with ${ISP_IP}) |

## Prerequisites

1. **ZeroTier controller running** (see `deploy/zerotier-controller/`)
2. **Network ID** from ZeroTier
3. **Member approved + Allow Global enabled** in ztncui (Allow Global lets ZeroTier assign
   public IPs from your address range instead of only private RFC1918 addresses)
4. **Host requirements**:
   - `net.ipv4.ip_forward=1` enabled
   - IP address in the BGP peering network (for BGP peering with ISP)

## Network Configuration

| Address | Role |
|---------|------|
| ${BORDER_ROUTER_IP} | This host (secondary IP for BGP) |
| ${ISP_IP} | ISP/Peer (BGP neighbor) |
| ${MESH_ADDRESS_RANGE} | Mesh network (ZeroTier) |
| (from mesh range) | This host (mesh IP, assigned by ZeroTier) |

## Deploy

### 1. Configure environment

```bash
cp .env.example .env
# Edit .env and add ZT_NETWORK_ID
```

**Environment variables:**

| Variable | Description |
|----------|-------------|
| ZT_NETWORK_ID | ZeroTier network ID |
| ZEROTIER_API_SECRET | Optional API token for zerotier-cli |

### 2. Add secondary IP for BGP peering

The border router needs an IP in the BGP peering network to peer with the ISP.

**Temporary (until reboot):**
```bash
sudo ip addr add ${BORDER_ROUTER_IP}/24 dev ${BORDER_ROUTER_INTERFACE}
```

**Persistent with NetworkManager:**
```bash
# Find your connection name
nmcli con show

# Add secondary IP
nmcli con mod "<connection-name>" +ipv4.addresses ${BORDER_ROUTER_IP}/24
nmcli con up "<connection-name>"
```

**Persistent with /etc/network/interfaces.d/:**
```bash
cat <<'BGP' | sudo tee /etc/network/interfaces.d/bgp-peering
# Secondary IP for BGP peering with ISP
auto ${BORDER_ROUTER_INTERFACE}:1
iface ${BORDER_ROUTER_INTERFACE}:1 inet static
    address ${BORDER_ROUTER_IP}
    netmask 255.255.255.0
BGP
```

Verify connectivity:
```bash
ping -c 2 ${ISP_IP}
```

### 3. Enable IP forwarding on host

```bash
sudo sysctl -w net.ipv4.ip_forward=1
# Make persistent:
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-forward.conf
```

### 4. Start services

```bash
docker compose up -d
```

The startup sequence:
1. `zerotier` joins the network and creates interface `zt*`
2. `bird` waits for interface (healthcheck)
3. `bird` starts BGP peering with ISP

### 5. Verify

```bash
# Check ZeroTier client
docker exec zerotier zerotier-cli listnetworks

# Check BIRD status
docker exec bird-border birdc show status
docker exec bird-border birdc show protocols

# Check BGP routes
docker exec bird-border birdc show route
docker exec bird-border birdc "show route export isp"

# Test mesh connectivity (to another mesh node)
ping <mesh-node-ip>  # any IP in ${MESH_ADDRESS_RANGE}
```

## Architecture

```
                         ZeroTier Controller
                                  │
                                  │ ZeroTier
                                  │
┌─────────────────────────────────┼──────────────────────────┐
│            Border Router        │                          │
│                                 ▼                          │
│  ┌───────────────┐      ┌─────────────┐                   │
│  │   zerotier    │──────│   zt*       │ mesh IP           │
│  │               │      │  interface  │                   │
│  └───────────────┘      └──────┬──────┘                   │
│                                │                           │
│                         ┌──────┴──────┐                   │
│  BGP :179               │    BIRD     │                   │
│  ◄──────────────────────│ AS ${BORDER │                   │
│                         │  _ROUTER_AS}│                   │
│                         └─────────────┘                   │
│                                                            │
│  Secondary IP: ${BORDER_ROUTER_IP}                        │
└────────────────────────────────────────────────────────────┘
         │
         │ BGP peering
         ▼
   ISP (${ISP_IP})
   AS ${ISP_AS}
```

## BGP Configuration

Configuration is managed via environment variables in `.env`:

- **Export to ISP**: `${MESH_ADDRESS_RANGE}` (mesh network)
- **Import from ISP**: All routes from peer (works for both iBGP and eBGP)

The BIRD configuration is generated from `bird.conf.template` at container startup using values from your `.env` file.

## Troubleshooting

### ZeroTier won't connect
```bash
docker logs zerotier
# Ensure the member is approved and Allow Global is enabled
```

### BIRD won't start
```bash
docker logs bird-border
# Usually waiting for zt* interface
```

### BGP session not established
```bash
docker exec bird-border birdc show protocols all isp
# Check ISP/peer is reachable
ping ${ISP_IP}
```

### Interface not detected
If BIRD can't find the ZeroTier interface:
```bash
# Check actual interface name
ip link | grep -E '^zt'

# The entrypoint auto-detects interfaces matching 'zt*'
docker logs bird-border
```
