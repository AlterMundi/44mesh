# ZeroTier Controller + UI

Self-hosted ZeroTier controller (non-free build) with the ztncui web UI.

## Prerequisites

- Docker + Docker Compose
- Public server with UDP 9993 open

## Setup

```bash
cd deploy/zerotier-controller
cp .env.example .env
# Edit .env as needed

docker compose up -d --build
```

## Access UI

By default, ztncui listens on:
- HTTP: `http://<host>:3000`
- HTTPS: `https://<host>:3443`

Login with the password set in `ZTNCUI_PASSWD`.

## Create Network

1. Create a new network in ztncui.
2. Set **Auto-Assign Range** to `${MESH_ADDRESS_RANGE}`.
3. Add a **Managed Route** for `${MESH_ADDRESS_RANGE}`.
4. For each member, enable **Allow Global** so public IPs are accepted.

## Notes

- The controller is built with `ZT_NONFREE=1` in `Dockerfile.controller`.
- ztncui reads the controller auth token from `/var/lib/zerotier-one/authtoken.secret`.
