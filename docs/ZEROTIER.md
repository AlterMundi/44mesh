# ZeroTier configuration

## Components

| Container | Image | Function |
|-----------|-------|----------|
| zerotier-controller | built (non-free) | Controller (control plane) |
| ztncui | built | Web UI for controller |
| zerotier | zerotier/zerotier:latest | Mesh client |

## Network

| Parameter | Value |
|-----------|-------|
| Address range | ${MESH_ADDRESS_RANGE} |
| Controller port | 9993/UDP + 9993/TCP |
| UI port | 3000/TCP (HTTP), 3443/TCP (HTTPS) |

## Controller notes

ZeroTier One v1.16.0+ does not ship the controller in default binaries. The controller must be built with the non-free components:

```bash
make ZT_NONFREE=1
```

This repo uses a Docker build in `deploy/zerotier-controller/Dockerfile.controller`.

## Network setup (ztncui)

1. Create a network.
2. Set **Auto-Assign Range** to `${MESH_ADDRESS_RANGE}`.
3. Add a **Managed Route** for `${MESH_ADDRESS_RANGE}`.
4. Approve members and enable **Allow Global** so clients accept public IPs/routes.

## Client join

```bash
# On a node (using deploy/zerotier)
zerotier-cli join <network-id>
zerotier-cli listnetworks
```

## WireGuard note

This mesh is no longer WireGuard-based. ZeroTier uses its own transport; BIRD should bind to `zt*` interface.
