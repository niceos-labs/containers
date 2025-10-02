## 1. Introduction

**What is Redis (in plain words).**
Redis is an in-memory data store you talk to over the network. It excels at keeping small pieces of data—strings, hashes, lists, sets, sorted sets—right next to the CPU for ultra-low latency. You can use it as a cache, a message broker, a rate limiter, a coordination layer, or even a tiny real-time database when durability is configured.

**Why a Redis container image for NiceOS.**
Running Redis well isn’t just “start a process and hope for the best.” Operations teams need predictable startup, safe configuration changes, sensible defaults, clean logs, non-root execution, secret management, and repeatable outcomes across environments. The NiceOS Redis image packages those concerns into a single, auditable artifact that works uniformly on laptops, CI runners, and production clusters.

**How this image differs from the vanilla Docker Hub image and Bitnami.**

* **NiceOS libraries baked in.**
  The image ships with the NiceOS runtime libraries (logging, filesystem, OS/user helpers, validations, networking). These small, focused utilities power safer entrypoints, graceful shutdowns, permission fixes, health probes, and configuration edits without re-implementing ad-hoc shell fragments in every script.

* **Strict idempotency and verifiable configuration.**
  Defaults are copied without overwriting user files; updates to `redis.conf` are done via explicit, line-level operations rather than blind rewrites. On each start, the same inputs lead to the same outputs—making behavior predictable in CI/CD and easy to audit during incident reviews.

* **Enterprise-grade logging by default.**
  Structured logging (plain and JSON), leveled output (ERROR/WARN/INFO/DEBUG/TRACE), rate-limiting of duplicate messages, optional color, and consistent module tags give you readable container logs locally and machine-parsable logs in production. This reduces noise and speeds up troubleshooting.

* **Production-first posture (not just dev convenience).**
  The image runs as a non-root user, honors secret files (`*_FILE`) to avoid leaking credentials, supports TLS/ACL configuration with validation, and keeps Redis in the foreground for clean PID 1 semantics and graceful termination. Quick-start commands are available, but the defaults and documentation assume real deployments, not only demos.


## 2. Key Differentiators of NiceOS Redis

📦 **Idempotent configuration management**
Default configs are copied into place *without overwriting* user-provided files. Every container start is predictable and audit-friendly.

🛠 **Clear separation: Setup vs Run**
The setup script fine-tunes `redis.conf` Bitnami-style (safe defaults, security hardening). The run script always launches Redis in **foreground mode** with `--daemonize no`, ensuring clean PID 1 behavior in containers.

🧑‍💻 **Runs as non-root by default**
Redis starts as UID:GID **10001:10001**, with safe directory ownership checks and permission fixes. No privileged user required.

🔒 **Secret management via `*_FILE`**
Passwords, certificates, and sensitive data are mounted as files—not plain env vars—so they never leak in `docker inspect` or `ps`.

🌐 **Built-in TLS and ACL support with validations**
TLS is first-class: certs, keys, CA, DH params are validated before start. ACL files are supported out-of-the-box for fine-grained access control.

📝 **Enterprise-grade logging**
Structured JSON and colorful human logs, deduplication of repeated messages, module tags, and consistent levels (ERROR/WARN/INFO/DEBUG/TRACE). Tail logs comfortably *or* parse them automatically.

🇷🇺 **Russian localization available**
When `LANG=ru_RU.UTF-8`, all helper scripts switch to Russian messages and log output—helpful for operators in domestic environments.


## 3. Quick Start (TL;DR) 🚀

The NiceOS Redis container comes with sane defaults, but you can start small or go production-ready in just a few lines.

### 🔓 Easiest way (development only!)

```bash
docker run --rm -it \
  --name redis-dev \
  -e ALLOW_EMPTY_PASSWORD=yes \
  niceos/redis:8.2.1
```

👉 Runs Redis without a password. Use **only** for local testing.

---

### 🔐 Recommended way (with password & persistent volume)

```bash
docker run -d \
  --name redis \
  -e REDIS_PASSWORD=supersecret \
  -v /my/redis-data:/app/data \
  niceos/redis:8.2.1
```

👉 Starts Redis with authentication enabled and data persisted in `/my/redis-data`.

---

### 🩺 Healthcheck example

The image ships with a built-in `HEALTHCHECK`. You can verify it manually:

```bash
docker exec redis \
  /usr/bin/redis-cli -a supersecret ping
```

Expected response:

```
PONG
```

For TLS deployments, use:

```bash
docker exec redis \
  /usr/bin/redis-cli --tls --cert /path/redis.crt --key /path/redis.key --cacert /path/ca.crt ping
```

## 4. Getting the Image 🐳

There are multiple ways to obtain the NiceOS Redis image, depending on your workflow.

### 📥 Pull from registry

Always use a versioned tag for reproducibility:

```bash
docker pull niceos/redis:8.2.1
```

👉 This ensures you always get the same Redis version, not a moving `latest`.

### 🛠 Use with Docker Compose

Define Redis as a service in your `docker-compose.yml`:

```yaml
version: "3.9"

services:
  redis:
    image: niceos/redis:8.2.1
    container_name: redis
    restart: unless-stopped
    environment:
      - REDIS_PASSWORD=supersecret
    volumes:
      - ./redis-data:/app/data
    ports:
      - "6379:6379"
```

Then start everything with:

```bash
docker-compose up -d
```

Your app can now connect to Redis at `localhost:6379` with the configured password.

## 5. Environment Variables

Below is the complete, grouped catalog of variables recognized by the NiceOS Redis image.
Conventions used:

