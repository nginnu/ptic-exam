# Design

## Goals

| Goal | Why |
| --- | --- |
| Everything above the cluster lives in Git | A change is a diff, and a rollback is a revert |
| One manual command, everything else from Git | No step that only exists in someone's head |
| Three environments from one set of manifests | The difference between them is a file, not a memory |
| Reachable from the internet without a public IP | The homelab has no fixed address and no load balancer |
| No plaintext secret in Git | The repository is public |

## Topology

```
[ Internet ]
     |
     v
+-----------------------------------------------------------------+
| External ingress                                                |
|   cloudflared tunnel, two replicas behind a PodDisruptionBudget |
|   dials out to Cloudflare; nothing dials in                     |
+-----------------------------------------------------------------+
     |
     v  ClusterIP, HTTP
+-----------------------------------------------------------------+
| Gateway                                                         |
|   Istio ingress gateway implementing the Kubernetes Gateway API |
|   HTTPRoute per hostname; metrics and access logs               |
+-----------------------------------------------------------------+
     |
     +-----------------------------+
     v                             v
+--------------------+    +--------------------+
| Frontend           |    | Backend API        |
| Deployment + HPA   |    | Deployment + HPA   |
| 3 replicas in prod |    | 3 replicas in prod |
+--------------------+    +--------------------+
                                  |
                                  v  TLS, CNPG certificates
                          +--------------------+
                          | pgbouncer          |
                          | CNPG Pooler, rw    |
                          +--------------------+
                                  |
     +----------------------------+----------------------------+
     v                                                         v
+----------------------------------+    +----------------------------------+
| Database                         |    | Object storage                   |
|   CloudNativePG operator         |    |   RustFS, S3-compatible          |
|   Postgres cluster, primary and  |    |   StatefulSet, one replica       |
|   one replica                    |--->|   holds base backups and WAL     |
|   hostPath volumes               |    |   hostPath volume                |
+----------------------------------+    +----------------------------------+
     |                                                         |
     |  continuous WAL archiving and a daily scheduled backup  |
     +---------------------------------------------------------+

     every layer above emits metrics, logs and traces
                          |
                          v
+-----------------------------------------------------------------+
| Observability                                                   |
|   Alloy, one agent per node, collects all three                 |
|   Prometheus (metrics) . Loki (logs) . Tempo (traces)           |
|   Grafana reads all three . Kiali reads the mesh metrics        |
+-----------------------------------------------------------------+

+-----------------------------------------------------------------+
| Delivery                                                        |
|   Argo CD reads this repository and makes the cluster match it  |
|   it manages itself from Git, so no layer is outside GitOps     |
+-----------------------------------------------------------------+
```

### One request, end to end

```
[ Cloudflare edge ]
      |
      v  over the tunnel
[ cloudflared pod ]           dials out; no inbound port, no public IP
      |
      v  ClusterIP
[ Istio gateway ]             HTTPRoute picks the backend by hostname and path
      |
      +-- /       --> [ frontend pod ]   serves the page
      |                   mTLS
      |
      +-- /api/*  --> [ backend pod ] --> [ pgbouncer ] --> [ postgres primary ]
                          mTLS            TLS, CNPG certificates
```

The page fetches `/api/probe` from the browser, so that is a second request down the
same path, not a call the frontend pod makes.

| Layer | What runs it | What it does |
| --- | --- | --- |
| Entry | cloudflared | Dials out to Cloudflare; nothing dials in |
| Gateway types | Kubernetes Gateway API CRDs | Installed first, so the gateway controller finds its types |
| Routing | Istio implementing the Gateway API | Routes, metrics, access logs |
| Applications | Deployment with an HPA | Scale with load |
| Connection pooling | pgbouncer through a CNPG Pooler | The pod count does not reach the database |
| Database | CloudNativePG | Failover, backup, WAL archiving, minor upgrades |
| Object storage | RustFS, S3-compatible, in-cluster | Backups stay on the premises |
| Observability | Alloy, Prometheus, Loki, Tempo, Grafana | Metrics, logs and traces from one agent |
| Delivery | Argo CD | Reads Git and makes the cluster match it |

## Repository layout

| Path | Contents |
| --- | --- |
| `cluster/` | Cluster topology, one file per environment |
| `bootstrap/` | Argo CD installation, applied once by hand |
| `gitops/` | Root application and the Applications it watches |
| `platform/` | Istio, database, object storage, observability |
| `apps/base/` | Application manifests shared by every environment |
| `apps/overlays/<env>/` | Per-environment differences |
| `docs/` | This document and the build notes |

