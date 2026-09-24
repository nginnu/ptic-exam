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
