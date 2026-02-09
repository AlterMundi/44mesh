# ZeroTier Replacement Design

## Goal
Replace Netmaker with a self-hosted ZeroTier controller + ztncui UI, using public roots only and keeping `${MESH_ADDRESS_RANGE}` for the overlay network.

## Architecture Summary
- **Controller**: `zerotier-one` built with non-free controller components (required for self-hosted controller).
- **UI**: `ztncui` for network/member management.
- **Roots**: Public roots only (no moon).
- **Clients**: ZeroTier nodes in Docker on border router and mesh nodes.
- **Routing**: BIRD uses ZeroTier interface (`zt*`) to export `${MESH_ADDRESS_RANGE}` via BGP.

## Data Flow
1. Controller and ztncui start on a public server.
2. Network auto-assign range is set to `${MESH_ADDRESS_RANGE}` and a managed route is added for `${MESH_ADDRESS_RANGE}`.
3. Clients join the network via `zerotier-cli join <network-id>`.
4. Each client enables `allowGlobal=1` to accept public IPs/routes.
5. BIRD announces `${MESH_ADDRESS_RANGE}` to ISP via the ZeroTier interface.

## Deployment Scope
- **New**: `deploy/zerotier-controller/` stack (controller + ztncui).
- **Replace**: `deploy/netclient/` → `deploy/zerotier/` client stack.
- **Update**: `deploy/bird-border/` to detect `zt*`.
- **Update**: Monitoring, workflows, and all docs to remove Netmaker references.
- **Remove**: Netmaker deploy/docs.

## Risks / Constraints
- Controller build must include non-free components.
- Clients must allow global addresses for public IP assignment.
- ZeroTier interface name is dynamic (`zt*`); scripts must detect it.

## Validation
- `docker compose config` in deploy stacks.
- Controller health via `zerotier-cli info`.
- Client join and interface presence.
- BIRD sees `zt*` and exports `${MESH_ADDRESS_RANGE}`.