| Decision | Why |
| --- | --- |
| Our own manifests are plain Kustomize | A reviewer reads the diff between environments without rendering anything |
| Third-party components stay upstream Helm charts | Vendoring them turns every upgrade into a diff of thousands of lines |
| Environments are directories, not branches | The difference between them is visible at any moment |

## Cluster

| Decision | Why |
| --- | --- |
| One cluster per environment | Chosen — an outage in one environment cannot reach another |
| Production runs three control planes | Chosen — the etcd quorum survives losing a node |
| Non-production runs one | Chosen — an outage there is not critical, and it saves three machines |
| Workers separate from control planes | Chosen — no workload can starve etcd or the API server |
| Shared nodes with CPU and memory limits | Not chosen — limits cover CPU and memory, not network or disk |
| A load balancer in front of the three API servers | Chosen — kind starts one for it |
| Cluster lifecycle outside GitOps | Chosen — Argo CD needs a cluster before it can manage anything |
| kind reproduces the topology | Chosen — it runs the whole topology on one machine for testing |

| Isolation | What it buys |
| --- | --- |
| No shared control plane | An upgrade touches one environment at a time |
| No shared nodes | A load test cannot slow down dev |

In production the layer below Kubernetes should not be kind. kube-vip fronts the
three API servers, the nodes come from kubeadm or RKE2 depending on the project,
and Terraform or Cluster API owns their lifecycle. Nothing above that layer
changes.

## GitOps flow

```
  push --> git --> argo cd --> cluster
                      |
                      +-- the root application watches gitops/applications
                              |
                              +-- one Application per component
                              +-- one Application per environment where it differs
```

| Decision | Why |
| --- | --- |
| Argo CD installs once, then manages itself from Git | An upgrade is a file change, not a command run from someone's laptop |
| Adding a component is a file in Git | Never a manual apply |
| Adding an environment is registering its cluster and adding its overlay | A developer portal could open that pull request instead of a person |
| Some platform components carry overlays, the rest do not | cloudflared, postgres, rustfs and routes are meant to differ per environment; everything else is meant to be identical |

## Secrets

| Decision | Why |
| --- | --- |
| SOPS with an age key that lives outside this repository | Chosen — Argo CD decrypts at render time, so nothing plaintext is ever committed |
| Keys stay in the clear, values encrypted | Chosen — a reviewer sees what a secret holds, not its value |
| The age key is the one thing bootstrap needs by hand | Chosen — the repository is public, so Argo CD needs no credential to read it |
| Vault | Not chosen — unsealing it needs a KMS this hardware does not have |

In production, where a cloud KMS or an HSM is available, External Secrets should
replace SOPS. The Secret names stay the same, so no Deployment changes; the
`.sops.yaml` files are replaced by `ExternalSecret` resources pointing at the store.

## Storage

| Fact | Consequence |
| --- | --- |
| hostPath is a directory on one node | A pod with that volume stays Pending if its node is down |
| The node's disk is a single point of failure | No snapshots, no replication underneath |
| Volumes come from the `hostpath` class | Named explicitly, so adding a second class later moves nothing |
| local-path-provisioner handles ordinary volumes | It runs the same on kubeadm and RKE2, so nothing here is tied to kind |
| Backups, not volumes, are the recovery path | And the restore is what gets tested |

## Network

```
  internet --> cloudflared --> gateway --> service --> pod
                   ^                         (mTLS inside)
                   |
              dials out only
```

| Decision | Why |
| --- | --- |
| cloudflared is the only inbound path | No public IP, no load balancer, nothing dials in |
| No Service of type LoadBalancer or NodePort anywhere | The validation script asserts it |
| Two replicas behind a PodDisruptionBudget | A rolling update does not drop the tunnel |
| cloudflared forwards to the Istio gateway | Routing, TLS, metrics and access logs stay in one place |

## Ingress and mesh

| Decision | Why |
| --- | --- |
| Istio serves both directions | Chosen — the gateway implements the Gateway API, and the same control plane handles traffic between pods |
| A second ingress controller | Not chosen — an extra hop, metrics split across two components, policy written twice |
| `PeerAuthentication: STRICT` | Chosen — traffic between workloads in the mesh is mTLS or it is refused |
| Default-deny `AuthorizationPolicy` | Chosen — only the paths opened on purpose work |
| One sidecar per workload | The cost of the above: a proxy in every pod, and one more component to upgrade |

