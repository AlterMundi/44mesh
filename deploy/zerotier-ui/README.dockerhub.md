<!--
SPDX-FileCopyrightText: 2025 AlterMundi

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# 44mesh ZeroTier UI (ztncui fork)

Web UI for managing a ZeroTier controller. Customized [ztncui](https://github.com/key-networks/ztncui)
fork with 44mesh-specific tweaks (confirm dialogs, nav cleanup, layout improvements).

- **Repo**: `buzondefede/44mesh-zerotier-ui`
- **Platforms**: `linux/amd64`, `linux/arm64`
- **Tags**: `latest` (main), `vX.Y.Z` / `X.Y.Z` (release tag), `sha-<short>` (all builds)

## Quick start

```sh
docker run -d \
  --network host \
  -e ZT_ADDR=127.0.0.1:9993 \
  -e ZTNCUI_HTTP_PORT=3180 \
  -e ZTNCUI_PASSWD=changeme \
  -v zerotier_data:/var/lib/zerotier-one:ro \
  buzondefede/44mesh-zerotier-ui:latest
```

## Source

- Deploy config: https://github.com/altermundi/44mesh/tree/main/deploy/zerotier-ui
