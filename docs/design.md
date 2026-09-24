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
                     Cloudflare
                          |
                          |  the tunnel dials out
                          v
   +---------------------------------------------+
   |  one cluster per environment                |
   |                                             |
   |   cloudflared --> gateway --> apps          |
   |                                 |           |
   |                                 v           |
   |                          postgres   object  |
   |                                      store  |
   |                                             |
   |   argo cd  <-- git                          |
   +---------------------------------------------+
```

| Layer | What runs it | What it does |
| --- | --- | --- |
| Entry | cloudflared | Dials out to Cloudflare; nothing dials in |
| Routing | Istio with the Gateway API | Routes, metrics, access logs |
| Applications | Deployment with an HPA | Scale with load |
| Database | CloudNativePG | Failover, backup, WAL archiving, minor upgrades |
| Object storage | S3-compatible, in-cluster | Backups stay on the premises |
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
                              +-- one Application per environment for apps/
```

| Decision | Why |
| --- | --- |
| Argo CD installs once, then manages itself from Git | An upgrade is a file change, not a command run from someone's laptop |
| Adding a component is a file in Git | Never a manual apply |
| Adding an environment is registering its cluster and adding its overlay | A developer portal could open that pull request instead of a person |

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
| Requests per second is the better signal | It needs Prometheus Adapter or KEDA; CPU stands in until then |
| PodDisruptionBudget and pods spread across nodes | A node loss or a rolling update does not drop capacity |
