# ztncui Web UI

Web interface for ZeroTier member management. Reads the controller auth token
from the shared `zerotier_data` volume mounted from `deploy/bird-border/`.

> **Note:** The ZeroTier controller itself runs inside `deploy/bird-border/`, not here.
> This stack only provides the ztncui UI.

## Prerequisites

- `deploy/bird-border/` running (controller + shared `zerotier_data` volume)
- Docker + Docker Compose

## Setup

```bash
cd deploy/zerotier-controller
cp .env.example .env
# Edit .env: set ZTNCUI_PASSWD and ports

docker compose up -d --build
```

## Access UI

By default, ztncui listens on:
- HTTP: `http://<host>:3180`
- HTTPS: `https://<host>:3443`

Login with the password set in `ZTNCUI_PASSWD`.

## Creating / Managing Networks

For initial network setup (creating the network, setting `ingressNodeV4`, authorizing
members), use the ZeroTier controller API directly. See
[../../docs/ZEROTIER.md](../../docs/ZEROTIER.md) for the full procedure.

ztncui is useful for day-to-day member authorization and network inspection.

## Notes

- ZeroTier binaries are built from the [AlterMundi/ZeroTierOne](https://github.com/AlterMundi/ZeroTierOne) fork (`feature/ingress-node` branch) in `Dockerfile.controller`.
- ztncui reads the controller auth token from `/var/lib/zerotier-one/authtoken.secret` (shared volume).
