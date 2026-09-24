#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAILED=0

for overlay in "${ROOT}"/apps/overlays/*/; do
  name="$(basename "${overlay}")"
  if kubectl kustomize "${overlay}" >/dev/null 2>&1; then
    printf 'ok    %s overlay builds\n' "${name}"
  else
    printf 'FAIL  %s overlay builds\n' "${name}"
    FAILED=1
  fi
done

exit "${FAILED}"
