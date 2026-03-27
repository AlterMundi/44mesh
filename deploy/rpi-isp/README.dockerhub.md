<!--
SPDX-FileCopyrightText: 2025 AlterMundi

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# 44mesh BIRD2 Router for Raspberry Pi

BIRD2-based BGP router image for 44mesh ISP nodes. Tuned for Raspberry Pi and general ARM/AMD64.

- **Repo**: `buzondefede/44mesh-rpi-isp`
- **Platforms**: `linux/amd64`, `linux/arm64`, `linux/arm/v7`
- **Tags**: `latest` (main), `vX.Y.Z` / `X.Y.Z` (release tag), `sha-<short>` (all builds)

## Quick start

```sh
docker run --rm \
  --network host \
  --cap-add=NET_ADMIN \
  -v ./bird.conf:/etc/bird/bird.conf:ro \
  buzondefede/44mesh-rpi-isp:latest
```

## Source

- Deploy config: https://github.com/altermundi/44mesh/tree/main/deploy/rpi-isp
