<!--
SPDX-FileCopyrightText: 2025 AlterMundi

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# 44mesh ZeroTier (AlterMundi fork)

Multi-arch ZeroTier One built from the [AlterMundi fork](https://github.com/AlterMundi/ZeroTierOne)
(branch `feature/ingress-node`) for 44mesh ingress/controller roles.

- **Repo**: `buzondefede/44mesh-zerotier`
- **Platforms**: `linux/amd64`, `linux/arm64`
- **Tags**: `latest` (main), `vX.Y.Z` / `X.Y.Z` (release tag), `sha-<short>` (all builds)

## Build arg

| Arg | Default |
|-----|---------|
| `ZEROTIER_BRANCH` | `feature/ingress-node` |

## Quick start

```sh
docker run --rm \
  --net=host \
  --cap-add=NET_ADMIN \
  --device /dev/net/tun \
  -v zerotier_data:/var/lib/zerotier-one \
  buzondefede/44mesh-zerotier:latest
```

## Source

- Upstream fork: https://github.com/AlterMundi/ZeroTierOne
- Deploy config: https://github.com/altermundi/44mesh/tree/main/deploy/zerotier
