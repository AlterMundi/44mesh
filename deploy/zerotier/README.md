# ZeroTier Client (Docker)

Joins a ZeroTier network using the official `zerotier/zerotier` image.

## Setup

```bash
cd deploy/zerotier
cp .env.example .env
# Set ZT_NETWORK_ID

docker compose up -d
```

## Approve Member + Allow Global

In ztncui:
1. Approve the member.
2. Enable **Allow Global** for the member. This is required because the mesh uses public
   IPs from `${MESH_ADDRESS_RANGE}` — without Allow Global, ZeroTier only accepts
   private RFC1918 addresses on the interface.

## Verify

```bash
docker exec zerotier zerotier-cli info
docker exec zerotier zerotier-cli listnetworks
ip link | grep -E '^zt'
```