* **Type/values** show expected kinds (boolean: `yes|no`, integer, path, string).
* **`*_FILE`**: if shown in **Notes**, the variable also supports a file-based twin (e.g., `REDIS_PASSWORD_FILE`). When present, the file’s contents override the plain env var.
* **Compat** flags variables that exist for Bitnami compatibility; prefer the NiceOS-native one where noted.
* **Default** is the effective default inside this image unless you override it.

---

### A) Base paths & process layout

| Name                               | Type / Values |                         Default | Notes                                                 |                                                               |
| ---------------------------------- | ------------- | ------------------------------: | ----------------------------------------------------- | ------------------------------------------------------------- |
| `REDIS_BASE_DIR`                   | path          |                          `/app` | Base application dir.                                 |                                                               |
| `REDIS_BIN_DIR`                    | path          |                      `/usr/bin` | Added to `PATH`.                                      |                                                               |
| `PATH`                             | path-list     |                          system | Includes `${REDIS_BIN_DIR}`.                          |                                                               |
| `REDIS_CONF_DIR`                   | path          |         `${REDIS_BASE_DIR}/etc` | —                                                     |                                                               |
| `REDIS_DEFAULT_CONF_DIR`           | path          | `${REDIS_BASE_DIR}/etc.default` | Seeds defaults on first run (idempotent).             |                                                               |
| `REDIS_MOUNTED_CONF_DIR`           | path          | `${REDIS_BASE_DIR}/mounted-etc` | Where you can mount `redis.conf` or `overrides.conf`. |                                                               |
| `REDIS_DATA_DIR`                   | path          |        `${REDIS_BASE_DIR}/data` | Persistent data dir.                                  |                                                               |
| `REDIS_LOG_DIR`                    | path          |        `${REDIS_BASE_DIR}/logs` | Log directory (also logs go to stdout).               |                                                               |
| `REDIS_TMP_DIR`                    | path          |         `${REDIS_BASE_DIR}/run` | PID and runtime files.                                |                                                               |
| `REDIS_CONF_FILE`                  | path          |  `${REDIS_CONF_DIR}/redis.conf` | Active config file.                                   |                                                               |
| `REDIS_LOG_FILE`                   | path          |    `${REDIS_LOG_DIR}/redis.log` | Empty string logs to stdout; can be overridden.       |                                                               |
| `REDIS_PID_FILE`                   | path          |    `${REDIS_TMP_DIR}/redis.pid` | Used by helpers & `run-redis.sh`.                     |                                                               |
| `REDIS_DAEMON_USER`                | user          |                           `app` | Non-root execution.                                   |                                                               |
| `REDIS_DAEMON_GROUP`               | group         |                           `app` | —                                                     |                                                               |
| `NICEOS_REDIS_CONF_GROUP_WRITABLE` | boolean `yes  |                             no` | `no`                                                  | If `yes`, setup makes `redis.conf` group-writable.            |
| `NICEOS_REDIS_RUN_SETUP`           | boolean `yes  |                             no` | `no`                                                  | Force running setup-tuning before start (NiceOS-only).        |
| `NICEOS_MODULE`                    | string        |                         `redis` | Tag for NiceOS logging.                               |                                                               |
| `NICEOS_DEBUG`                     | boolean `true |                          false` | `false`                                               | Enables verbose logging in NiceOS libs.                       |
| `BITNAMI_DEBUG`                    | boolean `true |                          false` | —                                                     | **Compat:** mapped to `NICEOS_DEBUG` (prefer `NICEOS_DEBUG`). |

---

### B) Auth, passwords & ACL

| Name                     | Type / Values   |   Default | Notes                                                                   |                     |
| ------------------------ | --------------- | --------: | ----------------------------------------------------------------------- | ------------------- |
| `ALLOW_EMPTY_PASSWORD`   | boolean `yes    |       no` | `no`                                                                    | `yes` only for dev. |
| `REDIS_PASSWORD`         | string          | *(empty)* | **`*_FILE` supported:** `REDIS_PASSWORD_FILE`. Sets `requirepass`.      |                     |
| `REDIS_MASTER_PASSWORD`  | string          | *(empty)* | **`*_FILE` supported:** `REDIS_MASTER_PASSWORD_FILE`. Used by replicas. |                     |
| `REDIS_ACLFILE`          | path            | *(empty)* | **`*_FILE` supported.** Enables ACL (Redis ≥6).                         |                     |
| `REDIS_DISABLE_COMMANDS` | CSV of commands | *(empty)* | **`*_FILE` supported.** E.g. `FLUSHALL,FLUSHDB,CONFIG`.                 |                     |

---

### C) Persistence (AOF / RDB)

| Name                        | Type / Values |                                    Default | Notes                                                        |                                |
| --------------------------- | ------------- | -----------------------------------------: | ------------------------------------------------------------ | ------------------------------ |
| `REDIS_AOF_ENABLED`         | boolean `yes  |                                        no` | `yes`                                                        | Turns on AOF.                  |
| `REDIS_RDB_POLICY`          | string        |                                  *(empty)* | Space-separated `sec#times` rules, e.g. `900#1 300#10`.      |                                |
| `REDIS_RDB_POLICY_DISABLED` | boolean `yes  |                                        no` | `no`                                                         | If `yes`, disables RDB `save`. |
| `REDIS_OVERRIDES_FILE`      | path          | `${REDIS_MOUNTED_CONF_DIR}/overrides.conf` | **`*_FILE` supported.** Appended via `include` (idempotent). |                                |

> All four above support `*_FILE` where listed in the header loader; when present, the file’s contents win.

