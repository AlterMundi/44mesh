# Headscale + DERP Replacement Design

## Goal
Replace Netmaker with a self-hosted Tailscale-compatible control plane (Headscale) plus self-hosted DERP, while keeping mesh IPs on the public `${MESH_ADDRESS_RANGE}` block and preserving the current border-router/BGP flow.

## Architecture Summary
- **Control plane**: Headscale runs on a single public server, serving HTTPS and issuing node registrations via pre-auth keys.
- **Relay**: DERP runs on the same server for NAT traversal and acts as the required fallback when direct peer connections fail.
- **Clients**: All nodes (border router and mesh nodes) run the Tailscale client (`tailscaled` + `tailscale` CLI). Each node registers to Headscale using pre-auth keys and receives an address from `${MESH_ADDRESS_RANGE}`.
- **Border router**: BIRD continues to announce `${MESH_ADDRESS_RANGE}` to the ISP, but now uses `tailscale0` as the interface for the mesh routes.
- **Monitoring**: Replace Netmaker API/MQTT checks with Headscale + DERP health checks and Tailscale interface/peer metrics.

## Data Flow
1. Nodes join Headscale using pre-auth keys and `--login-server` pointing to the Headscale URL.
2. Headscale assigns IPs from `${MESH_ADDRESS_RANGE}` and pushes route/ACL config to nodes.
3. Nodes attempt direct peer connections; when NAT traversal fails, DERP relays traffic.
4. The border router advertises the public block via BGP and routes between ISP and the mesh through `tailscale0`.

## Deployment Scope
- **New**: `deploy/headscale/` with Docker Compose, config templates, and docs.
- **Replace**: `deploy/netclient/` → `deploy/tailscale/` using the Tailscale client.
- **Update**: `deploy/bird-border/` to detect `tailscale0` and adjust docs/config.
- **Update**: Monitoring, workflows, and all documentation references to Netmaker.
- **Remove**: Netmaker-specific deploy and documentation artifacts.

## Risks / Constraints
- **TLS routing**: Headscale and DERP must be reachable via HTTPS; a reverse proxy is likely required to serve multiple hostnames on one server.
- **Addressing**: Headscale must be configured to allocate IPs from `${MESH_ADDRESS_RANGE}`.
- **Migration**: Existing netclient nodes must be re-registered to Headscale; no in-place migration tooling.

## Validation
- `docker compose config` in deploy stacks.
- Node join verification via `tailscale status` and `tailscale netcheck`.
- BIRD interface discovery and route export checks.
- Monitoring endpoints for Headscale + DERP health.
