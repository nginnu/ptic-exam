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

- [ ] Argo CD and the root application
- [ ] hostPath storage class
- [ ] Environment overlays
- [ ] Encrypted secrets

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
