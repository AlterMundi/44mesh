# 44mesh BIRD2 Border Router

BIRD2 border router container for 44mesh networks. Handles eBGP peering with upstream ISPs
and announces the mesh address range to the Internet.

- **Repo**: `buzondefede/44mesh-bird-border`
- **Platforms**: `linux/amd64`, `linux/arm64`
- **Tags**: `latest` (main), `vX.Y.Z` / `X.Y.Z` (release tag), `sha-<short>` (all builds)

## Quick start

```sh
docker run --rm \
  --network host \
  --cap-add=NET_ADMIN \
  -e BORDER_ROUTER_AS=65001 \
  -e MESH_ADDRESS_RANGE=100.64.0.0/10 \
  buzondefede/44mesh-bird-border:latest
```

## Source

- Deploy config: https://github.com/altermundi/44mesh/tree/main/deploy/bird-border
