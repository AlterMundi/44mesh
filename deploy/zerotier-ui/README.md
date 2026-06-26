<!--
SPDX-FileCopyrightText: 2025 AlterMundi

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# ZeroTier Web UI

Web interface for ZeroTier member management. Built from the
[altermundi/zerotier-ui](https://github.com/altermundi/zerotier-ui) fork, which
adds an **Ingress Node** button on the network detail page for configuring
`ingressNodeV4` without using the API directly.

Reads the controller auth token from the shared `zerotier_data` volume mounted
from `deploy/bird-border/`.

> **Note:** The ZeroTier controller itself runs inside `deploy/bird-border/`, not here.
> This stack only provides the web UI.

## Prerequisites

- `deploy/bird-border/` running (controller + shared `zerotier_data` volume)
- Docker + Docker Compose

## Setup

```bash
cd deploy/zerotier-ui
cp .env.example .env
# Edit .env: set ZTNCUI_PASSWD and ports

docker compose up -d --build
```

## Access UI

By default, the UI listens on:
- HTTP: `http://<host>:3180`
- HTTPS: `https://<host>:3443`

Login with the password set in `ZTNCUI_PASSWD`.

## Creating / Managing Networks

For initial network setup (creating the network, setting `ingressNodeV4`, authorizing
members), use the ZeroTier controller API directly or the **Ingress Node** button in the
web UI. See [../../docs/ZEROTIER.md](../../docs/ZEROTIER.md) for the full procedure.

The web UI is useful for day-to-day member authorization and network inspection.

## Notes

- ZeroTier binaries are built from the [AlterMundi/ZeroTierOne](https://github.com/AlterMundi/ZeroTierOne) fork (`feature/ingress-node` branch) in `deploy/bird-border/Dockerfile.controller`.
- The web UI is built from the [altermundi/zerotier-ui](https://github.com/altermundi/zerotier-ui) fork (`altermundi` branch) in `Dockerfile.ztncui`.
- The UI reads the controller auth token from `/var/lib/zerotier-one/authtoken.secret` (shared volume).
