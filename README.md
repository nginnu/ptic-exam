# ptic-exam

GitOps repository for a bare-metal Kubernetes homelab running three environments: `dev`, `staging` and `prod`.

## Scope

| Component | Choice |
| --- | --- |
| Database | CloudNativePG on hostPath |
| Backend API | Scalable, HA deployment |
| Frontend | Scalable, HA deployment |
| Ingress | Istio with the Kubernetes Gateway API |
| Object storage | In-cluster, S3-compatible |
| Observability | Metrics, logs and traces |
| External access | cloudflared tunnel, the only inbound path |

## Repository layout

| Path | Contents |
| --- | --- |
| `cluster/` | Cluster topology, one file per environment |
| `bootstrap/` | Argo CD installation, applied once by hand |
| `gitops/` | Root application and the Applications it watches |
| `platform/` | Platform components and their values |
| `apps/base/` | Application manifests shared by every environment |
| `apps/overlays/` | Per-environment overlays for `dev`, `staging` and `prod` |
| `docs/` | Design document and build notes |
