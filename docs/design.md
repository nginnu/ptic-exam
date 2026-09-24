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
                                  v  mTLS inside the mesh
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
|   replica on separate nodes      |<---|   holds base backups and WAL     |
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
      v  HTTP/2 over the tunnel
[ cloudflared pod ]           dials out; no inbound port, no public IP
      |
      v  ClusterIP
[ Istio gateway ]             HTTPRoute picks the service by hostname
      |
      v  mTLS
[ frontend pod ] --> [ backend pod ] --> [ pgbouncer ] --> [ postgres primary ]
```

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
| One cluster per environment | An outage in one environment cannot reach another |
| Production runs three control planes | The etcd quorum survives losing a node |
| Non-production runs one | An outage there is not critical, and it costs three fewer machines |
| Workers separate from control planes | No workload can starve etcd or the API server |
| Three API servers need a load balancer in front | kind ships haproxy; real hardware uses kube-vip |
| Cluster lifecycle sits outside GitOps | In production Terraform or Cluster API owns that layer |
| kind reproduces the topology for review | Real hardware would use kubeadm or RKE2 |

| Isolation | What it buys |
| --- | --- |
| No shared control plane | An upgrade touches one environment at a time |
| No shared nodes | A load test cannot slow down dev |
| CPU and memory limits do not cover network or disk | Only separate nodes do |

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

## Promotion

| Decision | Why |
| --- | --- |
| Environments are directories on one branch | The difference between them is visible at any moment |
| A change moves forward by editing the next environment's overlay | Usually one image tag |
| Every environment syncs automatically | Production needs a second reviewer on the pull request |

## Secrets

| Decision | Why |
| --- | --- |
| SOPS with an age key that lives outside this repository | Argo CD decrypts at render time; nothing plaintext is ever committed |
| Keys stay in the clear, values encrypted | A reviewer sees what a secret holds, not its value |
| Bootstrap needs one thing by hand: the age key | The repository itself is public, so Argo CD needs no credential to read it |
| Vault was rejected | Unsealing it needs a KMS this hardware does not have |
| With a cloud or an HSM, External Secrets replaces SOPS | No application manifest would change |

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
| Istio serves both directions | The gateway implements the Gateway API; the mesh handles traffic between pods |
| A second ingress controller was rejected | Extra hop, split metrics, policy written twice |
| `PeerAuthentication: STRICT` | Traffic between workloads in the mesh is mTLS or it is refused |
| Default-deny `AuthorizationPolicy` | Only the paths opened on purpose work |
| Cost | One proxy per workload, one more component to upgrade |

## Data

| Decision | Why |
| --- | --- |
| CloudNativePG runs Postgres | Failover, backup, WAL archiving and minor upgrades are fields in a custom resource |
| Primary and replica spread across nodes | One node going down does not take both |
| pgbouncer in front through a Pooler | The application scales without the connection count reaching the database |
| Continuous backup and WAL archiving to the in-cluster object store | Nothing leaves the premises and no public endpoint is needed |
| Read replicas scale by changing `spec.instances` | Writes stay on one primary |
| CNPG exposes no scale subresource | An HPA cannot drive it; a controller or KEDA would |

## Object storage

| Decision | Why |
| --- | --- |
| In-cluster and S3-compatible | No public IP, and the data never leaves the premises |
| RustFS rather than MinIO | Apache-2.0, after MinIO moved console features behind a commercial licence |
| It inherits the same hostPath limits | The recovery path is the backup, not the volume |

## Scaling

| Decision | Why |
| --- | --- |
| HPA on CPU, fed by metrics-server | The signal available without installing anything else |
| Validation checks that the HPA reads a number, not that it scales | Proving a scale-up needs a load generator and several minutes; on real hardware that is a k6 job in CI against staging |
| PodDisruptionBudget and pods spread across nodes | A node loss or a rolling update does not drop capacity |

### A better scaling signal

- Scale by workload metrics from Redis, an MQ, or an event stream, not by CPU alone.
- KEDA supports workload-based autoscaling and scale-to-zero.
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

## Not here

The focus here is the GitOps structure and the tunnel that makes it work on bare metal. Other areas go only as deep as that needed — happy to go into any of them.

| Area | Left out |
| --- | --- |
| Network | CNI choice and NetworkPolicy |
| Storage | Replicated block storage; a volume stays on the node that wrote it |
| Security | Admission policy, Pod Security Standards, image signing |
| TLS | cert-manager |
| Delivery | CI/CD pipeline and progressive delivery |
| Scaling | Node autoscaling and workload autoscaling on custom metrics |
| Recovery | Restore drill, etcd backup, cluster upgrades |
| Operations | Alerting and on-call routing |

| Known limitation | |
| --- | --- |
| The encrypted files here were sealed with the author's age key | Re-encrypt them with your own before installing |
| Only production was installed and validated end to end | `dev` and `staging` are proven by rendering their overlays, not by running them |
| `metrics-server` runs with `--kubelet-insecure-tls` | kind requires it; on real hardware, enable kubelet certificate rotation and drop the flag |
| hostPath has no snapshots and no replication | The recovery path is the backup, and the restore is what needs testing |
| The applications run in the mesh, the database and object store do not | Their traffic is not mTLS |
