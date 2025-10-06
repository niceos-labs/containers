# NiceOS Redis® / Redis® Cluster — Documentation Plan (better-than-Bitnami)

## 0) Front-matter

* **Title:** *NiceOS package for Redis® / Redis® Cluster*

* **Short synopsis (elevator pitch):**
  Ship a production-ready Redis/Redis Cluster in seconds 🚀. The NiceOS image provides **opinionated, secure defaults**, **idempotent configuration**, and **deterministic cluster bootstrapping**—with first-class **TLS**, **ACLs**, and **health checks**. It’s drop-in compatible with common Bitnami environment variables (plus helpful NiceOS extras), logs cleanly to stdout/stderr, and keeps all runtime state under `/app` for tidy persistence and backups. Whether you’re spinning up a single dev node or a 3-masters/3-replicas cluster, you get reproducible behavior, clear observability, and a path to hardened deployments in containers or Kubernetes 🧰.

* **Trademark disclaimer:**
  *Redis is a registered trademark of Redis Ltd. Any rights therein are reserved to Redis Ltd. Any use by NiceOS is for referential purposes only and does not indicate any sponsorship, endorsement, or affiliation between Redis Ltd. and NiceOS.*

* **Badges (minimal, useful set):**

  > Use these at the top of the README for quick scannability. Replace placeholders as appropriate.

  [![Image Size](https://img.shields.io/docker/image-size/niceos/redis-cluster/latest?logo=docker\&label=image%20size)](https://hub.docker.com/r/niceos/redis-cluster)
  [![Architectures](https://img.shields.io/badge/arch-amd64%20%7C%20arm64-informational)](#)
  [![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
  [![SBOM](https://img.shields.io/badge/SBOM-available-success)](#)
  [![Provenance/Attestation](https://img.shields.io/badge/provenance-SLSA%203-brightgreen)](#)
  [![Container Healthcheck](https://img.shields.io/badge/healthcheck-enabled-brightgreen)](#)
  [![Redis](https://img.shields.io/badge/Redis-6%2B%20%7C%207%2B-red?logo=redis)](https://redis.io)

  **Why these badges?**

  * **Image Size**: helps ops estimate pull times and storage ⏬
  * **Architectures**: shows multi-arch support 🧩
  * **License**: compliance at a glance ⚖️
  * **SBOM**: signals supply-chain transparency 📄
  * **Provenance/Attestation**: build integrity (e.g., SLSA-aligned) 🔐
  * **Healthcheck**: indicates built-in liveness/readiness tooling ❤️‍🩹
  * **Redis version**: clarifies upstream compatibility 🔢

---

## 1) TL;DR ⚡️

Fastest way to get started — no detours, no mystery knobs.
Use `niceos/redis-cluster` (always tagged `latest` and versioned, e.g. `8.2.1`) — both tags refer to the **same image** on Docker Hub.

---

### 🧩 Single-Node (Development Mode)

Run a single Redis instance in seconds (just for test).
Passwordless mode (`ALLOW_EMPTY_PASSWORD=yes`) is **intended for development only** — never use this in production.

```console
docker run -d --name redis-dev \
  -e ALLOW_EMPTY_PASSWORD=yes \
  -e REDIS_CLUSTER_ENABLED=no \
  -p 6379:6379 \
  niceos/redis-cluster:latest
```

**What happens here:**

* Starts a standalone Redis daemon inside the NiceOS base image 🧱
* Applies the same `redis.conf` template as a cluster node (so config parity is preserved)
* Logs cleanly to `stdout` and `stderr`, no syslog or detached log files 📜
* Persists data in `/app/data` if you mount a host volume 💾

Mount a volume for persistence:

```console
docker run -d --name redis-dev \
  -e ALLOW_EMPTY_PASSWORD=yes \
  -e REDIS_CLUSTER_ENABLED=no \
  -v /srv/redis:/app/data \
  -p 6379:6379 \
  niceos/redis-cluster:latest
```

---

### 🧠 6-Node Cluster (3 Masters + 3 Replicas)

Spin up a **fully functional Redis® Cluster** using the bundled Compose definition.
All nodes run from the **same image** (`niceos/redis-cluster:8.2.1` or `latest`) to ensure deterministic behavior.

```console
curl -LO https://repo.niceos.org/examples/redis-cluster/docker-compose.yml
docker compose up -d
```

**Behind the scenes:**

* Launches six containers: `r1` … `r6` 🧩
* Node `r1` acts as the **cluster creator**, orchestrating slot allocation and replication mapping
* Each replica pairs automatically with a master
* Healthcheck (`healthcheck-redis-cluster.sh`) validates readiness (`cluster_state:ok`)
* Perfect for CI pipelines, reproducible tests, and pre-prod validation 🧪

To stop and clean up the cluster:

```console
docker compose down -v
```

---

### 🔐 TLS-Enabled Instance (Production-Grade)

Enable encrypted connections and authenticated access in one command.
Mount your existing certificate bundle and toggle TLS support — no config rewrites required.

```console
docker run -d --name redis-tls \
  -v /path/to/certs:/app/certs \
  -e REDIS_TLS_ENABLED=yes \
  -e REDIS_TLS_CERT_FILE=/app/certs/redis.crt \
  -e REDIS_TLS_KEY_FILE=/app/certs/redis.key \
  -e REDIS_TLS_CA_FILE=/app/certs/ca.crt \
  -e REDIS_PASSWORD=StrongPass123 \
  -p 6379:6379 \
  niceos/redis-cluster:8.2.1
```

**This setup:**

* Enforces encrypted transport (TLS 1.2/1.3) 🔒
* Disables non-TLS ports unless explicitly enabled (`REDIS_TLS_PORT_NUMBER` ≠ `0`)
* Integrates with built-in healthchecks and the same CLI wrappers (`libredis.sh`)
* Fully compatible with replication and clustering modes

---

### 🧰 Copy-Paste Notes

* `niceos/redis-cluster:latest` **always points to the latest stable release**.
  Use a pinned tag (`8.2.1`) in production for deterministic builds.
* All images are **multi-arch (amd64 + arm64)** and under **122 MB** 🪶.
* Internal structure: `/app/bin`, `/app/etc`, `/app/data`, `/app/run`, `/app/certs`.
* Stop, restart, or rebuild freely — initialization is **idempotent** and re-entrant.

---

## 2) Important Notices 🔔

This section keeps you safe and sane — it explains how the image is built, versioned, and secured. The NiceOS Redis® / Redis® Cluster images follow strict reproducibility and security standards so you always know what you’re running.

---

### 🛡️ Security Baseline

**Authentication policy:**

* `ALLOW_EMPTY_PASSWORD=yes` exists **only for local testing or CI mocks**. Never use it in production.
* For any real environment, set `REDIS_PASSWORD` or `REDIS_ACLFILE`. Both options are compatible with replication and cluster modes.
* All startup scripts (`entrypoint.sh`, `libredis.sh`) enforce a “fail-closed” policy — Redis refuses to start if passwordless mode is used together with network exposure (`0.0.0.0` bind).

**TLS/SSL usage:**

* TLS is **first-class** in NiceOS Redis. Enable it with `REDIS_TLS_ENABLED=yes`.
* Use standard PEM-formatted certs, mapped under `/app/certs`.
* By default, when TLS is active, the plain TCP port is disabled for security.
* To run both TLS and non-TLS interfaces, set `REDIS_TLS_PORT_NUMBER` to a **non-zero** value and expose both ports explicitly.
* The container includes OpenSSL 3 hardened configuration and disables weak ciphers and legacy renegotiation by default.

**Data persistence and access:**

* Data lives in `/app/data`. Mount this path to persistent storage to survive container restarts.
* File permissions inside `/app` default to `app:app (UID/GID 10001)` for non-root security.
* Healthchecks (`healthcheck-redis-cluster.sh`) verify service integrity before other containers connect.

---

### 🧬 Image Lifecycle & Provenance

**Versioning policy:**

* The image version equals the **Redis upstream version**, e.g., `8.2.1`.
* `latest` tag always points to the newest stable build of that version line.
* Minor versions (e.g., `8.2.x`) are patched deterministically, preserving backward compatibility in configuration and behavior.

**Tags policy:**

| Tag      | Description                            | Notes                                   |
| -------- | -------------------------------------- | --------------------------------------- |
| `8.2.1`  | Immutable, production-ready tag.       | Recommended for all stable deployments. |
| `latest` | Alias of the most recent stable build. | Use only in CI or local tests.          |

---

### ⚠️ Breaking Changes and Migration

**Migration guidance:**

* For each major Redis or NiceOS release, a `MIGRATION.md` will accompany the image in the same directory as the `Dockerfile`.
* Transitional hooks (such as deprecated environment variable shims) are retained for **one minor release window** to allow smooth upgrades.
* If cluster state compatibility changes, `redis_cluster_update_ips` will safely migrate node definitions in place.

---

## 3) Why this Image? 🤔

Not all Redis® containers are created equal.
The NiceOS Redis® / Redis® Cluster image was built from the ground up to be **predictable, composable, and secure** — without breaking compatibility with popular conventions such as Bitnami’s.

---

### 🌟 Key Differentiators (vs Bitnami)

**1️⃣ Strict `/app` Filesystem Policy**
Everything — binaries, configs, runtime state, logs, and certs — lives under `/app`.
This consistency eliminates path confusion and simplifies volume mounting, backup, and SELinux/AppArmor confinement.

| Path           | Purpose                                                                |
| -------------- | ---------------------------------------------------------------------- |
| `/app/bin`     | Executables and helpers (`redis-server`, `redis-cli`, `healthcheck-*`) |
| `/app/etc`     | Generated configuration files                                          |
| `/app/data`    | Persistent Redis data                                                  |
| `/app/run`     | PID and socket files                                                   |
| `/app/certs`   | TLS certificates                                                       |

This uniform structure means **you can always know where things are**, no matter what mode (standalone, replica, cluster) you run in.

---

**2️⃣ Idempotent Configuration Writers 🧮**
Unlike the Bitnami scripts, which patch configuration files in-place each startup, NiceOS uses atomic “conf writer” functions (`redis_conf_get/set/unset`) from `libredis.sh` and `librediscluster.sh`.
They ensure the same environment variables always produce the same deterministic configuration, even across reboots or redeployments.

Result:

* No duplicate `save` or `replicaof` lines.
* Safe concurrent reconfiguration for orchestrators.
* Configurable *post-merge include order* for custom overrides.

---

**3️⃣ Predictable Cluster Bootstrap ⚙️**
Cluster creation logic is **idempotent and self-verifying**:

* DNS resolution waits until all nodes respond (`_wait_for_dns_lookup`).
* The creator node (`redis_cluster_create`) executes once per cluster, no race conditions.
* Built-in health probe (`redis_cluster_check`) ensures `All 16384 slots covered`.

This yields reproducible clusters — same number of masters, replicas, and slot maps, every time.

---

**4️⃣ Drop-in Environment Compatibility Layer 🧩**
NiceOS images recognize **Bitnami-style** variables (`REDIS_*`, `ALLOW_EMPTY_PASSWORD`, `REDIS_CLUSTER_REPLICAS`, etc.) but extend them with additional toggles:

| Extra Variable        | Purpose                                                |
| --------------------- | ------------------------------------------------------ |
| `REDIS_DEBUG`         | Enables verbose startup diagnostics.                   |
| `REDIS_LOG_FORMAT`    | Choose between `plain`, `json`, or `both`.             |
| `REDIS_HEALTH_STRICT` | Fails container health if replication lag detected.    |
| `REDIS_SAFE_MODE`     | Forces AOF on, disables unsafe commands automatically. |

No migration pain — you can reuse existing Compose or Helm configs that were written for Bitnami.

---

**5️⃣ Safer Defaults 🔒**

* **AOF (Append Only File)** persistence is enabled by default (`appendonly yes`), improving durability.
* **Dangerous commands** (`FLUSHALL`, `CONFIG`, `SHUTDOWN`, `DEBUG`) are disabled unless explicitly re-enabled via `redis_disable_unsafe_commands`.
* TLS and password auth are opt-out, not opt-in.
* Non-root runtime enforced (`UID 1001`), with read-only `/app/bin`.

These defaults are designed to pass common **CIS Docker** and **FSTEC-style security baselines** with minimal adjustment.

---

### 🧑‍💻 Who Should Use It

This image is intended for two broad audiences:

**For Platform & SRE Teams:**

* Looking for reproducible Redis clusters across environments (Docker, Podman, Kubernetes).
* Wanting SBOM transparency, attestation, and clean logs for compliance or SOC audits.
* Expecting reliable health signals and predictable lifecycle hooks.

**For Developers:**

* Need local Redis instances identical to production.
* Want easy debugging (`REDIS_DEBUG=yes`), readable logs, and safe defaults without manual tweaking.
* Prefer to run multi-node clusters for integration testing without scripting headaches.

---

In short: **NiceOS Redis is the predictable Redis.**
You get Bitnami compatibility with stronger defaults, reproducible state, and real-world operational ergonomics.

---

## 4) Getting the Image 📦

Everything starts with the container image — and NiceOS keeps it simple, verifiable, and fast to pull.
Each Redis® / Redis® Cluster build is published to Docker Hub under the canonical repository:

👉 [`niceos/redis-cluster`](https://hub.docker.com/r/niceos/redis-cluster)

Both `latest` and versioned tags (e.g. `8.2.1`) always refer to the same immutable image digest for a given release cycle.

---

### 🐳 Pull the Latest Stable Version

Get the newest NiceOS Redis Cluster build in one line:

```console
docker pull niceos/redis-cluster:latest
```

**What you get:**

* Fully patched Redis® 8.2.1 server
* Hardened NiceOS base layer
* SBOM + provenance metadata embedded via OCI labels
* Verified image size: ~122 MB

Inspect embedded metadata for build provenance and SBOM location:

```console
docker inspect niceos/redis-cluster:latest | jq '.[0].Config.Labels'
```

---

### 📌 Pull a Pinned Version

For reproducible builds and long-term deployments, always pin to an explicit tag.

```console
docker pull niceos/redis-cluster:8.2.1
```

**Tip:**
Pinned tags never change content. If you rebuild or redeploy, Docker will reuse the same digest (`sha256:…`), guaranteeing byte-for-byte identical behavior.

You can verify the digest match manually:

```console
docker inspect --format='{{.Id}}' niceos/redis-cluster:8.2.1
```

**Summary:**
Use `latest` for quick testing 🧪, `8.2.1` for production 🏭, and build locally when you want complete transparency 🔍.

---


## 5) Requirements & Prerequisites 🧠

Before launching Redis® or Redis® Cluster with NiceOS, ensure your host is tuned for stability and persistence. Redis loves RAM, predictable I/O, and a few kernel knobs turned just right. This section gives you practical, production-tested defaults — no superstition, just the right sysctl spells.

---

### ⚙️ Host Kernel Tuning

Redis performance and durability depend on a few critical Linux kernel parameters.

**Minimal required sysctl tuning:**

```bash
# Allow Redis to allocate memory optimistically (prevents OOM issues)
sysctl -w vm.overcommit_memory=1

# Increase the maximum number of pending connections
sysctl -w net.core.somaxconn=1024

# Disable Transparent Huge Pages (THP) to avoid latency spikes
echo never > /sys/kernel/mm/transparent_hugepage/enabled
```

For persistent changes, add to `/etc/sysctl.conf` or a dedicated drop-in under `/etc/sysctl.d/redis.conf`.

**Why this matters:**

* `overcommit_memory=1` ensures Redis can fork during background saves (RDB/AOF rewrites).
* `somaxconn=1024` lets the kernel queue more connections before SYN backlog overflow.
* Disabling THP avoids unpredictable latency from large memory page compaction.

More details:

* [Redis latency guide](https://redis.io/docs/interact/latency/)
* [Redis memory tuning](https://redis.io/docs/interact/memory/tuning/)

---

### 💾 Disk & Memory Sizing Heuristics

Redis is memory-first, disk-second. Below are **approximate sizing guidelines** to help estimate resource requirements per node:

| Cluster Tier | Memory (RAM) | Disk (AOF+RDB) | Example Use Case                             |
| ------------ | ------------ | -------------- | -------------------------------------------- |
| Small        | 512 MB–1 GB  | 1–2 GB         | Local dev, CI pipelines                      |
| Medium       | 2–4 GB       | 5–10 GB        | Small production, internal caches            |
| Large        | 8–16 GB+     | 20–100 GB      | High-availability clusters, analytics caches |

**Rule of thumb:**
Disk = 2×RAM (for AOF + RDB backups).
Redis itself rarely needs more CPU than one logical core per node unless IO threading is enabled (`REDIS_IO_THREADS`).

---

### 🗂️ Volume Model

All NiceOS Redis images use a strict, clean filesystem policy:

| Path           | Purpose                    | Persistence                     |
| -------------- | -------------------------- | ------------------------------- |
| `/app/data`    | Data directory for AOF/RDB | **Persistent (mount a volume)** |
| `/app/etc`     | Generated configuration    | Regenerated at startup          |
| `/app/run`     | PID, sockets               | Volatile                        |
| `/app/certs`   | TLS certificates           | Mount if using TLS              |

**Logging model:**

* All logs go to **stderr** — ideal for `docker logs`, systemd journal, or Kubernetes log collectors.
* No rotation or logfiles on disk (by design).

To persist data, mount `/app/data`:

```console
docker run -d \
  -v /srv/redis-data:/app/data \
  -e REDIS_PASSWORD=StrongPass123 \
  niceos/redis-cluster:8.2.1
```

---

### 🔁 Cold vs Warm Redeploy

Redis behavior during container restart depends on what you persist:

| Resource                     | Behavior                                  | Persistence     |
| ---------------------------- | ----------------------------------------- | --------------- |
| Data (`/app/data`)           | Reused if mounted                         | ✅               |
| Config (`/app/etc`)          | Rebuilt at startup (from env vars)        | 🔁              |
| Cluster state (`nodes.conf`) | Regenerated unless persistent volume used | ✅ (for cluster) |
| Logs                         | Volatile (stdout/stderr)                  | ❌               |
| Certificates                 | Mount externally                          | ✅ (if TLS)      |

**Warm redeploys** (keeping `/app/data`) resume seamlessly with full dataset.
**Cold redeploys** (no mounted volume) reinitialize Redis with an empty dataset.

---

## 6) Networking & Configuration Model 🌐

Redis may be a memory daemon at heart, but in cluster mode it’s a chatty little organism — ports, DNS, and name resolution matter. The NiceOS Redis® / Redis® Cluster image keeps networking **predictable and composable**, while configuration layering ensures you always know where a value comes from.

---

### 🛜 Container Networking

**Bridge & user-defined networks:**

* Default mode is Docker’s **user-defined bridge network**. This allows all Redis nodes to discover each other by **container name**, not IP.
* Example: `redis-node1` can reach `redis-node2:6379` with zero manual DNS setup.
* Works equally well with `docker compose`, `podman network create`, or Kubernetes CNI networks.

**DNS & name-based discovery:**

* All cluster initialization functions (`_wait_for_dns_lookup`, `_to_host_and_port`) resolve names before starting slot assignment.
* In cluster mode, DNS lookup retries follow:

  * `REDIS_CLUSTER_DNS_LOOKUP_RETRIES` (default: `1`)
  * `REDIS_CLUSTER_DNS_LOOKUP_SLEEP` (default: `1s`)
* You can adjust initial delay via `REDIS_CLUSTER_SLEEP_BEFORE_DNS_LOOKUP` (useful for slow DNS propagation or orchestrators).

**IPv6 support:**

* Fully supported — no brackets required in configuration (`redis_conf_set` handles IPv6 gracefully).
* Cluster bus binds to both `::` and `0.0.0.0` unless explicitly restricted.

---

### 🔌 Ports Overview

| Port    | Purpose             | Default                 | Notes                                           |
| ------- | ------------------- | ----------------------- | ----------------------------------------------- |
| `6379`  | Main Redis TCP port | `REDIS_PORT_NUMBER`     | Can be TLS or non-TLS depending on settings     |
| `16379` | Cluster bus port    | `data port + 10000`     | Internal gossip/slot migration; not for clients |
| `6380`  | TLS port            | `REDIS_TLS_PORT_NUMBER` | Enabled only when `REDIS_TLS_ENABLED=yes`       |

**Behavior summary:**

* When `REDIS_TLS_ENABLED=no`: only `6379` is active.
* When `REDIS_TLS_ENABLED=yes`:

  * `6379` becomes the **TLS port** by default.
  * To expose both plain and TLS, set `REDIS_TLS_PORT_NUMBER` to a nonzero alternate port.
* Bus port (`+10000`) is automatically derived and opened unless `REDIS_CLUSTER_ENABLED=no`.

---

### ⚙️ Configuration Model & Precedence

The NiceOS Redis configuration system follows a **strict, layered precedence chain**.
Every level builds on the previous one to guarantee determinism and reproducibility.

| Precedence    | Source                                                           | Description                                                                                                         | Typical Use                                    |
| ------------- | ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------- |
| 1️⃣ (Highest) | **Mounted full config** `/app/mounted-etc/redis.conf`            | Complete user-provided configuration file. When mounted, all other layers are ignored.                              | Bring-your-own-config setups                   |
| 2️⃣           | **Env-driven generated `redis.conf`**                            | Automatically rendered from environment variables via `libredis.sh` setters (`redis_conf_set`, `redis_conf_unset`). | Default for container users                    |
| 3️⃣           | **Overrides include** `overrides.conf` / `$REDIS_OVERRIDES_FILE` | Appended as the *final include* line in generated configs.                                                          | Small tweaks without maintaining a full config |
| 4️⃣ (Lowest)  | **Runtime flags** `$REDIS_EXTRA_FLAGS`                           | Extra `redis-server` arguments injected at launch.                                                                  | For ephemeral tuning or debug mode             |

Example structure inside container:

```
/app/etc/redis.conf
└── includes:
    └── overrides.conf (if present)
```

**Determinism:**
Each restart rebuilds the same config from the same environment — no drift, no duplication, no side effects.

---

### 🔐 Secrets Loader — `_FILE` Pattern

Certain sensitive environment variables also support the `_FILE` convention, so you can load secrets from Docker or Kubernetes secrets instead of inline env vars.

**Supported variables:**

| Variable                  | File alternative               | Description                         |
| ------------------------- | ------------------------------ | ----------------------------------- |
| `REDIS_PASSWORD`          | `REDIS_PASSWORD_FILE`          | Main authentication password        |
| `REDIS_MASTER_PASSWORD`   | `REDIS_MASTER_PASSWORD_FILE`   | Replica authentication              |
| `REDIS_TLS_KEY_FILE_PASS` | `REDIS_TLS_KEY_FILE_PASS_FILE` | TLS key decryption passphrase       |
| `REDIS_ACLFILE`           | `REDIS_ACLFILE_FILE`           | ACL definition file (advanced mode) |

**Precedence:**
`*_FILE` → in-memory variable → default.
That means if `REDIS_PASSWORD_FILE` is defined, it overrides any value in `REDIS_PASSWORD`.

**Example:**

```yaml
services:
  redis-node:
    image: niceos/redis-cluster:8.2.1
    environment:
      - REDIS_PASSWORD_FILE=/run/secrets/redis_pass
      - REDIS_TLS_ENABLED=yes
      - REDIS_TLS_KEY_FILE_PASS_FILE=/run/secrets/tls_keypass
    secrets:
      - redis_pass
      - tls_keypass
secrets:
  redis_pass:
    file: ./secrets/redis_password.txt
  tls_keypass:
    file: ./secrets/tls_key_password.txt
```

This model ensures you never have to expose raw secrets in `docker-compose.yml` or `kubectl describe`.

---

## 10) Modes of Operation ⚙️

NiceOS Redis® / Redis® Cluster can run in **Cluster** mode.

The most sophisticated mode — built for high availability, sharding, and linear scalability.
Cluster mode turns several Redis nodes into a **self-aware, interconnected grid** of masters and replicas.

Activated when:

* `REDIS_CLUSTER_ENABLED=yes`, **or**
* any cluster-related variable (e.g. `REDIS_NODES`, `REDIS_CLUSTER_CREATOR`) is set.

#### Example: 3 Masters + 3 Replicas

```console
docker compose -f docker-compose.cluster.yml up -d
```

**Behavior:**

* Nodes coordinate through the **cluster bus** (default port = data port + 10000).
* One node (where `REDIS_CLUSTER_CREATOR=yes`) bootstraps the cluster deterministically:

  1. Waits until all peers are resolvable (`_wait_for_dns_lookup`).
  2. Runs `redis-cli --cluster create ... --cluster-replicas N --cluster-yes`.
  3. Performs health checks (“All 16384 slots covered”).
  4. Returns to foreground Redis mode.
* The cluster state (`nodes.conf`) persists on the mounted `/app/data` volume.
* Deterministic restart: node IDs remain stable, preventing unnecessary re-sharding.

**Announcement strategy:**

| Mode                      | Controlled by                           | Description                                                     |
| ------------------------- | --------------------------------------- | --------------------------------------------------------------- |
| `dynamic`                 | `REDIS_CLUSTER_DYNAMIC_IPS=yes`         | Auto-detect IPs via Docker/K8s DNS; ideal for dynamic networks. |
| `announce-ip`             | `REDIS_CLUSTER_ANNOUNCE_IP`             | Use a fixed external IP (e.g., public node).                    |
| `announce-hostname`       | `REDIS_CLUSTER_ANNOUNCE_HOSTNAME`       | Use container hostnames for cluster gossip.                     |
| `preferred-endpoint-type` | `REDIS_CLUSTER_PREFERRED_ENDPOINT_TYPE` | Forces `ip` or `hostname` resolution globally.                  |

**Dual-port cluster:**
If `REDIS_TLS_ENABLED=yes`, both TLS and plaintext bus ports can coexist, ensuring interoperability during migration phases.

---

## 11) TLS, Healthchecks & Operational Health 🩺🔒

Security and liveness are built in. This section reflects the **exact** behavior of the shipped healthcheck script and how TLS is wired into both the server and `redis-cli` invocations.

---

### 🔒 Switching to TLS

Enable TLS with a single switch:

```bash
-e REDIS_TLS_ENABLED=yes
```

**Port semantics:**

* If `REDIS_TLS_ENABLED=yes` → the **effective client port** for health/CLI defaults to `REDIS_TLS_PORT_NUMBER` (fallback `6379`).
* If `REDIS_TLS_ENABLED` is not truthy → the effective port is `REDIS_PORT_NUMBER` (fallback `6379`).
* Dual-stack (TLS + plaintext) is possible if you explicitly configure both ports in your container/service exposure and Redis config.

**Typical TLS variables & layout (mounted under `/app/certs`):**

* `REDIS_TLS_CERT_FILE` → server certificate (e.g., `/app/certs/redis.crt`)
* `REDIS_TLS_KEY_FILE` → server key (e.g., `/app/certs/redis.key`)
* `REDIS_TLS_CA_FILE` **or** `REDIS_TLS_CA_DIR` → trust anchor(s)
* `REDIS_TLS_DH_PARAMS_FILE` → optional DH params
* `REDIS_TLS_AUTH_CLIENTS` → `yes|no` (mutual TLS toggle)

> The container’s startup validation fails fast if required files are missing or unreadable. When TLS is on, the healthcheck and bootstrap logic **automatically** pass the right `redis-cli` TLS flags.

---

### 🩺 Healthcheck: Exact Contract (matches the script)

Script: `healthcheck-redis-cluster.sh`
Interpreter flags: `set -euo pipefail` (fail-fast, strict mode)

**1) Effective host & port detection**

* Host resolution:

  1. `REDIS_HOST`
  2. `HOSTNAME`
  3. `127.0.0.1`
* Port selection:

  * If `REDIS_TLS_ENABLED` ∈ `{yes,true,on,1}` → `PORT = ${REDIS_TLS_PORT_NUMBER:-6379}`
  * Else → `PORT = ${REDIS_PORT_NUMBER:-6379}`

**2) Timing & mode knobs (defaults)**

* `HC_TIMEOUT` → **`1`** second (passed to `redis-cli -t`)
* `HC_RETRIES` → **`1`** (passed to `redis-cli -r`)
* `HC_CLUSTER_CHECK` → `auto|on|off` (default **`auto`**)

> `-r` is a `redis-cli` *repeat* count; the script uses **one** CLI process to send multiple PINGs when `HC_RETRIES>1`.

**3) Building `redis-cli` arguments (in order)**

* Base: `-h "$HOST" -p "$PORT" -t "$HC_TIMEOUT" -r "$HC_RETRIES"`
* Auth:

  * If `REDIS_PASSWORD` is set → `-a "$REDIS_PASSWORD"`
  * If `REDIS_ACL_USERNAME` is set → `--user "$REDIS_ACL_USERNAME"`
* TLS (when enabled):

  * `--tls`
  * Server auth: prefer `--cacert "$REDIS_TLS_CA_FILE"` **else** `--cacertdir "$REDIS_TLS_CA_DIR"`
  * mTLS (optional): `--cert "$REDIS_TLS_CERT_FILE"` and/or `--key "$REDIS_TLS_KEY_FILE"`

**4) Step A — Liveness by `PING`**

* Runs: `redis-cli <args…> ping`
* Fails if:

  * CLI exits non-zero (network/auth/TLS error) → prints `PING failed: <stderr>` and **exit 1**
  * Response is not exactly `PONG` → prints `Unexpected PING response: <resp>` and **exit 1**

**5) Step B — Cluster readiness (conditional)**

* Decide whether to check cluster state:

  * `HC_CLUSTER_CHECK=on|true|1` → **check**
  * `HC_CLUSTER_CHECK=off|false|0` → **skip**
  * `HC_CLUSTER_CHECK=auto` (default) → **check only if** `REDIS_CLUSTER_ENABLED` is truthy.
    ⚠️ The script’s default is `REDIS_CLUSTER_ENABLED=${REDIS_CLUSTER_ENABLED:-yes}`, so **in auto mode the cluster check is ON by default** unless you explicitly set `REDIS_CLUSTER_ENABLED=no`.
* When checking:

  * Runs: `redis-cli <args…> cluster info`
  * If CLI fails → prints `cluster info failed` and **exit 1**
  * If output lacks `^cluster_state:ok` → prints `cluster_state not OK` and **exit 1**

**6) Exit codes**

* **`0`** → healthy
* **`1`** → any failure (PING/auth/TLS/cluster not OK).
  *(There are no other numeric codes in the script.)*

---

### 🧭 Practical Examples

**Force cluster check even outside cluster mode:**

```bash
docker run --rm \
  -e HC_CLUSTER_CHECK=on \
  niceos/redis-cluster:8.2.1
```

**Skip cluster check in a single-node or replica-only deployment:**

```bash
docker run --rm \
  -e HC_CLUSTER_CHECK=off \
  niceos/redis-cluster:8.2.1
```

---

### 🔎 Operational Guidance

* **Logs:** All messages go to `stderr` and are concise: failures print *why* (e.g., `PING failed`, `cluster_state not OK`).
* **Default behavior:** In `auto` mode, cluster health is checked by default (because `REDIS_CLUSTER_ENABLED` defaults to truthy). Set `REDIS_CLUSTER_ENABLED=no` or `HC_CLUSTER_CHECK=off` to bypass cluster gating.
* **Where to look:**

  * Container logs: `docker logs <container>`
  * Manual probe: `docker exec <container> redis-cli [--tls …] ping` and `cluster info`
* **CI/CD tip:** Keep `HC_RETRIES` low (1–2) for fast fail; raise it only in slow-start environments.

---

## 12) Observability & Logging 📊

NiceOS keeps visibility boring—in the good way. Logs are consistent, live on stderr, and play nicely with whatever collector you’ve got. Health signals come from Redis itself (`PING`, `CLUSTER INFO`, `INFO *` sections), and you can crank verbosity up without turning your logs into confetti.

---

### 🧾 Where the logs go

* **Destination:** All container logs go to **stderr** by design. No on-disk log files inside the container.
* **Collection:** Use your platform’s normal pipeline:

  * Docker: `docker logs <container>` (default `json-file` driver)
  * Swap drivers if needed: `--log-driver local|journald|fluentd|gelf|awslogs|syslog|…`
  * Kubernetes: kubelet tails container streams → your log agent (Fluent Bit, Vector, etc.)
* **Why stderr?** Zero in-container rotation, no inode leaks, trivial shipping to SIEM/ELK/ClickHouse.

Minimal examples:

```console
# Live tail
docker logs -f redis-node1

# With a custom driver (example)
docker run --log-driver local niceos/redis-cluster:8.2.1
```

---

### 🐛 Debug switches (turn up the light, not the heat)

You can increase verbosity without changing the container image:

* `NICEOS_DEBUG=yes` → enables chatty, human-readable diagnostics from NiceOS scripts (setup, run, health).
* `NICEOS_TRACE=yes` → ultra-verbose tracing (function-level noise); great for CI flakiness hunts.
* `BITNAMI_DEBUG=yes` → **mapped to `NICEOS_DEBUG=yes`** for drop-in compatibility with Bitnami-style configs.

Examples:

```console
# Extra diagnostics on startup & health
docker run -e NICEOS_DEBUG=yes niceos/redis-cluster:8.2.1

# Trace-level for deep dives (use sparingly)
docker run -e NICEOS_TRACE=yes niceos/redis-cluster:8.2.1

# Bitnami-compatible flag, auto-mapped
docker run -e BITNAMI_DEBUG=yes niceos/redis-cluster:8.2.1
```

**What you’ll see with DEBUG/TRACE on:**

* Explicit printouts of effective host/port, chosen TLS flags, and config merges.
* Clear failure reasons from health checks (e.g., “cluster_state not OK”, “PING failed: …”).
* Deterministic cluster bootstrap steps (creator node flows, DNS wait loops).

---

### ✅ Practical sign-off checklist (quick)

* Logs show **no** repeated restarts or backoff loops.
* `redis-cli ping` → `PONG` (with TLS flags if TLS is enabled).
* Replication: master/replica linkage healthy.
* Cluster: `cluster_state:ok` and expected master/replica counts.
* Memory within budget, CPU steady, ops/sec plausible for your load pattern.

When these are true, your observability is doing its job—quietly, reliably, predictably.


---

## 13) Troubleshooting Cookbook 🧩

Even well-behaved clusters occasionally throw tantrums. This section gives you a **symptom → likely cause → verified fix** matrix, followed by a quick anatomy lesson on `nodes.conf` and how to safely recover a broken cluster.

---

### 🧠 Symptom Matrix

| 🩸 Symptom                                          | 🧩 Likely Cause                                                                                    | 🔧 Fix                                                                                                                                                                    |
| --------------------------------------------------- | -------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`cluster_state:fail` or `cluster_state:not ok`**  | Cluster bus unreachable between nodes; mismatched announce IP/hostname; incomplete slot assignment | Verify `REDIS_CLUSTER_ANNOUNCE_*` settings. Ensure ports `6379` and `16379` (bus) are open. Run `redis-cli cluster nodes` to locate `handshake` nodes.                    |
| **Cluster bootstrap never completes**               | `REDIS_CLUSTER_CREATOR` node started before peers resolved                                         | Delay creator start or set `REDIS_CLUSTER_SLEEP_BEFORE_DNS_LOOKUP=20`. Use `HC_CLUSTER_CHECK=on` for deterministic readiness gating.                                      |
| **TLS handshake failure**                           | Wrong CA chain, unreadable key file, or missing passphrase                                         | Verify mounted certs: permissions `0400–0644`, owner matches container user. Confirm `REDIS_TLS_KEY_FILE_PASS` if key is encrypted. Check for path typos in `/app/certs`. |
| **Replica refuses to follow master**                | Password mismatch or incorrect `REDIS_MASTER_HOST` resolution                                      | Ensure `REDIS_MASTER_PASSWORD` on replica matches master’s `REDIS_PASSWORD`. Verify DNS with `getent hosts redis-master`.                                                 |
| **Replica flips between master/slave repeatedly**   | Sentinel misconfiguration or duplicate node ID                                                     | If Sentinel used, clear `nodes.conf` and let replica resync. Persist volumes for stable node IDs.                                                                         |
| **Healthcheck fails only under ACL mode**           | Wrong `REDIS_ACL_USERNAME` or password not set                                                     | Confirm both `REDIS_ACL_USERNAME` and `REDIS_PASSWORD` defined. Test manually: `redis-cli --user <user> -a <pass> ping`.                                                  |
| **`PING` works but `cluster info` fails**           | Cluster partially formed (node IDs mismatch)                                                       | Check `/app/data/nodes.conf` across nodes—IDs must be unique. If inconsistent, delete all `nodes.conf` and restart cluster creation node.                                 |
| **TLS nodes connect internally but not externally** | Announce using internal DNS name only                                                              | Set `REDIS_CLUSTER_ANNOUNCE_IP` to public IP or ingress hostname; optionally set `REDIS_CLUSTER_PREFERRED_ENDPOINT_TYPE=hostname`.                                        |
| **Redis fails to start after config mount**         | Syntax error or conflicting directives in mounted `redis.conf`                                     | Run `redis-server --test-memory` or `redis-server /path/to/redis.conf --check-config`. Mount minimal config first, then layer overrides.                                  |

---

### 🧬 Deep Dive: `nodes.conf` Anatomy

`nodes.conf` is Redis’s **internal cluster registry**, not user-editable, but understanding it helps during recovery.

Typical lines:

```
8f1dc5323... redis-node1:6379@16379 master - 0 1717287826000 1 connected 0-5460
b57e9238a... redis-node2:6379@16379 slave 8f1dc5323... 0 1717287827000 2 connected
```

**Key fields (left to right):**

1. Node ID (persistent identity)
2. Endpoint and bus port
3. Role (`master` or `slave`)
4. Master ID (for replicas)
5. Ping/pong timestamps
6. Config epoch (used for conflict resolution)
7. Connection state
8. Slot assignment (only for masters)

**Safe recovery procedure (when cluster is borked):**

1. Stop all Redis nodes.
2. Delete only `nodes.conf` files (`rm /app/data/nodes.conf`).
3. Restart the designated `REDIS_CLUSTER_CREATOR=yes` node **after** all peers are up.
4. Wait for `cluster_state:ok` in `redis-cli cluster info`.
5. Optionally run `redis-cli --cluster fix host:6379`.

Never edit `nodes.conf` by hand; it’s rewritten at runtime and signature-checked by Redis.

---

## 14) Bitnami Compatibility Guide 🔄

NiceOS Redis® images preserve **drop-in environmental compatibility** with Bitnami containers—plus several deterministic and security improvements.

---

### ⚙️ Environment Variable Equivalence

| Bitnami Variable            | NiceOS Equivalent       | Notes                                                     |       |                 |
| --------------------------- | ----------------------- | --------------------------------------------------------- | ----- | --------------- |
| `BITNAMI_DEBUG`             | `NICEOS_DEBUG`          | Identical semantics; enables verbose logs                 |       |                 |
| `REDIS_PASSWORD`            | same                    | Auth password                                             |       |                 |
| `REDIS_MASTER_PASSWORD`     | same                    | Replication auth                                          |       |                 |
| `REDIS_REPLICATION_MODE`    | same                    | `master` / `replica`                                      |       |                 |
| `REDIS_CLUSTER_CREATOR`     | same                    | Bootstraps cluster                                        |       |                 |
| `REDIS_CLUSTER_REPLICAS`    | same                    | Replica factor                                            |       |                 |
| `REDIS_CLUSTER_DYNAMIC_IPS` | same                    | Dynamic IP detection                                      |       |                 |
| `REDIS_CLUSTER_ANNOUNCE_*`  | same                    | Host/IP/bus port advertisement                            |       |                 |
| `REDIS_TLS_ENABLED`         | same                    | Enable TLS                                                |       |                 |
| `REDIS_TLS_*`               | same                    | Full TLS suite supported                                  |       |                 |
| `ALLOW_EMPTY_PASSWORD`      | same                    | Only allowed for dev use                                  |       |                 |
| —                           | `NICEOS_TRACE`          | Extended debug (no Bitnami equivalent)                    |       |                 |
| —                           | `NICEOS_LOG_FORMAT=json | plain                                                     | both` | Structured logs |
| —                           | `HC_*` variables        | Healthcheck tuning (Bitnami used built-in Docker healths) |       |                 |

---

### 🧠 Behavior Differences

| Category              | Bitnami                                              | NiceOS                                                                      |
| --------------------- | ---------------------------------------------------- | --------------------------------------------------------------------------- |
| **Logging**           | Writes to `/opt/bitnami/redis/logs/redis.log` (file) | All logs to **stderr**; Docker logging driver friendly                      |
| **Filesystem layout** | `/opt/bitnami/redis/...`                             | `/app/...` (`/app/data`, `/app/etc`, `/app/certs`, etc.)                    |
| **Cluster bootstrap** | Asynchronous init, sometimes racy                    | Deterministic, idempotent bootstrap via `REDIS_CLUSTER_CREATOR` logic       |
| **Healthchecks**      | Minimal `redis-cli ping`                             | Full TLS-aware cluster health script                                        |
| **TLS defaults**      | Optional, not enforced                               | TLS fully integrated; validated at startup                                  |
| **Volumes**           | `/bitnami/redis`                                     | `/app/data` (for persistence)                                               |
| **Process model**     | Foreground `redis-server` only                       | Foreground `redis-server` + lifecycle scripts (`setup.sh`, `entrypoint.sh`) |

---

### 🧳 Migration Notes (Bitnami → NiceOS)

| Step  | Action                                                                          |
| ----- | ------------------------------------------------------------------------------- |
| **1** | Change image name from `bitnami/redis-cluster` → `niceos/redis-cluster:8.2.1`   |
| **2** | Update volume mount: `/bitnami/redis` → `/app/data`                             |
| **3** | Remove file-based logs; rely on `docker logs`                                   |
| **4** | Replace any custom health commands with `healthcheck-redis-cluster.sh` |
| **5** | Keep all `REDIS_*` and `ALLOW_EMPTY_PASSWORD` vars — they are fully supported.  |
| **6** | Optional: add `NICEOS_DEBUG=yes` for richer diagnostics.                        |

---

### 💡 Compatibility Summary

* Fully **drop-in compatible** for standard Bitnami deployments.
* Stricter security and cleaner logging out of the box.
* Deterministic clustering means **no orphan masters** or endless handshake loops.
* Ideal for migrating existing Bitnami Redis clusters to a smaller, auditable, and fully SBOM-scanned base image.

---

## 15) Examples Gallery 🎛️

Concrete, copy-pasteable scenarios for common topologies. Each example includes a `docker run` one-liner, a `docker-compose.yaml` variant, and the **expected outcome** so you know what “good” looks like.

---

### A) Dev Single Node (no TLS) 🧪

**Goal:** ultra-fast local Redis for apps/tests. Passwordless is **dev only**.

#### `docker run`

```console
docker run -d --name redis-dev \
  -e ALLOW_EMPTY_PASSWORD=yes \
  -p 6379:6379 \
  niceos/redis:8.2.1
```

#### `docker-compose.yaml`

```yaml
services:
  redis-dev:
    image: niceos/redis:8.2.1
    container_name: redis-dev
    environment:
      - ALLOW_EMPTY_PASSWORD=yes
    ports:
      - "6379:6379"
```

**Expected outcome**

* `docker logs redis-dev` shows Redis ready; `PING` → `PONG`.
* `redis-cli -h 127.0.0.1 -p 6379 ping` returns `PONG`.
* No cluster bus, no replication; pure standalone.

---

### B) Prod 3 Masters + 3 Replicas (TLS-only) 🏭🔐

**Goal:** production cluster with full encryption. Plaintext port disabled.

#### `docker-compose.yaml`

```yaml
version: "3.8"
services:
  r1:
    image: niceos/redis-cluster:8.2.1
    hostname: r1
    environment:
      - REDIS_PASSWORD=${REDIS_PASSWORD:?set_me}
      - REDIS_TLS_ENABLED=yes
      - REDIS_TLS_CERT_FILE=/app/certs/redis.crt
      - REDIS_TLS_KEY_FILE=/app/certs/redis.key
      - REDIS_TLS_CA_FILE=/app/certs/ca.crt
      - REDIS_CLUSTER_CREATOR=yes
      - REDIS_CLUSTER_REPLICAS=1
      - HC_CLUSTER_CHECK=on
    volumes:
      - r1_data:/app/data
      - ./certs:/app/certs:ro
    networks: [rnet]

  r2:
    image: niceos/redis-cluster:8.2.1
    hostname: r2
    environment:
      - REDIS_PASSWORD=${REDIS_PASSWORD:?set_me}
      - REDIS_TLS_ENABLED=yes
      - REDIS_TLS_CERT_FILE=/app/certs/redis.crt
      - REDIS_TLS_KEY_FILE=/app/certs/redis.key
      - REDIS_TLS_CA_FILE=/app/certs/ca.crt
    volumes: [r2_data:/app/data, ./certs:/app/certs:ro]
    networks: [rnet]

  r3:
    image: niceos/redis-cluster:8.2.1
    hostname: r3
    environment:
      - REDIS_PASSWORD=${REDIS_PASSWORD:?set_me}
      - REDIS_TLS_ENABLED=yes
      - REDIS_TLS_CERT_FILE=/app/certs/redis.crt
      - REDIS_TLS_KEY_FILE=/app/certs/redis.key
      - REDIS_TLS_CA_FILE=/app/certs/ca.crt
    volumes: [r3_data:/app/data, ./certs:/app/certs:ro]
    networks: [rnet]

  r4:
    image: niceos/redis-cluster:8.2.1
    hostname: r4
    environment:
      - REDIS_PASSWORD=${REDIS_PASSWORD:?set_me}
      - REDIS_TLS_ENABLED=yes
      - REDIS_TLS_CERT_FILE=/app/certs/redis.crt
      - REDIS_TLS_KEY_FILE=/app/certs/redis.key
      - REDIS_TLS_CA_FILE=/app/certs/ca.crt
    volumes: [r4_data:/app/data, ./certs:/app/certs:ro]
    networks: [rnet]

  r5:
    image: niceos/redis-cluster:8.2.1
    hostname: r5
    environment:
      - REDIS_PASSWORD=${REDIS_PASSWORD:?set_me}
      - REDIS_TLS_ENABLED=yes
      - REDIS_TLS_CERT_FILE=/app/certs/redis.crt
      - REDIS_TLS_KEY_FILE=/app/certs/redis.key
      - REDIS_TLS_CA_FILE=/app/certs/ca.crt
    volumes: [r5_data:/app/data, ./certs:/app/certs:ro]
    networks: [rnet]

  r6:
    image: niceos/redis-cluster:8.2.1
    hostname: r6
    environment:
      - REDIS_PASSWORD=${REDIS_PASSWORD:?set_me}
      - REDIS_TLS_ENABLED=yes
      - REDIS_TLS_CERT_FILE=/app/certs/redis.crt
      - REDIS_TLS_KEY_FILE=/app/certs/redis.key
      - REDIS_TLS_CA_FILE=/app/certs/ca.crt
    volumes: [r6_data:/app/data, ./certs:/app/certs:ro]
    networks: [rnet]

networks:
  rnet:
    driver: bridge

volumes:
  r1_data: {}
  r2_data: {}
  r3_data: {}
  r4_data: {}
  r5_data: {}
  r6_data: {}
```

#### Minimal `docker run` (single secure node)

```console
docker run -d --name redis-tls \
  -v $PWD/certs:/app/certs:ro \
  -e REDIS_PASSWORD=StrongPass123 \
  -e REDIS_TLS_ENABLED=yes \
  -e REDIS_TLS_CERT_FILE=/app/certs/redis.crt \
  -e REDIS_TLS_KEY_FILE=/app/certs/redis.key \
  -e REDIS_TLS_CA_FILE=/app/certs/ca.crt \
  niceos/redis:8.2.1
```

**Expected outcome**

* `HC_CLUSTER_CHECK=on` makes health green **only** when `cluster_state:ok`.
* `redis-cli --tls --cacert ca.crt -a $REDIS_PASSWORD -h r1 -p 6379 ping` → `PONG`.
* `cluster info` shows `cluster_state:ok`; 16,384 slots covered; 3 masters, 3 replicas.

---

### C) IPv6-only Cluster with Announce-Hostname 🌐🆚

**Goal:** run Redis Cluster in IPv6-only networks using DNS hostnames for gossip/clients.

#### `docker-compose.yaml`

```yaml
services:
  n1:
    image: niceos/redis-cluster:8.2.1
    hostname: n1.redis.local
    environment:
      - REDIS_PASSWORD=${REDIS_PASSWORD:?set_me}
      - REDIS_CLUSTER_CREATOR=yes
      - REDIS_CLUSTER_REPLICAS=1
      - REDIS_CLUSTER_PREFERRED_ENDPOINT_TYPE=hostname
      - REDIS_CLUSTER_ANNOUNCE_HOSTNAME=n1.redis.local
      - REDIS_CLUSTER_DYNAMIC_IPS=no
      - REDIS_ALLOW_REMOTE_CONNECTIONS=yes
    sysctls:               # helpful for IPv6-heavy labs
      net.ipv6.conf.all.disable_ipv6: "0"
    networks: [v6net]
    volumes: [n1data:/app/data]

  n2:
    image: niceos/redis-cluster:8.2.1
    hostname: n2.redis.local
    environment:
      - REDIS_PASSWORD=${REDIS_PASSWORD:?set_me}
      - REDIS_CLUSTER_PREFERRED_ENDPOINT_TYPE=hostname
      - REDIS_CLUSTER_ANNOUNCE_HOSTNAME=n2.redis.local
      - REDIS_CLUSTER_DYNAMIC_IPS=no
      - REDIS_ALLOW_REMOTE_CONNECTIONS=yes
    networks: [v6net]
    volumes: [n2data:/app/data]

  n3:
    image: niceos/redis-cluster:8.2.1
    hostname: n3.redis.local
    environment:
      - REDIS_PASSWORD=${REDIS_PASSWORD:?set_me}
      - REDIS_CLUSTER_PREFERRED_ENDPOINT_TYPE=hostname
      - REDIS_CLUSTER_ANNOUNCE_HOSTNAME=n3.redis.local
      - REDIS_CLUSTER_DYNAMIC_IPS=no
      - REDIS_ALLOW_REMOTE_CONNECTIONS=yes
    networks: [v6net]
    volumes: [n3data:/app/data]

networks:
  v6net:
    driver: bridge
    enable_ipv6: true
    ipam:
      driver: default
      config:
        - subnet: "fd00:1234::/64"

volumes:
  n1data: {}
  n2data: {}
  n3data: {}
```

#### `docker run` (single IPv6 node, dev)

```console
docker run -d --name redis-v6 \
  --sysctl net.ipv6.conf.all.disable_ipv6=0 \
  -e ALLOW_EMPTY_PASSWORD=yes \
  niceos/redis-cluster:8.2.1
```

**Expected outcome**

* The creator forms a cluster using **hostnames** (no raw IPs in `nodes.conf`).
* `cluster nodes` shows endpoints like `n1.redis.local:6379@16379`.
* Healthcheck passes when `cluster_state:ok`; IPv6 connectivity verified by DNS.

---

## 25) Environment Reference (complete, structured) 🧭

> Table schema per group:
> **Name** | **Type** | **Default** | **Mode(s)** | **Maps to (redis.conf / CLI)** | **Used by** | **Secret** | **Hot-reload** | **Notes**
> **Mode(s):** Standalone / Replication / Cluster. **Used by:** `setup.sh` / `run.sh` / `libredis.sh` / `librediscluster.sh` / `healthcheck-redis-cluster.sh`.

---

### 25.1 Core paths & identity

| Name                                   | Type   | Default                  | Mode(s) | Maps to (redis.conf / CLI)                 | Used by          | Secret | Hot-reload | Notes                                        |
| -------------------------------------- | ------ | ------------------------ | ------- | ------------------------------------------ | ---------------- | ------ | ---------- | -------------------------------------------- |
| REDIS_BASE_DIR                         | path   | `/app`                   | all     | –                                          | setup            | no     | n/a        | Root of runtime layout                       |
| REDIS_CONF_DIR                         | path   | `/app/etc`               | all     | –                                          | setup            | no     | n/a        |                                              |
| REDIS_DEFAULT_CONF_DIR                 | path   | `/app/etc.default`       | all     | –                                          | entrypoint/setup | no     | n/a        | Seeds defaults if empty                      |
| REDIS_MOUNTED_CONF_DIR                 | path   | `/app/mounted-etc`       | all     | –                                          | setup            | no     | n/a        | Full config override if `redis.conf` present |
| REDIS_CONF_FILE                        | path   | `/app/etc/redis.conf`    | all     | –                                          | setup/run        | no     | n/a        | Generated if not mounted                     |
| REDIS_DATA_DIR                         | path   | `/app/data`              | all     | `dir`, `dbfilename`, `cluster-config-file` | setup/run        | no     | n/a        | Persistent volume                            |
| REDIS_LOG_DIR                          | path   | `/app/logs`              | all     | –                                          | setup            | no     | n/a        | Logs go to **stderr** by design              |
| REDIS_TMP_DIR                          | path   | `/app/run`               | all     | –                                          | setup/run        | no     | n/a        | PID/socket staging                           |
| REDIS_PID_FILE                         | path   | `/app/run/redis.pid`     | all     | `pidfile`                                  | setup/run        | no     | n/a        |                                              |
| REDIS_DAEMON_USER / REDIS_DAEMON_GROUP | string | `app` / `app`            | all     | –                                          | setup            | no     | n/a        | Ownership if running as root                 |
| REDIS_HOST                             | host   | `HOSTNAME` → `127.0.0.1` | all     | announce helpers                           | run              | no     | n/a        | Effective host for CLI/health                |

---

### 25.2 Ports & binding

| Name                           | Type | Default                        | Mode(s) | Maps to                | Used by   | Secret | Hot-reload                 | Notes                                           |
| ------------------------------ | ---- | ------------------------------ | ------- | ---------------------- | --------- | ------ | -------------------------- | ----------------------------------------------- |
| REDIS_DEFAULT_PORT_NUMBER      | int  | `6379`                         | all     | `port`                 | setup     | no     | risky via `CONFIG REWRITE` | Build-time/default                              |
| REDIS_PORT_NUMBER              | int  | `${REDIS_DEFAULT_PORT_NUMBER}` | all     | `port`                 | setup/run | no     | no                         | Effective data/plaintext port (if TLS disabled) |
| REDIS_PORT (legacy)            | int  | –                              | all     | `port`                 | run       | no     | no                         | Back-compat only                                |
| REDIS_ALLOW_REMOTE_CONNECTIONS | bool | `yes`                          | all     | `bind`, protected-mode | setup     | no     | yes*                       | Binds `0.0.0.0 ::` if allowed                   |

---

### 25.3 Auth & ACL

| Name                  | Type   | Default | Mode(s)      | Maps to                        | Used by                 | Secret  | Hot-reload | Notes                                         |
| --------------------- | ------ | ------- | ------------ | ------------------------------ | ----------------------- | ------- | ---------- | --------------------------------------------- |
| ALLOW_EMPTY_PASSWORD  | bool   | `no`    | all          | `protected-mode no` (when yes) | libredis/setup          | –       | yes*       | Dev-only; refuse remote exposure with no auth |
| REDIS_PASSWORD        | string | –       | all          | `requirepass` / CLI `-a`       | libredis / run / health | **yes** | yes        | Primary auth secret                           |
| REDIS_MASTER_PASSWORD | string | –       | repl/cluster | `masterauth`                   | libredis                | **yes** | yes        | For replicas following master                 |
| REDIS_ACLFILE         | path   | –       | all          | `aclfile`                      | libredis                | no      | partial    | Optional ACL rules file                       |
| REDIS_ACL_USERNAME    | string | –       | all          | CLI `--user`                   | healthcheck             | no      | yes        | For health/CLI under ACL                      |

---

### 25.4 Persistence

| Name                      | Type                      | Default | Mode(s) | Maps to                                  | Used by  | Secret | Hot-reload           | Notes                     |
| ------------------------- | ------------------------- | ------- | ------- | ---------------------------------------- | -------- | ------ | -------------------- | ------------------------- |
| REDIS_AOF_ENABLED         | bool                      | `yes`   | all     | `appendonly yes`, `appendfsync everysec` | setup    | no     | via CONFIG (caution) | Safer durability defaults |
| REDIS_RDB_POLICY          | string list `sec#changes` | –       | all     | multiple `save` lines                    | libredis | no     | yes                  | Example: `"900#1 300#10"` |
| REDIS_RDB_POLICY_DISABLED | bool                      | `no`    | all     | `save ""`                                | libredis | no     | yes                  | Disables RDB checkpoints  |

---

### 25.5 Replication & Sentinel

| Name                                                                          | Type         | Default  | Mode(s) | Maps to                  | Used by                   | Secret   | Hot-reload | Notes                       |                          |
| ----------------------------------------------------------------------------- | ------------ | -------- | ------- | ------------------------ | ------------------------- | -------- | ---------- | --------------------------- | ------------------------ |
| REDIS_REPLICATION_MODE                                                        | enum `master | replica` | –       | repl                     | `replicaof`, `masterauth` | libredis | no         | dynamic                     | Enables replication role |
| REDIS_MASTER_HOST                                                             | host         | –        | repl    | `replicaof`              | libredis                  | no       | dynamic    | Master address for replicas |                          |
| REDIS_MASTER_PORT_NUMBER                                                      | int          | `6379`   | repl    | `replicaof`              | libredis                  | no       | dynamic    | Master port                 |                          |
| REDIS_REPLICA_IP / REDIS_REPLICA_PORT                                         | host/int     | –        | repl    | announce hints           | libredis                  | no       | n/a        | Optional explicit announce  |                          |
| REDIS_SENTINEL_HOST / REDIS_SENTINEL_PORT_NUMBER / REDIS_SENTINEL_MASTER_NAME | host/int/str | –        | repl    | Sentinel discovery (CLI) | libredis                  | no       | n/a        | For Sentinel-aware replicas |                          |

---

### 25.6 TLS

| Name                                 | Type   | Default | Mode(s) | Maps to                            | Used by           | Secret  | Hot-reload | Notes                     |
| ------------------------------------ | ------ | ------- | ------- | ---------------------------------- | ----------------- | ------- | ---------- | ------------------------- |
| REDIS_TLS_ENABLED                    | bool   | `no`    | all     | `tls-*` keys                       | libredis          | no      | restart    | Master switch             |
| REDIS_TLS_PORT_NUMBER                | int    | `6379`  | all     | `tls-port`                         | libredis          | no      | restart    | Effective TLS client port |
| REDIS_TLS_CERT_FILE                  | path   | –       | all     | `tls-cert-file`                    | libredis          | no      | restart    | Server cert               |
| REDIS_TLS_KEY_FILE                   | path   | –       | all     | `tls-key-file`                     | libredis          | no      | restart    | Server key                |
| REDIS_TLS_KEY_FILE_PASS              | string | –       | all     | `tls-key-file-pass` / CLI `--pass` | libredis          | **yes** | restart    | Key passphrase            |
| REDIS_TLS_CA_FILE / REDIS_TLS_CA_DIR | path   | –       | all     | `tls-ca-*`                         | libredis / health | no      | restart    | Trust anchor(s)           |
| REDIS_TLS_DH_PARAMS_FILE             | path   | –       | all     | `tls-dh-params-file`               | libredis          | no      | restart    | Optional DH params        |
| REDIS_TLS_AUTH_CLIENTS               | bool   | `yes`   | all     | `tls-auth-clients`                 | libredis          | no      | restart    | mTLS toggle               |
| REDIS_TLS_PORT (legacy)              | int    | –       | all     | seeds `REDIS_TLS_PORT_NUMBER`      | libredis          | no      | restart    | Alias for compat          |

---

### 25.7 Cluster

| Name                                  | Type               | Default                        | Mode(s)         | Maps to                        | Used by             | Secret             | Hot-reload      | Notes                                    |     |                 |
| ------------------------------------- | ------------------ | ------------------------------ | --------------- | ------------------------------ | ------------------- | ------------------ | --------------- | ---------------------------------------- | --- | --------------- |
| REDIS_CLUSTER_ENABLED                 | bool               | `yes`                          | cluster         | `cluster-enabled yes`          | run/libredis        | no                 | restart         | Default truthy for HC auto-mode          |     |                 |
| REDIS_NODES                           | list `host[:port]` | –                              | cluster         | CLI `--cluster create` targets | librediscluster     | no                 | n/a             | Creator uses this                        |     |                 |
| REDIS_CLUSTER_CREATOR                 | bool               | `no`                           | cluster         | bootstrap role                 | run/librediscluster | no                 | n/a             | One node should set `yes`                |     |                 |
| REDIS_CLUSTER_REPLICAS                | int                | `1`                            | cluster         | `--cluster-replicas`           | librediscluster     | no                 | n/a             | Replica factor per master                |     |                 |
| REDIS_CLUSTER_DYNAMIC_IPS             | bool               | `yes`                          | cluster         | announce strategy              | librediscluster     | no                 | n/a             | Auto-detect endpoints                    |     |                 |
| REDIS_CLUSTER_ANNOUNCE_IP             | ip                 | –                              | cluster         | `cluster-announce-ip`          | librediscluster     | no                 | n/a             | Fixed external IP                        |     |                 |
| REDIS_CLUSTER_ANNOUNCE_HOSTNAME       | hostname           | –                              | cluster         | `cluster-announce-hostname`    | librediscluster     | no                 | n/a             | DNS hostname announce                    |     |                 |
| REDIS_CLUSTER_ANNOUNCE_PORT           | int                | –                              | cluster         | `cluster-announce-port`        | librediscluster     | no                 | n/a             | Client port override                     |     |                 |
| REDIS_CLUSTER_ANNOUNCE_BUS_PORT       | int                | –                              | cluster         | `cluster-announce-bus-port`    | librediscluster     | no                 | n/a             | Bus port override (default = data+10000) |     |                 |
| REDIS_CLUSTER_PREFERRED_ENDPOINT_TYPE | enum `ip           | hostname                       | all-interfaces` | `ip`                           | cluster             | announce selection | librediscluster | no                                       | n/a | Endpoint policy |
| REDIS_CLUSTER_NODE_TIMEOUT_MS         | int ms             | `5000`                         | cluster         | `cluster-node-timeout`         | libredis            | no                 | reload          | Gossip timing                            |     |                 |
| REDIS_CLUSTER_NODES_FILE              | path               | `${REDIS_DATA_DIR}/nodes.conf` | cluster         | `cluster-config-file`          | libredis            | no                 | n/a             | Persist node IDs/slots                   |     |                 |
| REDIS_DNS_RETRIES                     | int                | `120`                          | cluster         | lookup loop budget             | librediscluster     | no                 | n/a             | DNS robustness                           |     |                 |
| REDIS_CLUSTER_SLEEP_BEFORE_DNS_LOOKUP | int sec            | `0`                            | cluster         | initial delay                  | librediscluster     | no                 | n/a             | Helps flaky DNS                          |     |                 |
| REDIS_CLUSTER_DNS_LOOKUP_RETRIES      | int                | `1`                            | cluster         | lookup retries                 | librediscluster     | no                 | n/a             | Combine with SLEEP                       |     |                 |
| REDIS_CLUSTER_DNS_LOOKUP_SLEEP        | int sec            | `1`                            | cluster         | sleep between retries          | librediscluster     | no                 | n/a             |                                          |     |                 |

---

### 25.8 Performance & extras

| Name                      | Type   | Default          | Mode(s) | Maps to               | Used by  | Secret | Hot-reload | Notes                       |
| ------------------------- | ------ | ---------------- | ------- | --------------------- | -------- | ------ | ---------- | --------------------------- |
| REDIS_IO_THREADS          | int    | –                | all     | `io-threads`          | libredis | no     | restart    | Enable only when beneficial |
| REDIS_IO_THREADS_DO_READS | bool   | –                | all     | `io-threads-do-reads` | libredis | no     | restart    | Read threading              |
| REDIS_DISABLE_COMMANDS    | CSV    | –                | all     | `rename-command ""`   | libredis | no     | reload     | Disable dangerous ops       |
| REDIS_EXTRA_FLAGS         | string | –                | all     | argv passthrough      | run      | no     | n/a        | Appended to `redis-server`  |
| REDIS_DATABASE            | string | `redis` (compat) | all     | –                     | libredis | no     | n/a        | Parity/no direct mapping    |
| REDIS_OVERRIDES_FILE      | path   | –                | all     | final `include`       | libredis | no     | reload     | Tail include wins           |

---

### 25.9 Healthcheck tuning

| Name             | Type       | Default | Mode(s) | Maps to  | Used by     | Secret         | Hot-reload  | Notes                            |     |                                                      |
| ---------------- | ---------- | ------- | ------- | -------- | ----------- | -------------- | ----------- | -------------------------------- | --- | ---------------------------------------------------- |
| HC_TIMEOUT       | int sec    | `1`     | all     | CLI `-t` | healthcheck | no             | n/a         | Per-attempt timeout              |     |                                                      |
| HC_RETRIES       | int        | `1`     | all     | CLI `-r` | healthcheck | no             | n/a         | Repeat count within one CLI call |     |                                                      |
| HC_CLUSTER_CHECK | enum `auto | on      | off`    | `auto`   | cluster     | cluster gating | healthcheck | no                               | n/a | `auto` checks when `REDIS_CLUSTER_ENABLED` is truthy |

---

### 25.10 Debug & diagnostics

| Name          | Type | Default | Mode(s) | Maps to                 | Used by    | Secret | Hot-reload | Notes                      |
| ------------- | ---- | ------- | ------- | ----------------------- | ---------- | ------ | ---------- | -------------------------- |
| NICEOS_DEBUG  | bool | `false` | all     | verbose logs            | all        | no     | n/a        | Human-readable diagnostics |
| NICEOS_TRACE  | bool | `false` | all     | trace logs              | all        | no     | n/a        | Very chatty; CI deep dives |
| BITNAMI_DEBUG | bool | –       | all     | mapped → `NICEOS_DEBUG` | env-loader | no     | n/a        | Drop-in compat flag        |

---

### 25.11 Secrets via `*_FILE` (curated)

| File Variable                  | Sets                      | Notes                             |
| ------------------------------ | ------------------------- | --------------------------------- |
| `REDIS_PASSWORD_FILE`          | `REDIS_PASSWORD`          | If readable, overrides inline env |
| `REDIS_MASTER_PASSWORD_FILE`   | `REDIS_MASTER_PASSWORD`   | For replica → master auth         |
| `REDIS_TLS_KEY_FILE_PASS_FILE` | `REDIS_TLS_KEY_FILE_PASS` | For encrypted TLS keys            |

**Precedence rule:** `*_FILE` → variable → default. If a `*_FILE` var is set and readable, its content wins over any direct value in the corresponding variable.


