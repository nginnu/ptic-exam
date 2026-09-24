#!/usr/bin/env bash
set -uo pipefail

MISSING=0

need() {
  local tool="$1" hint="$2"
  if command -v "${tool}" >/dev/null 2>&1; then
    printf 'ok      %s\n' "${tool}"
  else
    printf 'missing %-10s %s\n' "${tool}" "${hint}"
    MISSING=1
  fi
}

need docker  "https://docs.docker.com/get-docker"
need kind    "brew install kind"
need kubectl "brew install kubernetes-cli"
need helm    "brew install helm"
need sops    "brew install sops"
need age     "brew install age"

exit "${MISSING}"