---

### D) Networking & replication

| Name                             | Type / Values |                        Default | Notes                                                             |                                                                   |                                                |
| -------------------------------- | ------------- | -----------------------------: | ----------------------------------------------------------------- | ----------------------------------------------------------------- | ---------------------------------------------- |
| `REDIS_DEFAULT_PORT_NUMBER`      | int           |                         `6379` | Build-time default.                                               |                                                                   |                                                |
| `REDIS_PORT_NUMBER`              | int           | `${REDIS_DEFAULT_PORT_NUMBER}` | Non-TLS port (0 to disable when TLS-only).                        |                                                                   |                                                |
| `REDIS_ALLOW_REMOTE_CONNECTIONS` | boolean `yes  |                            no` | `yes`                                                             | If `yes`, `bind 0.0.0.0 ::` is applied by setup when appropriate. |                                                |
| `REDIS_REPLICATION_MODE`         | `master       |                        replica | slave`                                                            | *(empty)*                                                         | `slave` kept for **compat**, prefer `replica`. |
| `REDIS_MASTER_HOST`              | host          |                      *(empty)* | Required on replica. **`*_FILE` supported.**                      |                                                                   |                                                |
| `REDIS_MASTER_PORT_NUMBER`       | int           |                         `6379` | **`*_FILE` supported.**                                           |                                                                   |                                                |
| `REDIS_REPLICA_IP`               | IP            |                      *(empty)* | Announce IP; if empty, auto-detected.                             |                                                                   |                                                |
| `REDIS_REPLICA_PORT`             | int           |                      *(empty)* | Announce port; defaults to master port if empty.                  |                                                                   |                                                |
| `REDIS_EXTRA_FLAGS`              | argv string   |                      *(empty)* | Extra `redis-server` flags; highest precedence in `run-redis.sh`. |                                                                   |                                                |

> `*_FILE` is supported for `REDIS_MASTER_HOST` and `REDIS_MASTER_PORT_NUMBER` via the central loader.

---

### E) TLS (encryption)

| Name                       | Type / Values |   Default | Notes                                                 |                                      |                     |
| -------------------------- | ------------- | --------: | ----------------------------------------------------- | ------------------------------------ | ------------------- |
| `REDIS_TLS_ENABLED`        | boolean `yes  |       no` | `no`                                                  | Enables TLS listeners & replication. |                     |
| `REDIS_TLS_PORT_NUMBER`    | int           |    `6379` | TLS port (set non-`0` when using dual-stack).         |                                      |                     |
| `REDIS_TLS_PORT`           | int           |         — | **Compat alias** for `REDIS_TLS_PORT_NUMBER`.         |                                      |                     |
| `REDIS_TLS_CERT_FILE`      | path          | *(empty)* | **`*_FILE` supported.** Required when TLS is enabled. |                                      |                     |
| `REDIS_TLS_KEY_FILE`       | path          | *(empty)* | **`*_FILE` supported.** Required when TLS is enabled. |                                      |                     |
| `REDIS_TLS_KEY_FILE_PASS`  | string        | *(empty)* | **`*_FILE` supported.** Optional key passphrase.      |                                      |                     |
| `REDIS_TLS_CA_FILE`        | path          | *(empty)* | **`*_FILE` supported.** Preferred over dir.           |                                      |                     |
| `REDIS_TLS_CA_DIR`         | path          | *(empty)* | **`*_FILE` supported.** Used if `CA_FILE` not set.    |                                      |                     |
| `REDIS_TLS_DH_PARAMS_FILE` | path          | *(empty)* | **`*_FILE` supported.** Optional.                     |                                      |                     |
| `REDIS_TLS_AUTH_CLIENTS`   | `yes          |        no | optional`                                             | `yes`                                | Client auth policy. |

TLS validation happens during setup; missing/invalid files cause a clear error before Redis starts.

---

### F) Sentinel (optional auto-discovery for replicas)

| Name                         | Type / Values |   Default | Notes                 |
| ---------------------------- | ------------- | --------: | --------------------- |
| `REDIS_SENTINEL_MASTER_NAME` | string        | *(empty)* | Sentinel master name. |
| `REDIS_SENTINEL_HOST`        | host          | *(empty)* | Sentinel address.     |
| `REDIS_SENTINEL_PORT_NUMBER` | int           |   `26379` | Sentinel port.        |

When Sentinel variables are set on a replica, the image queries Sentinel to discover the active master and configures `replicaof` accordingly.

---

### G) Performance tuning

| Name                        | Type / Values |   Default | Notes                              |                                          |
| --------------------------- | ------------- | --------: | ---------------------------------- | ---------------------------------------- |
| `REDIS_IO_THREADS`          | int           | *(empty)* | Enables Redis IO threads when set. |                                          |
| `REDIS_IO_THREADS_DO_READS` | `yes          |       no` | *(empty)*                          | Enables multi-threaded reads when `yes`. |

---

### H) Localization & locale

| Name     | Type / Values |       Default | Notes                                                        |
| -------- | ------------- | ------------: | ------------------------------------------------------------ |
| `LANG`   | locale        | `en_US.UTF-8` | If `ru_RU.UTF-8`, NiceOS helpers switch to Russian messages. |
| `LC_ALL` | locale        | `en_US.UTF-8` | —                                                            |

---

### I) File-backed secret variants (`*_FILE`)

