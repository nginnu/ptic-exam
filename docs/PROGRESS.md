# Build notes

What exists in this repository and why. Each section reflects the current state, not the order things happened.

## Phase 0 — Foundation

- [x] Repository skeleton: directory layout, `.gitignore`, `.editorconfig`, README. The layout separates `cluster/`, `gitops/`, `platform/` and `apps/` so each concern can be owned and reviewed on its own.
- [x] Design document: goals, topology and repository layout, written before the first manifest so every later phase has a decision to build against.

## Phase 1 — Infrastructure

- [x] Cluster topology per environment: `cluster/<env>.yaml`. Production runs three control planes with stacked etcd and three workers; dev and staging run one control plane and two workers.
- [x] `Makefile` and `scripts/`: `check-tools`, `install-cluster`, `delete-cluster`, `validate`. Written alongside the cluster rather than at the end so every phase adds its own checks as it lands.
- [x] `scripts/validate.sh`: node counts, node readiness, etcd members and the control-plane taint, all compared against the environment's own config rather than a fixed number.

## Phase 2 — GitOps

- [x] Argo CD installed from `bootstrap/` with the upstream Helm chart, then managed from this repository by its own Application. Helm rather than the plain install manifest so resource requests stay small and unused components are switched off.
- [x] `gitops/root-app.yaml`: the one Application applied by hand. It watches `gitops/applications`, so every later component arrives by committing a file.
- [x] hostPath storage: `local-path-provisioner` at sync wave -2, StorageClass `hostpath` on `/var/lib/ptic/volumes`. It replaces the one kind installs, which is deleted by hand once — a cluster built by kubeadm or RKE2 never has it. PVCs name the class rather than relying on the default, so adding a second class later moves nothing.
- [x] Base and per-environment overlays: `apps/base` shared, `apps/overlays/{dev,staging,prod}` per environment. The cluster is labelled with its environment at install time, and an ApplicationSet turns that label into the overlay it renders.
- [x] SOPS secret encryption: an age key held outside the repository, a `.sops.yaml` path rule, and ksops installed into the repo server by an initContainer. Argo CD decrypts at render time, so no plaintext secret is committed.
- [x] `make build`: renders every overlay without a cluster, so the repository can be checked from a fresh clone.

## Phase 3 — Networking

- [x] Gateway API CRDs at sync wave -3, installed before Istio so the gateway controller finds its types.
- [x] Istio: `istio-base`, `istiod` and an ingress gateway. Sidecars rather than ambient, because they carry the metrics and access logs the design depends on.
- [x] Mesh policy: `PeerAuthentication` STRICT and a default-deny `AuthorizationPolicy`, with one rule opening the gateway. Traffic between pods is mTLS or it is refused.
- [x] `Gateway` resource on the ingress gateway, kept at `ClusterIP`, the only entry into the mesh.
- [x] cloudflared: two replicas with a PodDisruptionBudget, tunnel credentials held encrypted. The tunnel dials out, so the cluster keeps no LoadBalancer, NodePort or public IP.
- [x] Validation: strict mTLS, access logging on, the proxy exporting Prometheus metrics, and the proxy writing access logs.

## Phase 4 — Data

- [x] Object storage: RustFS as a StatefulSet claiming a `hostpath` volume, reached over a headless Service. S3-compatible and in-cluster, so backups never leave the premises and no public endpoint is needed.
- [x] PostgreSQL through CloudNativePG: one instance in dev, two in staging and production, spread across nodes by anti-affinity, with pgbouncer in front through a Pooler.
- [x] Continuous backup and WAL archiving into the object store, with a daily scheduled backup and a seven-day retention policy.
- [x] Credentials for both are generated per install and encrypted with SOPS; ksops renders them at sync time, so the repository holds ciphertext only.
- [x] Validation: an object written and read back, the database accepting a write, the replica following the primary, and a WAL segment landing in the object store after a forced switch.

## Phase 5 — Applications

- [x] Backend: PostgREST exposing the database as a REST API, reaching it through pgbouncer rather than the primary directly, so the connection count does not grow with the pod count.
- [x] Frontend: a page that reads the API, three replicas in production and one in dev.
- [x] Routes: every entry point kept in one component, so the paths the tunnel exposes are read in a single file.
- [x] metrics-server at sync wave -2, so the HPAs have numbers to read before the applications land.
- [x] Validation: the API answering, the database accepting a write through the pooler, the page rendering through the gateway, and each HPA reading a CPU figure rather than `<unknown>`.

## Phase 6 — Observability

- [x] One Alloy agent per node collects metrics, logs and traces and forwards them to Prometheus, Loki and Tempo.
- [x] Grafana reads all three; Kiali reads the mesh metrics for the service graph.
- [x] Validation emits a metric, a log line and a trace, then reads each one back out of its store.

## Phase 7 — Wrap-up

- [x] Install guide: `docs/install.md`, from an empty machine to a validated cluster.
- [x] Known limitations recorded in the README.

---

This repository is aimed at the GitOps structure and the tunnel model. Other areas are covered at the level the task needed rather than in full depth — happy to go into any of them.
