# 🐧 NiceSOFT — Container-first Linux & Secure Images

**NiceSOFT** builds a **container-first Linux distribution (NiceOS)** and a catalog of **secure, reproducible container images** for modern DevOps, Kubernetes and cloud-native workloads.

Our mission: **reduce supply-chain risk** and make container images **transparent, minimal, non-root by default, with SBOM and vulnerability reports inside**.

---

## 🔹 Why NiceOS?

Traditional base images (Debian, Alpine, CentOS) were never designed for containers. NiceOS flips the model:

* **Container-first base OS**
  Deterministic rootfs builds (`--reproducible`)
* **Non-root execution**
  UID/GID `10001`, compliant with Kubernetes PodSecurity
* **SBOM + CVE scans inside the image**
  `/nicesoft/niceos/reports/<release>-<build>-<arch>/`
* **Minimal attack surface**
  No package manager at runtime, no SUID/SGID
* **Transparent supply chain**
  Build metadata in `/.niceos/manifest.json`

---

## 🔹 Available images

### Base OS

* [**niceos/base-os**](https://hub.docker.com/r/niceos/base-os)
  Minimal NiceOS rootfs, perfect for building deterministic application images.

### Language runtimes

* [**niceos/openjdk21**](https://hub.docker.com/r/niceos/openjdk21)
  Secure Java 21 runtime & JDK, non-root, with SBOM & vulnerability scans included.
* [**niceos/openjdk25**](https://hub.docker.com/r/niceos/openjdk25)
  Future-ready Java 25 (early access) runtime & JDK with the same guarantees.

### Application images (coming soon)

* Redis
* PostgreSQL
* NGINX
* MariaDB / MySQL
* WordPress and other popular stacks

---

## 🔹 Example usage

**Run Java 21 app:**

```bash
docker run --rm niceos/openjdk21:latest java -version
```

**Inspect reports:**

```bash
docker run --rm niceos/base-os:latest \
  ls -1 /nicesoft/niceos/reports/latest
```

**In Kubernetes (Helm values):**

```yaml
image:
  repository: niceos/openjdk21
  tag: latest
  digest: "sha256:<REAL_DIGEST>"
securityContext:
  runAsNonRoot: true
  runAsUser: 10001
```

---

## 🔹 Migration from Bitnami

Broadcom has closed free access to most Bitnami images. **NiceSOFT images** are a drop-in alternative:

* Same familiar tags (semver + `latest`)
* Digest pinning supported
* Embedded reports for compliance & audits
* Non-root defaults for Kubernetes security

---

## 🔹 Roadmap

* ✅ Base OS (`base-os`)
* ✅ OpenJDK 21, 25
* ⏳ Redis, PostgreSQL, NGINX (first wave apps)
* ⏳ MariaDB, RabbitMQ, Kafka
* ⏳ Artifact Hub integration for Helm charts
* ⏳ Multi-arch builds (amd64 + arm64)

---

## 🔹 Documentation

* [GitHub: niceos-labs/containers](https://github.com/niceos-labs/containers)
* [Docker Hub organization: niceos](https://hub.docker.com/u/niceos)
* Build tooling (`build-rootfs.sh`, `build-image.sh`) — fully open.
* Security model: every image includes **SBOM + CVE scans** + optional **strict CVE gating**.

---

## 🔹 Join & contribute

* Suggest which Bitnami alternative you need first
* Test NiceOS images in your stack
* Open issues / PRs in [GitHub](https://github.com/niceos-labs/containers)
* Spread the word: *“Bitnami is gone, but NiceSOFT is here”*

---

## 🔹 License & disclaimer

* Build scripts: Apache 2.0
* Images: upstream software under respective licenses
* **Bitnami** is a trademark of Broadcom. We are not affiliated.

---

✨ **NiceSOFT = Trustable containers. Minimal. Secure. Reproducible.**

---