The loader in this image supports file-backed alternatives for **every** variable listed in this array:
`REDIS_DATA_DIR`, `REDIS_OVERRIDES_FILE`, `REDIS_DISABLE_COMMANDS`, `REDIS_DATABASE`, `REDIS_AOF_ENABLED`, `REDIS_RDB_POLICY`, `REDIS_RDB_POLICY_DISABLED`, `REDIS_MASTER_HOST`, `REDIS_MASTER_PORT_NUMBER`, `REDIS_PORT_NUMBER`, `REDIS_ALLOW_REMOTE_CONNECTIONS`, `REDIS_REPLICATION_MODE`, `REDIS_REPLICA_IP`, `REDIS_REPLICA_PORT`, `REDIS_EXTRA_FLAGS`, `ALLOW_EMPTY_PASSWORD`, `REDIS_PASSWORD`, `REDIS_MASTER_PASSWORD`, `REDIS_ACLFILE`, `REDIS_IO_THREADS_DO_READS`, `REDIS_IO_THREADS`, `REDIS_TLS_ENABLED`, `REDIS_TLS_PORT_NUMBER`, `REDIS_TLS_CERT_FILE`, `REDIS_TLS_CA_DIR`, `REDIS_TLS_KEY_FILE`, `REDIS_TLS_KEY_FILE_PASS`, `REDIS_TLS_CA_FILE`, `REDIS_TLS_DH_PARAMS_FILE`, `REDIS_TLS_AUTH_CLIENTS`, `REDIS_SENTINEL_MASTER_NAME`, `REDIS_SENTINEL_HOST`, `REDIS_SENTINEL_PORT_NUMBER`, `REDIS_TLS_PORT`.
For each of the above, setting `NAME_FILE=/run/secret` makes the image read the value from that file and ignore the plain `NAME` if both are present.

---

### J) Compatibility & deprecation notes

* `REDIS_REPLICATION_MODE=slave` is accepted for **Bitnami compatibility**; prefer `replica`.
* `REDIS_TLS_PORT` is accepted for **compatibility**; prefer `REDIS_TLS_PORT_NUMBER`.
* `BITNAMI_DEBUG` is accepted for **compatibility**; prefer `NICEOS_DEBUG`.

---

### K) Notable defaults the image enforces

* Foreground execution: `--daemonize no` (PID 1-friendly).
* Idempotent defaults: copy templates without overwriting user files.
* Safe logging: structured logs; do not echo secrets.
* Non-root runtime: UID:GID `10001:10001` with directory checks/fixes during setup.

## 6. Secrets & Security 🔐

NiceOS Redis is designed with security as a first-class concern. While you can spin up a quick development container without a password, production deployments should always apply secure defaults.

---

### 📄 File-based secrets (`*_FILE` support)

Every sensitive environment variable supports a `*_FILE` counterpart.
Instead of:

```bash
-e REDIS_PASSWORD=supersecret
```

you can mount a Docker secret or Kubernetes Secret:

```bash
-e REDIS_PASSWORD_FILE=/run/secrets/redis_pass
```

👉 This prevents your password from leaking into `docker inspect`, logs, or process arguments.

---

### ⚠️ `ALLOW_EMPTY_PASSWORD` is for development only

You can bypass password enforcement by setting:

```bash
-e ALLOW_EMPTY_PASSWORD=yes
```

This is acceptable in quick demos or local tests, but **extremely unsafe** in production. In production, always provide `REDIS_PASSWORD` or `REDIS_PASSWORD_FILE`.

---

### 🗝 Access control: ACL & disabling commands

* **ACL:** You can provide an `ACLFILE` to define fine-grained users, commands, and key patterns:

  ```bash
  -e REDIS_ACLFILE=/app/mounted-etc/users.acl
  -v ./users.acl:/app/mounted-etc/users.acl
  ```
* **Disabled commands:** By default, unsafe commands such as `FLUSHALL`, `FLUSHDB`, `CONFIG`, `DEBUG`, `SHUTDOWN`, and `CLUSTER` are disabled during setup unless you explicitly override `REDIS_DISABLE_COMMANDS`.
  This prevents accidents like flushing production databases.

---

### 👤 Non-root execution and directory ownership

Redis runs as user `app` (UID 10001) by default.

* All runtime directories (`/app/data`, `/app/logs`, `/app/run`) are created if missing and ownership is fixed automatically.
* The container never requires root privileges at runtime, which lowers the attack surface.

---

### 🔐 TLS for encrypted traffic

Redis traffic can be encrypted end-to-end. Enable TLS with:

```bash
-e REDIS_TLS_ENABLED=yes \
-e REDIS_TLS_CERT_FILE=/app/certs/redis.crt \
-e REDIS_TLS_KEY_FILE=/app/certs/redis.key \
-e REDIS_TLS_CA_FILE=/app/certs/ca.crt \
-v ./certs:/app/certs
```

* The container validates that certs, keys, and CA files exist before starting.
* You can configure client auth (`REDIS_TLS_AUTH_CLIENTS=yes`) for mutual TLS.

---

### 🌐 Secure replication with master-auth

When running replicas, use `REDIS_MASTER_PASSWORD` to authenticate against the master:

```bash
# Master
docker run -d --name redis-master \
  -e REDIS_REPLICATION_MODE=master \
  -e REDIS_PASSWORD=masterpass \
  niceos/redis:8.2

# Replica
docker run -d --name redis-replica \
  -e REDIS_REPLICATION_MODE=replica \
  -e REDIS_MASTER_HOST=redis-master \
  -e REDIS_MASTER_PORT_NUMBER=6379 \
  -e REDIS_MASTER_PASSWORD=masterpass \
  -e REDIS_PASSWORD=replicapass \
  niceos/redis:8.2
```