In production the database and the object store should join the mesh as well. Here
they run outside it, so the hop from the API to pgbouncer is encrypted by the
certificates CloudNativePG issues rather than by the mesh, and one policy does not
yet cover every hop.

## Data

| Decision | Why |
| --- | --- |
| CloudNativePG runs Postgres | Chosen — failover, backup, WAL archiving and minor upgrades are fields in a custom resource |
| Primary and replica on separate nodes | Chosen — pod anti-affinity on the hostname key, so the scheduler prefers to keep them apart |
| pgbouncer in front through a Pooler | Chosen — the application scales without the connection count reaching the database |
| Continuous backup and WAL archiving to the in-cluster object store | Chosen — nothing leaves the premises and no public endpoint is needed |
| An HPA on the database | Not chosen — CNPG exposes no scale subresource, so an HPA has nothing to drive |

In production reads should have a path of their own. `spec.instances` already puts a
replica on a second node, but the only Pooler here is `rw`, so every query lands on
the primary; a second Pooler of type `ro` and a read-only connection string in the
API would spread them.

## Object storage

| Decision | Why |
| --- | --- |
| In-cluster and S3-compatible | No public IP, and the data never leaves the premises |
| RustFS rather than MinIO | Apache-2.0, after MinIO moved console features behind a commercial licence |
| It inherits the same hostPath limits | The recovery path is the backup, not the volume |

## Scaling

| Decision | Why |
| --- | --- |
| HPA on CPU, fed by metrics-server | Chosen — the signal available without installing anything else |
| A load generator in the validation | Not chosen — proving a scale-up takes several minutes, so validation checks that each HPA reads a CPU figure rather than `<unknown>` |
| A PodDisruptionBudget on each application | Chosen — `minAvailable: 1`, so a drain or a rolling update cannot take every replica at once |

In production CPU is the wrong signal for most workloads. Scale on queue depth or
request rate instead — from Redis, a message queue or an event stream — which is
what KEDA reads, and it can scale to zero as well. A k6 job in CI against staging
is what proves a scale-up actually happens.

- Floodgate — a custom autoscaler I developed, with capacity per replica, headroom, and several scaling modes.

## Observability

```
  pod ──┐
        │
  gateway ──> alloy ──> metrics ──> Prometheus ──┐
              (one per          logs ──> Loki ───┼──> Grafana
               node)            traces ─> Tempo ─┘
```

| Decision | Why |
| --- | --- |
| One agent per node collects metrics, logs and traces | One pipeline to run and upgrade, not three |
| Ingress access logs take the same path as container logs | A 500 at the edge leads back to the pod that caused it |
| The gateway starts a trace and the mesh propagates it | No application change is needed |
| Grafana reads all three | One place to correlate a metric, a log line and a trace |
| Kiali reads the mesh metrics | The service graph and mTLS status come from data already collected |
| Losing this stack does not take the platform down | It watches the system; it is not in the request path |

## Out of scope

The focus here is the GitOps structure and the tunnel that makes it work on bare
metal. These areas were left alone on purpose — happy to go into any of them.

| Area | Not covered |
| --- | --- |
| Network | CNI choice and NetworkPolicy |
| Storage | Replicated block storage |
| Security | Admission policy, Pod Security Standards, image signing |
| TLS | cert-manager |
| Delivery | CI/CD pipeline and progressive delivery |
| Scaling | Node autoscaling and workload autoscaling on custom metrics |
| Recovery | Restore drill, etcd backup, cluster upgrades |
| Operations | Alerting and on-call routing |

## Known limitations

Everything below runs. Each line is the trade-off it was built with.

| Limitation | What it means for you |
| --- | --- |
| The encrypted files here were sealed with the author's age key | Re-encrypt them with your own before installing |
| Production was installed and validated end to end; `dev` and `staging` are proven by rendering their overlays | The difference between them is a file, so rendering is what there is to check |
| A hostPath volume is a directory on one node, with no replication and no snapshots | The recovery path is the backup, and the restore is what needs testing |
| Backups land in the in-cluster object store, which sits on one of those volumes | Nothing leaves the premises by design; a second site or an off-cluster target is the next step |
