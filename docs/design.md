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
