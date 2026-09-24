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

## Validate without a cluster

```
make build
```

Renders every environment from a fresh clone. It needs `kustomize` and nothing else.

## Install

| Command | What it does |
| --- | --- |
| `make check-tools` | Report tools missing from this machine |
| `make install-cluster` | Create the cluster for `ENV` |
| `make install-argocd` | Install Argo CD and apply the root application |
| `make validate` | Check that what is installed actually works |
| `make delete-cluster` | Remove the cluster |

`ENV` selects the environment: `dev`, `staging` or `prod`. Step by step: [docs/install.md](docs/install.md).

## Validate with a cluster

`make validate` checks results rather than the presence of objects. Each topic also runs on its own as `make validate-<topic>`.

| Topic | What it proves |
| --- | --- |
| `manifests` | Every overlay builds |
| `cluster` | Node counts, etcd members and taints match the environment's config |
| `gitops` | Argo CD healthy, every Application synced, no Service exposed outside the cluster |
| `storage` | An object written to the store and read back unchanged |
| `database` | The database accepts a write; the replica follows the primary |
| `backup` | A forced WAL switch lands a segment in the object store; a new backup completes |
| `apps` | The API answers, reaches the database through the pooler, and each HPA reads a CPU figure |
| `routes` | The page renders through the gateway |
| `ingress` | Strict mTLS, access logging on, the proxy exporting metrics and writing logs |
| `observability` | A metric, a log line and a trace emitted and read back out |

## Bootstrap assumptions

- The cluster exists and is reachable.
- An age key pair for SOPS exists outside this repository, and the encrypted files here have been re-encrypted with it.
- A Cloudflare tunnel has been created and its credentials encrypted into this repository.

## Running system

Every address below is served through the Cloudflare tunnel. The cluster has no public IP and no load balancer.

| URL | What it is |
| --- | --- |
| https://ptic.nginnu.com/ | The frontend, reading the API |
| https://argocd-ptic.nginnu.com/ | Argo CD, showing every Application and its sync state |
| https://grafana-ptic.nginnu.com/ | Grafana, reading Prometheus, Loki and Tempo |
| https://kiali-ptic.nginnu.com/ | Kiali, showing the mesh and its traffic |
| https://rustfs-ptic.nginnu.com/rustfs/console/ | The object store console |
| https://s3-ptic.nginnu.com/public/photo.jpg | An object served from the store |

### The frontend, through the tunnel

![The frontend](docs/images/frontend.png)

### Argo CD, every Application synced from this repository

![Argo CD](docs/images/argocd.png)

### Kiali, showing the mesh policy in effect

![Kiali](docs/images/kiali.png)

### The object store, holding the backup bucket

![RustFS](docs/images/rustfs.png)

### The cluster: three control planes and three workers

![Cluster nodes](docs/images/cluster-node.png)

## Known limitations

- The encrypted files here were sealed with the author's age key. Re-encrypt them with your own before installing.
- Only production was installed and validated end to end. `dev` and `staging` are proven by `make build`.
- `metrics-server` runs with `--kubelet-insecure-tls`, which kind requires. On real hardware, enable kubelet certificate rotation and drop the flag.
- hostPath has no snapshots and no replication. The recovery path is the backup, and the restore is what needs testing.
- The applications run in the mesh. The database and the object store do not, so their traffic is not mTLS.

## Design document

See [docs/design.md](docs/design.md).
