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

kubectl --context "${CONTEXT}" apply -f "${HERE}/../gitops/root-app.yaml"