👉 Replicas will refuse to start if `REDIS_MASTER_PASSWORD` is missing (unless `ALLOW_EMPTY_PASSWORD=yes` is set for development).

---

**Summary:**
With file-backed secrets, strict defaults, disabled unsafe commands, enforced non-root execution, TLS validation, and authenticated replication, the NiceOS Redis image is built to be **production-safe out of the box**.

## 7. Configuration ⚙️

The NiceOS Redis image offers multiple, predictable ways to configure Redis, from mounting your own `redis.conf` to using lightweight overrides. All approaches are **idempotent**: the same input always produces the same result.

---

### 📂 Using your own `redis.conf` (mounted-etc)

If you mount a full `redis.conf` into the container at:

```
/app/mounted-etc/redis.conf
```

the setup logic will copy it into place and skip auto-tuning.
Example:

```bash
-v ./redis.conf:/app/mounted-etc/redis.conf
```

👉 In this mode, the image treats your config as authoritative and does not generate or patch defaults.

---

### 📝 Using `overrides.conf`

If you only want to override a few settings, mount a file at:

```
/app/mounted-etc/overrides.conf
```

The entrypoint ensures that this file is **included at the end** of the active `redis.conf` via an `include` directive.
This lets you apply small adjustments (like changing memory limits or maxclients) without maintaining a full config file.

---

### 💾 Persistence (AOF and RDB)

* **AOF (Append Only File)** is enabled by default (`REDIS_AOF_ENABLED=yes`). It fsyncs every second (`appendfsync everysec`) for a safe performance balance.
* **RDB snapshots** are disabled by default in the setup flow (`save ""`). You can re-enable them by:

  ```bash
  -e REDIS_RDB_POLICY="900#1 300#10"
  -e REDIS_RDB_POLICY_DISABLED=no
  ```

  which produces lines like:

  ```
  save 900 1
  save 300 10
  ```

---

### 📦 Idempotent defaults copying

On startup, the entrypoint copies files from:

```
/app/etc.default/ → /app/etc/
```

using `rsync --ignore-existing` or `cp -rnp`.

* Existing files are **never overwritten**.
* If no `redis.conf` exists, one is seeded from `/app/etc.default/redis.conf` or, as a last resort, from `/etc/redis.conf`.
  This guarantees that a working config is always present, but your changes are preserved.

---

### 🔧 Behavior of the setup script (`setup-redis.sh`)

The setup phase is optional and runs when explicitly requested (`NICEOS_REDIS_RUN_SETUP=yes` or legacy run path). It:

* Validates environment variables (passwords, TLS, ports).
* Creates and fixes ownership of data/log/tmp directories.
* Ensures `redis.conf` is readable and group-safe (if configured).
* Applies **Bitnami-style tuning** idempotently to the existing `redis.conf`:

  * disables unsafe commands (e.g., `FLUSHALL`),
  * configures AOF and persistence policy,
  * sets password and ACL,
  * enables TLS if requested,
  * applies replication and Sentinel settings.

What it **does not do**:

* It never blindly regenerates `redis.conf` from scratch.
* It does not overwrite a mounted user config.
* It does not enable insecure defaults automatically (only if you explicitly set them).

---

✅ Result: the configuration layer in NiceOS Redis is **transparent, reproducible, and safe**—whether you prefer to bring your own config, override a few lines, or rely on environment-driven tuning.


## 8. Running & Management 🚦

The lifecycle of the container is split into clear phases:

---

### 🛠 Entrypoint → Setup

* The container always starts with `entrypoint.sh`.
* The entrypoint decides whether to run the **setup script**:

  * Runs automatically if `NICEOS_REDIS_RUN_SETUP=yes` (default in this image).
  * Also runs for legacy paths (`/run.sh`, Bitnami compatibility).
* `setup-redis.sh` validates env vars, applies defaults, fixes permissions, and tunes `redis.conf` idempotently.

---

### 🚀 Run script (`run-redis.sh`)

The actual Redis process is launched by `run-redis.sh`, which guarantees:

* **Foreground execution**: `--daemonize no` is always enforced for clean PID 1 behavior.
* **Pidfile safety**: generates a pidfile only if the directory is writable; otherwise, runs without.
* **Logfile control**: defaults to stdout (`--logfile ""`) unless you override it.
* **Extra args respected**: appends `REDIS_EXTRA_FLAGS` and any user arguments.

---

### 📦 Examples

**Standalone (no persistence, dev mode):**

```bash
docker run --rm -it \
  --name redis-dev \
  -e ALLOW_EMPTY_PASSWORD=yes \
  niceos/redis:8.2
```

**With persistent data volume:**

```bash
docker run -d \
  --name redis \
  -e REDIS_PASSWORD=supersecret \
  -v ./redis-data:/app/data \
  niceos/redis:8.2
```

**With additional flags (`REDIS_EXTRA_FLAGS`):**

```bash
docker run -d \
  --name redis \
  -e REDIS_PASSWORD=supersecret \
  -e REDIS_EXTRA_FLAGS="--maxmemory 256mb --maxmemory-policy allkeys-lru" \
  niceos/redis:8.2
```

👉 Flags are merged at the end, so they override defaults where supported.

---

### 👤 Non-root execution

Redis is always launched as user **UID:GID 10001:10001** (`app:app`).

* No root privileges are needed at runtime.
* Ownership of `/app/data`, `/app/logs`, and `/app/run` is adjusted during setup.
* If you mount volumes, ensure they are writable by UID 10001.

---

✅ With this design, you get predictable startup, secure defaults, and full control over Redis arguments without breaking container best practices.


