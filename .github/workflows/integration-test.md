# Integration Test — VPN Mesh Connectivity

Companion document for `integration-test.yml`.
Read this side-by-side with the workflow file.

---

## Why this test exists

The 44mesh stack has three moving parts that must work together:

1. **ZeroTier controller** — assigns mesh IPs and manages node membership
2. **BIRD2 border router** — announces the mesh IP range to an upstream ISP via BGP
3. **ZeroTier client nodes** — join the overlay and communicate over it

A build that passes image validation and unit checks can still fail at runtime if,
for example, the ZeroTier interface never comes up, the BIRD template is
misconfigured, or the overlay dataplane drops packets. This workflow boots the
real services in CI and exercises all three layers.

---

## Network topology used in the test

```
  Host runner (ubuntu-latest)
  ├── eth0 (primary, public IP)
  │   ├── eth0:isp    → 172.30.0.1/24   (mock ISP BGP address)
  │   └── eth0:border → 172.30.0.100/24 (border router BGP address)
  │
  ├── zt<id>  → 44.30.127.1/24          (controller's mesh IP, on host namespace)
  │
  ├── [host-network containers]
  │     zt-controller  — ZeroTier daemon + controller, port 9993
  │     bird-border    — BIRD2, AS 65000, peers with 172.30.0.1
  │     bird-isp       — BIRD2, AS 65001, peers with 172.30.0.100
  │
  └── [bridge network: mesh-test-net 172.31.0.0/24]
        zt-node1  — ZeroTier client, gets IP from pool 44.30.127.10–50
        zt-node2  — ZeroTier client, gets IP from pool 44.30.127.10–50
```

### Why split networking?

The **controller and BIRD services** run with `--network host` so they share the
host's network namespace. This is exactly how they run in production and it lets
BIRD see the `zt*` interface that the ZeroTier daemon creates.

The **client nodes** run on a Docker bridge (`mesh-test-net`). This gives each
client its own Linux network namespace, which means each ZeroTier daemon creates
its own `zt<id>` interface without name-conflicting with the controller's
interface (both would try to use the same name for the same network ID if they
shared the host namespace). Outbound UDP from the bridge is NAT-ted through the
host, which is enough for ZeroTier's NAT traversal to work.

---

## Setup steps (before the tests)

### Kernel & host network

```
Load kernel modules and configure host networking
```

- Loads the `tun` kernel module (required by ZeroTier to create TAP/TUN devices).
- Detects the default egress interface dynamically with `ip route get 8.8.8.8`
  instead of hardcoding `eth0` — runner interface names differ across cloud
  providers and runner generations.
- Adds two secondary IPs to that interface (`172.30.0.1` for the mock ISP,
  `172.30.0.100` for the border router). Both BIRD instances then bind to these
  addresses and peer over the same physical interface.
- Creates the `mesh-test-net` Docker bridge used by client nodes.

### Image preparation

Builds the two local images (`bird-border`, `rpi-isp`) from source and pulls the
pre-built ZeroTier image. Building from source in CI ensures that any Dockerfile
or config-template change is exercised, not a stale cached layer.

### ZeroTier controller bootstrap

```
Start ZeroTier controller
Wait for ZeroTier controller to come online
Create ZeroTier mesh network
Controller joins its own network and receives a static mesh IP
Verify host zt* interface has mesh IP before starting BIRD
```

1. The controller container starts with `--network host` and the
   `controller-entrypoint.sh` from the repo (mounted read-only). No identity is
   pre-seeded, so a fresh one is generated each run.

2. Readiness is confirmed by polling `zerotier-cli -j info` until
   `.online == true` (JSON output, not text parsing).

3. A private ZeroTier network is created via the local REST API
   (`POST /controller/network/${CTRL_ID}______`). The six underscores are
   expanded by the controller into a unique suffix — this is the documented way
   to create a controller-owned network. The returned `.id` is validated
   non-empty and saved as `ZT_NETWORK_ID`.

4. The controller joins its own network and is authorized with the static IP
   `44.30.127.1`. The authorization is polled (not a fixed sleep) to avoid a
   race where the member record doesn't exist yet.

5. Before starting BIRD, the workflow waits for `44.30.127.1` to appear on the
   host's `zt*` interface. This is the synchronization point between ZeroTier
   and BIRD — BIRD's `entrypoint.sh` scans for a `zt*` interface, and if it
   isn't there yet, BIRD exits with an error.

### BGP services start

```
Start BIRD border router
Start mock ISP (BIRD)
Verify BGP listeners bound on expected IPs
```

Both BIRD containers start with `--network host`. Each receives its BGP
parameters as environment variables; `entrypoint.sh` runs `envsubst` on
`bird.conf.template` to produce the final config, verifies it with
`bird -p`, then starts the daemon.

A defensive step (`ss -nltp 'sport = :179'`) asserts that both daemons are
actually listening on the expected IPs before the BGP test runs. This catches
template substitution failures where BIRD binds to `0.0.0.0` instead of a
specific address.

---

## The four tests

### TEST 1 — BGP session established

```yaml
- name: "TEST 1: BGP session established"
```

