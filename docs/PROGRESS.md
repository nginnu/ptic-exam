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
- [x] hostPath storage: `local-path-provisioner` at sync wave -2, StorageClass `hostpath` on `/var/lib/ptic/volumes`. PVCs name the class rather than relying on the default.
- [x] Base and per-environment overlays: `apps/base` shared, `apps/overlays/{dev,staging,prod}` per environment. The cluster is labelled with its environment at install time, and an ApplicationSet turns that label into the overlay it renders.
- [x] SOPS secret encryption: an age key held outside the repository, a `.sops.yaml` path rule, and ksops installed into the repo server by an initContainer. Argo CD decrypts at render time, so no plaintext secret is committed.
- [x] `make build`: renders every overlay without a cluster, so the repository can be checked from a fresh clone.

## Phase 3 — Networking

- [ ] Gateway API and Istio
- [ ] Mesh policy
- [ ] cloudflared tunnel

## Phase 4 — Data

- [ ] Object storage
- [ ] PostgreSQL
- [ ] Backups

## Phase 5 — Applications

- [ ] Backend API
- [ ] Frontend
- [ ] Routes

## Phase 6 — Observability

- [ ] Metrics, logs and traces
- [ ] Dashboards

## Phase 7 — Wrap-up

- [ ] Install guide
- [ ] Known limitations
