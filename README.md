# 🐧 NiceSOFT — Container-first Linux & Secure Images

[![License: GPL-3.0](https://img.shields.io/badge/license-GPLv3-blue.svg)](LICENSE)  

**NiceOS Containers** are a **free, community-driven, drop-in replacement for Bitnami images**, designed in response to the recent Broadcom changes that restricted access to Bitnami’s previously free catalog.  

We are building and maintaining container images around the clock to ensure that developers, DevOps engineers, and organizations can continue to rely on **secure, reproducible, non-root containers** without licensing barriers.  

Our mission is simple: **help everyone migrate smoothly away from Bitnami without sacrificing security, transparency, or usability.**

---

## 🚀 Why NiceOS Containers?

Bitnami was once the go-to choice for production-ready images. After Broadcom’s acquisition, access to those images became restricted, leaving countless teams searching for alternatives. **NiceOS Containers** aim to fill that gap with a focus on:

- **Container-first operating system**: Based on [NiceOS](https://nice-soft.com/), built from the ground up for containers.  
- **Non-root by default**: All images run as a non-root UID/GID (10001) to ensure compatibility with Kubernetes PodSecurity standards.  
- **Security baked in**:  
  - Built-in SBOM (Software Bill of Materials) available inside each image.  
  - CVE vulnerability scans shipped alongside images for transparency.  
- **Minimal attack surface**: No package manager, no SUID/SGID binaries in runtime layers.  
- **Reproducible builds**: Deterministic rootfs construction (`--reproducible`) makes it possible to verify integrity.  
- **Supply-chain transparency**: Build metadata, manifests, and reports are embedded directly inside every image.  
- **Always free**: Unlike the new Bitnami model, these images will remain free and community-driven.  

---

## 📦 Available Images Today

- **niceos/redis** – Secure Redis container, non-root, with SBOM and CVE reports.  
- **niceos/openjdk21** – Secure OpenJDK 21 container, non-root, with SBOM and CVE reports.  
- **niceos/openjdk25** – Early access OpenJDK 25 container with the same guarantees.  
- **niceos/base-os** – Minimal NiceOS rootfs, a clean foundation for building your own containers.  

---

## 🔜 Coming Soon (Work in Progress)

We are adding new images every day. High-priority targets include:  

- PostgreSQL  
- NGINX  
- MariaDB / MySQL  
- RabbitMQ  
- Apache Kafka  
- WordPress and popular application stacks  

If the image you need is not listed here, keep reading — we actively **take requests** and prioritize based on community demand.  

---

## 📖 Usage Examples

Pull and run OpenJDK 21:  
```bash
docker run --rm niceos/openjdk21:latest java -version
```

Check vulnerability reports inside a container:

```bash
docker run --rm niceos/base-os:latest ls -1 /nicesoft/niceos/reports/latest
```

Kubernetes deployment example:

```yaml
image:
  repository: niceos/openjdk21
  tag: latest
  digest: "<sha256:…>"

securityContext:
  runAsNonRoot: true
  runAsUser: 10001
```

---

## 🔁 Migrating from Bitnami

Many developers and organizations were blindsided by Broadcom’s decision to restrict access to Bitnami containers. NiceOS images are designed as **drop-in replacements**, meaning:

* Matching versions and tags (`semver` + `latest`)
* Fully supported by digest pinning
* Same common entrypoints and behaviors (with extra safety by default)
* Transparent SBOM and vulnerability scan reports
* Non-root containers out-of-the-box

In most cases, replacing `bitnami/...` with `niceos/...` should “just work.”

---

## 📅 Roadmap

| Status         | Image / Feature                                    |
| -------------- | -------------------------------------------------- |
| ✅ Ready        | base-os, openjdk21, openjdk25, Redis              |
| 🚧 In Progress |  PostgreSQL, NGINX                                 |
| 📝 Planned     | MariaDB, RabbitMQ, Kafka                           |
| 📌 Future      | Artifact Hub integration, Helm chart compatibility |
| 🌍 Multi-arch  | Expanding to arm64 and additional architectures    |

---

## 🙋 How to Request a New Image

We actively encourage the community to request images. The more requests we receive, the faster we can expand the catalog. Here’s how you can help:

1. Open a new [Issue on GitHub](https://github.com/niceos-labs/containers/issues).

2. Use the title format: **“Image request: <name>”**

3. Provide as much detail as possible, including:

   * **Image name and version(s):** e.g., `redis-cluster:7.0`, `nginx:1.25`
   * **Features/options:** environment variables, clustering support, plugins, init scripts
   * **Usage example:** `docker run`, Docker Compose, or Kubernetes/Helm snippet
   * **Security expectations:** non-root UID/GID, probes, persistence, compliance requirements
   * **Migration reference:** If replacing Bitnami, note the exact Bitnami tag you are migrating from
   * **Success criteria:** how you’ll know the image works for your case

4. Subscribe to the issue for updates.

5. React with 👍 on other requests to help us prioritize.

**The rule is simple: more requests = faster implementation.**

---

## 🤝 Community & Contribution

This project is free and will always remain free. But speed depends on the community. You can help us by:

* **Filing requests** for new images
* **Testing** existing images and reporting bugs
* **Voting** (👍) on issues to raise priority
* **Submitting PRs** (Dockerfiles, CI improvements, fixes)
* **Sharing** this project with colleagues and communities — many people are still unaware that Bitnami is no longer free

---

## 🔗 Useful Links

* **GitHub repository:** [niceos-labs/containers](https://github.com/niceos-labs/containers)
* **Docker Hub:** [hub.docker.com/u/niceos](https://hub.docker.com/u/niceos)
* **Project website:** [nice-soft.com](https://nice-soft.com/)

---

✨ **NiceOS Containers = Free. Secure. Transparent. Always reproducible.**
Together, we can build the catalog that the community deserves.