**What it does:** Polls `birdc show protocols` on the border router until the
BGP session with the ISP reaches the `Established` state (up to 90 s).

**What it proves:** The two BIRD instances can reach each other over the
`172.30.0.0/24` link, the BIRD configs are syntactically and semantically
correct, and the BGP FSM completes the full Open → Active → Established
transition.

**Pass condition:** `birdc show protocols` output contains the word
`Established`.

---

### TEST 2 — Mesh route exported via BGP

```yaml
- name: "TEST 2: Mesh route exported via BGP"
```

**What it does:** Waits up to 60 s for `44.30.127.0/24` to appear in the ISP's
BIRD routing table, then asserts it is present.

**What it proves:**
- The border router's BIRD config correctly exports the mesh range (the
  `export filter` in `bird.conf.template` accepts `net ~ [${MESH_ADDRESS_RANGE}]`).
- The ZeroTier `zt*` interface was recognised by the `protocol direct { interface "zt*"; }`
  block and the prefix was learned.
- Route propagation from border → ISP works end-to-end.

**Pass condition:** `docker exec bird-isp birdc show route` contains `44.30.127.0/24`.

---

### TEST 3 — ZeroTier nodes receive mesh IPs

```yaml
- name: Start ZeroTier mesh node 1
- name: Start ZeroTier mesh node 2
- name: Wait for client nodes to appear in controller and authorize them
- name: "TEST 3: ZeroTier nodes receive mesh IPs"
```

**What it does (setup):** Two client containers start on `mesh-test-net`. Each
mounts the same `entrypoint.sh`, `local.conf` (allows management from any IP),
and `network.local.conf` (sets `allowManaged=1`, `allowGlobal=1`,
`allowDefault=1`). They call `zerotier-cli join <NETWORK_ID>` and then wait to
be authorized.

Authorization is done by polling the controller API until it sees three members
(controller + 2 clients), then issuing `POST .../member/<id>` with
`{"authorized": true}` for each client. A 10-second settle follows so clients
can fetch their updated network config from the controller.

**What it asserts:** For each node, `zerotier-cli -j listnetworks` returns
`status == "OK"` and at least one `assignedAddresses` entry that matches
`^44\.30\.127\.`. The IP is extracted via `jq` and stored for TEST 4. An empty
or out-of-range IP is a hard failure.

**What it proves:**
- The controller correctly assigns IPs from the configured pool.
- Clients can reach the controller through Docker bridge NAT (ZeroTier's NAT
  traversal via planet/root servers handles this).
- The `entrypoint.sh` correctly pre-configures the network join on startup.

**Pass condition:** Both nodes have a mesh IP in `44.30.127.0/24` and status `OK`.

---

### TEST 4 — Node-to-node ping over ZeroTier mesh

```yaml
- name: "TEST 4: Node-to-node ping over ZeroTier mesh"
```

**What it does:** Runs `ping -c 5 -W 3 <peer-ip>` in each direction inside the
client containers.

**What it proves:**
- The ZeroTier overlay dataplane is functional — packets sent to a mesh IP
  actually traverse the encrypted ZeroTier tunnel and arrive at the peer.
- Both nodes have established a peer path (direct or relayed) and can exchange
  traffic bidirectionally.

**Pass condition:** 5/5 ping replies in both directions (node1→node2 and
node2→node1).

---

## Diagnostics on failure

```yaml
- name: Collect diagnostics on failure
  if: failure()
```

Runs only when a previous step has failed. Dumps:

| Group | Contents |
|---|---|
| Container logs | Last 50 lines from each container |
| Host network state | `ip addr`, `ip link`, `ip route`, `ss -nltp :179` |
| BIRD state | `birdc show protocols` and `birdc show route` for both routers |
| ZT controller members | JSON member list from controller API |
| ZT node status | `zerotier-cli -j listnetworks` and `zerotier-cli -j peers` from each client + `ip addr` |

The `peers` output is especially useful for diagnosing TEST 4 failures: if peers
show `latency == -1` or no direct path, it indicates the ZeroTier path was never
established (often a UDP connectivity or timing issue in CI).

---

## Known limitations and risks

| Risk | Mitigation |
|---|---|
| Bridge→host ZT path needs internet (planet/root servers) | TEST 3 allows 180 s; `zerotier-cli -j peers` in diagnostics |
| `zerotier-cli -j` flag in AlterMundi fork may differ | Confirmed present in fork; if broken, `-j` output lands in diagnostics |
| Interface fallback to `eth0` if route detection fails | `ss` listener check in setup surfaces misconfigured BGP bind addresses early |
| `allowDefault=1` in `network.local.conf` accepts a default route from mesh | No default route is configured in the test network, so no routing loop occurs |

---

## Triggers

| Event | Condition |
|---|---|
| Pull request to `main` | Only if `deploy/**` or the workflow file itself changed |
| Push to `stage` | Only if `deploy/**` changed |
| Manual (`workflow_dispatch`) | Always |

Concurrency is set to cancel in-progress runs for the same ref, so pushing
multiple commits in quick succession does not queue up redundant runs.
