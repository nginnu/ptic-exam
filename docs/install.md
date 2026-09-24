# Install

Every step is run from a clone of this repository.

## 1. Tools

```
make check-tools
```

Installs nothing. It reports what is missing. Required: docker, kind, kubectl, helm, sops, age.

## 2. Secrets

The encrypted files here were sealed with the author's age key. Create your own and re-encrypt them before installing.

```
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
```

Put the public key it prints into `.sops.yaml`, then re-encrypt each `*.sops.yaml` with `sops --rotate --in-place`.

## 3. Cloudflare tunnel

Create a tunnel on a domain served by Cloudflare and point a hostname at it. Put the tunnel id in `platform/cloudflared/base/config.yaml` and encrypt its credentials file into `platform/cloudflared/base/credentials.sops.yaml`.

## 4. Cluster

```
make install-cluster ENV=prod
```

`ENV` picks the file in `cluster/`. Production runs three control planes; dev and staging run one.

kind installs its own provisioner and default StorageClass. Both are replaced by the ones in this repository, so remove them once:

```
kubectl -n local-path-storage delete deployment local-path-provisioner
kubectl -n local-path-storage delete serviceaccount local-path-provisioner-service-account
kubectl delete storageclass standard
```

Real hardware has neither, so this step is for kind only. `cluster/` describes the topology with kind so it can be reproduced on a laptop; on real hardware the same shape is built with kubeadm or RKE2, and nothing above that layer changes.

## 5. Argo CD

```
make install-argocd ENV=prod
```

This installs Argo CD, loads the age key, registers the cluster with its environment label, and applies `gitops/root-app.yaml`. It is the only manual apply in the project. Everything else arrives from Git.

## 6. Check

```
make build      renders every overlay; needs no cluster
make validate   runs against the cluster
```

## Access

Argo CD has no public route by design. Reach it through a port forward:

```
kubectl -n argocd port-forward svc/argocd-server 8080:80
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

## Removing it

```
make delete-cluster ENV=prod
```

---

This repository is aimed at the GitOps structure and the tunnel model. Other areas are covered at the level the task needed rather than in full depth — happy to go into any of them.