## 9. Replication & Sentinel 🔄

Redis replication is supported out of the box in the NiceOS image. Configuration is environment-driven, with safe defaults and validation at startup.

---

### ⚙️ Relevant environment variables

* **Replication role**

  * `REDIS_REPLICATION_MODE=master|replica|slave`
  * `slave` is accepted for compatibility, but `replica` is preferred.

* **Master configuration**

  * `REDIS_PASSWORD` → master auth password (replicas will use it as `masterauth`).
  * `REDIS_PORT_NUMBER` → port of the master (default: 6379).

* **Replica configuration**

  * `REDIS_MASTER_HOST` → hostname/IP of the master.
  * `REDIS_MASTER_PORT_NUMBER` → master port (default: 6379).
  * `REDIS_MASTER_PASSWORD` → password used by replicas to authenticate with the master.
  * `REDIS_PASSWORD` → password replicas themselves require for clients.
  * `REDIS_REPLICA_IP` / `REDIS_REPLICA_PORT` → optional announce IP/port.

* **Sentinel discovery**

  * `REDIS_SENTINEL_HOST` → Sentinel node to query.
  * `REDIS_SENTINEL_PORT_NUMBER` → Sentinel port (default: 26379).
  * `REDIS_SENTINEL_MASTER_NAME` → logical master name known to Sentinel.

---

### 📌 Master + Replica example

**Master node:**

```bash
docker run -d --name redis-master \
  -e REDIS_REPLICATION_MODE=master \
  -e REDIS_PASSWORD=masterpass \
  niceos/redis:8.2
```

**Replica node:**

```bash
docker run -d --name redis-replica \
  --link redis-master:master \
  -e REDIS_REPLICATION_MODE=replica \
  -e REDIS_MASTER_HOST=master \
  -e REDIS_MASTER_PORT_NUMBER=6379 \
  -e REDIS_MASTER_PASSWORD=masterpass \
  -e REDIS_PASSWORD=replicapass \
  niceos/redis:8.2
```

👉 The replica will wait until the master port is reachable, then configure `replicaof` with the correct credentials.

---

### 🔎 Sentinel auto-discovery

Instead of hardcoding the master, you can let replicas discover it dynamically via Sentinel:

```bash
docker run -d --name redis-replica \
  -e REDIS_REPLICATION_MODE=replica \
  -e REDIS_SENTINEL_HOST=sentinel-node \
  -e REDIS_SENTINEL_PORT_NUMBER=26379 \
  -e REDIS_SENTINEL_MASTER_NAME=mymaster \
  -e REDIS_MASTER_PASSWORD=masterpass \
  niceos/redis:8.2
```

* The container queries Sentinel with:

  ```
  redis-cli -h $REDIS_SENTINEL_HOST -p $REDIS_SENTINEL_PORT_NUMBER \
    sentinel get-master-addr-by-name $REDIS_SENTINEL_MASTER_NAME
  ```
* It then updates `REDIS_MASTER_HOST` and `REDIS_MASTER_PORT_NUMBER` automatically before starting.

---

### ⏳ Why `wait-for-port` matters

Replication setup calls a helper (`wait-for-port`) to ensure that the master is **reachable** before starting the replica.

* Without it, Redis might start with a broken replication config and fail silently.
* With it, the container retries until the master port accepts TCP connections, ensuring reliable bootstrap in clustered environments.

---

✅ With these mechanics, you can scale a Redis master-replica cluster easily, add Sentinel for auto-discovery, and rely on built-in safety checks for predictable startup.


## 10. Persistence 💾

Redis supports two main persistence models. The NiceOS image exposes both with sane defaults and clear knobs.

---

### 🔄 AOF vs RDB

* **AOF (Append Only File)**

  * Enabled by default (`REDIS_AOF_ENABLED=yes`).
  * Logs every write operation and replays them on restart.
  * Safer for durability; fsync every second (`appendfsync everysec`) is the default balance of speed and safety.

* **RDB (point-in-time snapshots)**

  * Disabled by default (`save ""`) to avoid surprises.
  * Can be re-enabled with:

    ```bash
    -e REDIS_RDB_POLICY_DISABLED=no
    -e REDIS_RDB_POLICY="900#1 300#10"
    ```

    which produces:

    ```
    save 900 1
    save 300 10
    ```
  * More compact but less durable than AOF.

👉 You can use both together for redundancy: AOF for durability, RDB for faster restarts.

---

### 📂 Mounting a volume

Data lives under:

```
/app/data
```

Mount this to a persistent location:

```bash
docker run -d \
  -e REDIS_PASSWORD=supersecret \
  -v ./redis-data:/app/data \
  niceos/redis:8.2
```

Without a volume, all data disappears when the container is removed.

---

### 🗑 What happens on container removal

* **With no volume:** data is ephemeral and is lost once the container is deleted.
* **With a volume:** `/app/data` is preserved on the host and reused across container restarts or upgrades.

---

### 🛡 Backup & restore

**Backup with rsync (safe for live volumes):**

```bash
rsync -a ./redis-data ./redis-backup.$(date +%Y%m%d-%H%M%S)
```

**Restore:**

```bash
docker run -d \
  -e REDIS_PASSWORD=supersecret \
  -v ./redis-backup.20251002:/app/data \
  niceos/redis:8.2
```

**Snapshot strategy:**

* For local/dev: simple rsync is enough.
* For production: use filesystem snapshots (e.g. LVM, ZFS, btrfs) on the host. These capture a consistent point-in-time view of the volume with minimal downtime.

