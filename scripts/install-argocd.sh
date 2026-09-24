#!/usr/bin/env bash
set -euo pipefail

ENV="${ENV:-prod}"
CONTEXT="kind-ptic-${ENV}-cluster"
NAMESPACE="argocd"
CHART_VERSION="${ARGOCD_CHART_VERSION:-10.9.2}"
HERE="$(cd "$(dirname "$0")" && pwd)"

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update argo >/dev/null

helm upgrade --install argocd argo/argo-cd \
  --kube-context "${CONTEXT}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --version "${CHART_VERSION}" \
  --values "${HERE}/../bootstrap/argocd/values.yaml" \
  --wait --timeout 10m

kubectl --context "${CONTEXT}" -n "${NAMESPACE}" create secret generic in-cluster \
  --from-literal=name=in-cluster \
  --from-literal=server=https://kubernetes.default.svc \
  --from-literal=config='{"tlsClientConfig":{"insecure":false}}' \
  --dry-run=client -o yaml \
  | kubectl --context "${CONTEXT}" label -f - --local -o yaml --dry-run=client \
      argocd.argoproj.io/secret-type=cluster "env=${ENV}" \
  | kubectl --context "${CONTEXT}" apply -f -

kubectl --context "${CONTEXT}" apply -f "${HERE}/../gitops/root-app.yaml"
