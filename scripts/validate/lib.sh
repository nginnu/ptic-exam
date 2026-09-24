ENV="${ENV:-prod}"
CLUSTER_NAME="ptic-${ENV}-cluster"
CONTEXT="kind-${CLUSTER_NAME}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG="${ROOT}/cluster/${ENV}.yaml"
FAILED=0

check() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'ok    %s\n' "${name}"
  else
    printf 'FAIL  %s\n' "${name}"
    FAILED=1
  fi
}

k() {
  kubectl --context "${CONTEXT}" "$@"
}

nodes_in_config() {
  grep -c "role: $1" "${CONFIG}"
}

nonempty() {
  local out
  out="$("$@")" || return 1
  [ -n "${out}" ] || return 1
  printf '%s\n' "${out}"
}

run_pod() {
  local namespace="$1" image="$2"
  shift 2
  local out
  for _ in 1 2 3; do
    out="$(k -n "${namespace}" run "probe-$$-${RANDOM}" --rm -i --restart=Never --quiet \
      --image="${image}" "$@" 2>/dev/null)"
    if [ -n "${out}" ]; then
      printf '%s\n' "${out}"
      return 0
    fi
    sleep 5
  done
  return 1
}

build_overlay() {
  kustomize build --enable-alpha-plugins --enable-exec "${ROOT}/apps/overlays/$1"
}

contains() {
  case "$1" in *"$2"*) return 0 ;; esac
  return 1
}

pod_output_contains() {
  local namespace="$1" image="$2" pattern="$3"
  shift 3
  local out
  out="$(run_pod "${namespace}" "${image}" "$@")" || return 1
  case "${out}" in *"${pattern}"*) return 0 ;; esac
  return 1
}