---

✅ Persistence in NiceOS Redis is transparent: you choose AOF or RDB (or both), mount a volume, and backups are just file copies or snapshots.


## 11. Healthcheck & Monitoring 🩺📊

The NiceOS Redis image ships with a built-in healthcheck and is designed to integrate cleanly with monitoring stacks.

---

### ✅ Built-in healthcheck

* Every container has a `HEALTHCHECK` directive baked in.
* By default, it runs:

  ```bash
  redis-cli -h 127.0.0.1 -p 6379 ping
  ```

  and expects `PONG`.
* If `REDIS_PASSWORD` is set, authentication is added automatically (`-a $REDIS_PASSWORD`).
* Exit code `0` means healthy, any non-zero is unhealthy.

👉 This makes orchestration tools (Docker, Kubernetes) aware of Redis liveness.

---

### 📡 Monitoring recommendations

For production, liveness is not enough. Add observability:

* **Prometheus Exporter**

  * Deploy [`redis_exporter`](https://github.com/oliver006/redis_exporter) sidecar or standalone.
  * Exposes Redis metrics (`connected_clients`, `used_memory`, `instantaneous_ops_per_sec`, etc.) to Prometheus/Grafana.
* **Logging integration**

  * Container logs are already JSON-capable, which makes them ingestible by ELK / Loki without parsing hacks.
* **Alerting**

  * Add alerts for high memory usage, replication lag, and unresponsive replicas.

---

### 🔐 TLS-aware healthcheck

If you run Redis with TLS enabled, you can test health manually (or override the built-in healthcheck) with:

```bash
docker exec redis \
  /usr/bin/redis-cli \
    --tls \
    --cert /app/certs/redis.crt \
    --key /app/certs/redis.key \
    --cacert /app/certs/ca.crt \
    ping
```

Expected output:

```
PONG
```

---

✅ With the built-in healthcheck, optional TLS probing, and integration with Prometheus exporters, the NiceOS Redis image is ready for both **container orchestration liveness** and **enterprise-grade monitoring**.


## 12. Logging 📝

Logging in the NiceOS Redis image is designed to be **human-friendly by default** and **machine-friendly when needed**.

---

### 📤 stdout vs `redis.log`

* By default, Redis logs go to **stdout** (`--logfile ""`). This keeps logs visible via `docker logs` and integrates with orchestration systems.
* You can also redirect logs to a file with:

  ```bash
  -e REDIS_LOG_FILE=/app/logs/redis.log
  ```
* Both methods can coexist: NiceOS helper libraries (`liblog.sh`) always send their own logs to stdout (structured).

---

### 📄 Log formats

* **plain** → human-readable text.
* **json** → structured JSON for log processors (ELK, Loki, Fluentd).
* **both** → emit plain + JSON simultaneously.

Configured via NiceOS logging environment variables (`NICEOS_LOG_FORMAT`).

---

### 🖋 Example logs

**Plain format (default):**

```
2025-10-02 12:45:30 [INFO] (redis) 🚀 Starting NiceOS Redis entrypoint
2025-10-02 12:45:31 [INFO] (redis) Paths: BASE=/app, CONF_DIR=/app/etc
2025-10-02 12:45:32 [WARN] (redis) ALLOW_EMPTY_PASSWORD=yes — unsafe in production
2025-10-02 12:45:33 [INFO] (redis) Redis: Redis server v=8.2.1 sha=00000000
```

**JSON format:**

```json
{
  "ts": "2025-10-02T12:45:30.452Z",
  "level": "INFO",
  "module": "redis",
  "pid": 1,
  "msg": "🚀 Starting NiceOS Redis entrypoint"
}
```

---

### 🎨 Colors, PID, module

* **Colors:** enabled automatically when stdout is a TTY (can be forced with `NICEOS_FORCE_COLOR=true`).
* **PID display:** optional (`NICEOS_LOG_SHOW_PID=true`), useful for multi-process debugging.
* **Module tags:** each library sets `NICEOS_MODULE` (e.g. `redis`, `libos`, `libnet`) so logs are clearly attributed.

---

✅ Result: whether you tail logs interactively or ship them to a log collector, you always get **clear, structured, and consistent output**.


## 14. Upgrades & Migration ⛵️

Keeping Redis current is straightforward with the NiceOS image. Follow these steps to upgrade safely while preserving data.

---

### 🔁 Standard upgrade flow (pull → stop → rm → run)

**Docker CLI**

```bash
# 1) Pull the new image (pin a specific tag!)
docker pull niceos/redis:8.2.1

# 2) Stop the old container (data is on a volume, so it's safe)
docker stop redis

# 3) Remove the old container (keeps the volume intact)
docker rm redis

# 4) Run the new version, reusing the same volume
docker run -d --name redis \
  -e REDIS_PASSWORD=supersecret \
  -v ./redis-data:/app/data \
  niceos/redis:8.2.1
```

**Docker Compose**

```bash
# 1) Edit docker-compose.yml → set image: niceos/redis:8.2.1
# 2) Pull the new image
docker compose pull redis
# 3) Recreate with no data loss (volumes are preserved)
docker compose up -d redis
```

---

### 💾 Preserve data with a volume

All runtime data lives in `/app/data`. As long as you mount it to a persistent host path or named volume, the dataset survives container replacement:

```bash
-v ./redis-data:/app/data
# or
-v redis_data:/app/data
```

Without a mounted volume, data is **ephemeral** and will be lost on container removal.

---

### 🧰 Pre-upgrade backup (recommended)

Create a quick snapshot before upgrading:

```bash
# If using a host bind mount
rsync -a ./redis-data ./redis-backup.$(date +%Y%m%d-%H%M%S)

# If using a named volume, temporarily mount it:
docker run --rm -v redis_data:/from -v "$(pwd)":/to alpine \
  sh -c 'apk add --no-cache rsync >/dev/null && rsync -a /from/ /to/redis-backup.$(date +%Y%m%d-%H%M%S)/'
```

Restore by pointing the new container at the backup directory:

```bash
docker run -d --name redis \
  -e REDIS_PASSWORD=supersecret \
  -v ./redis-backup.20251002:/app/data \
  niceos/redis:8.2.1
```

---

### 🏷 Versioning & compatibility

* **Pin exact tags for reproducibility**
  Prefer `niceos/redis:8.2.1` over `latest`. Pinning avoids surprise upgrades.

* **Minor bumps (e.g., 8.2.1 → 8.2.1)**
  Generally safe. Config and data formats are expected to be compatible. Still back up.

* **Major bumps (e.g., 7.x → 8.x)**
  Read upstream Redis release notes for any breaking changes (persistence formats, config directives). Test with a copy of your data first.

* **`latest` tag**
  Convenient for dev, not recommended for production. It can move unexpectedly.

* **Rolling restart guidance**
  In replicated setups, upgrade replicas first, then the master to minimize downtime. With Sentinel, ensure quorum and failover policies are healthy before upgrading the master.

---

### ✅ Post-upgrade checks

* Health:

  ```bash
  docker inspect --format='{{.State.Health.Status}}' redis
  ```
* Connectivity:

  ```bash
  docker exec redis /usr/bin/redis-cli -a supersecret ping
  ```
* Persistence status (AOF/RDB) and memory:

  ```bash
  docker exec redis /usr/bin/redis-cli -a supersecret info persistence
  docker exec redis /usr/bin/redis-cli -a supersecret info memory
  ```

---

**Summary:** Pin a version, keep `/app/data` on a volume, back up before upgrades, and recreate the container with the new tag. Test major-version jumps in staging.


## 15. Docker Compose Examples 🐙

Here are ready-to-use Compose snippets showing different Redis deployment scenarios with the NiceOS image.

---

### 🟢 Simple standalone (ephemeral, dev)

```yaml
version: "3.9"

services:
  redis:
    image: niceos/redis:8.2.1
    container_name: redis
    environment:
      - ALLOW_EMPTY_PASSWORD=yes
    ports:
      - "6379:6379"
```

👉 Runs Redis without a password (development only). Data is lost when the container stops.

---

### 💾 Standalone with persistent volume

```yaml
version: "3.9"

services:
  redis:
    image: niceos/redis:8.2.1
    container_name: redis
    restart: unless-stopped
    environment:
      - REDIS_PASSWORD=supersecret
    volumes:
      - ./redis-data:/app/data
    ports:
      - "6379:6379"
```

👉 Data is stored in `./redis-data` and persists across restarts or upgrades.

---

### 🔄 Master + Replica cluster

```yaml
version: "3.9"

services:
  redis-master:
    image: niceos/redis:8.2.1
    container_name: redis-master
    restart: unless-stopped
    environment:
      - REDIS_REPLICATION_MODE=master
      - REDIS_PASSWORD=masterpass
    volumes:
      - ./redis-master-data:/app/data
    ports:
      - "6379:6379"

  redis-replica:
    image: niceos/redis:8.2.1
    container_name: redis-replica
    restart: unless-stopped
    depends_on:
      - redis-master
    environment:
      - REDIS_REPLICATION_MODE=replica
      - REDIS_MASTER_HOST=redis-master
      - REDIS_MASTER_PORT_NUMBER=6379
      - REDIS_MASTER_PASSWORD=masterpass
      - REDIS_PASSWORD=replicapass
    volumes:
      - ./redis-replica-data:/app/data
    ports:
      - "6380:6379"
```

👉 The replica automatically connects to the master, authenticates, and syncs.

---

### 📡 Sentinel + Master + Replica

```yaml
version: "3.9"

services:
  redis-master:
    image: niceos/redis:8.2.1
    container_name: redis-master
    environment:
      - REDIS_REPLICATION_MODE=master
      - REDIS_PASSWORD=masterpass
    ports:
      - "6379:6379"

  redis-replica:
    image: niceos/redis:8.2.1
    container_name: redis-replica
    depends_on:
      - redis-master
      - redis-sentinel
    environment:
      - REDIS_REPLICATION_MODE=replica
      - REDIS_SENTINEL_HOST=redis-sentinel
      - REDIS_SENTINEL_PORT_NUMBER=26379
      - REDIS_SENTINEL_MASTER_NAME=mymaster
      - REDIS_MASTER_PASSWORD=masterpass
      - REDIS_PASSWORD=replicapass
    ports:
      - "6380:6379"

  redis-sentinel:
    image: bitnami/redis-sentinel:latest   # or a NiceOS sentinel variant
    container_name: redis-sentinel
    environment:
      - REDIS_MASTER_HOST=redis-master
      - REDIS_MASTER_PORT_NUMBER=6379
      - REDIS_MASTER_PASSWORD=masterpass
      - REDIS_SENTINEL_MASTER_NAME=mymaster
    ports:
      - "26379:26379"
```

👉 Sentinel watches the master. Replicas query Sentinel for the active master and reconfigure automatically if failover occurs.

---

✅ With these Compose templates you can cover the full spectrum: **dev playground, persistent production instance, high-availability with replicas, and Sentinel for automatic failover.**

