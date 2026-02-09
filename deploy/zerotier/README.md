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
2. Enable **Allow Global** for the member so it can accept public IPs/routes.

## Verify

```bash
docker exec zerotier zerotier-cli info
docker exec zerotier zerotier-cli listnetworks
ip link | grep -E '^zt'
```
