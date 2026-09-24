#!/usr/bin/env bash
set -euo pipefail

ENV="${ENV:-prod}"
NODE_IMAGE="${NODE_IMAGE:-kindest/node:v1.34.11}"
CONFIG="$(dirname "$0")/../cluster/${ENV}.yaml"
CLUSTER_NAME="ptic-${ENV}-cluster"

if [ ! -f "${CONFIG}" ]; then
  echo "no cluster config for ${ENV}"
  exit 1
fi

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "cluster ${CLUSTER_NAME} already exists"
  exit 0
fi

kind create cluster --name "${CLUSTER_NAME}" --image "${NODE_IMAGE}" --config "${CONFIG}" --wait 300s
kubectl --context "kind-${CLUSTER_NAME}" wait --for=condition=Ready nodes --all --timeout=300s
