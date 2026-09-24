#!/usr/bin/env bash
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "${HERE}/validate/lib.sh"

TOPICS="cluster gitops"
WANTED="${1:-${TOPICS}}"

for topic in ${WANTED}; do
  if [ ! -f "${HERE}/validate/${topic}.sh" ]; then
    echo "unknown topic: ${topic}"
    echo "topics: ${TOPICS}"
    exit 2
  fi
done

for topic in ${WANTED}; do
  echo "${topic}"
  . "${HERE}/validate/${topic}.sh"
done

exit "${FAILED}"
