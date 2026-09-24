TELEMETRYGEN="ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.140.1"
PROBE_SERVICE="ptic-probe"

observability_pods_running() {
  local unhealthy
  unhealthy="$(k -n observability get pods --no-headers | grep -cv ' Running ')"
  [ "${unhealthy}" = "0" ]
}

curl_in_cluster() {
  run_pod observability curlimages/curl:8.11.1 -- -sf --max-time 20 "$@"
}

emit_telemetry() {
  local signal="$1"
  k -n observability run "telemetrygen-${signal}-$$" --rm -i --restart=Never --quiet \
    --image="${TELEMETRYGEN}" -- "${signal}" \
    --otlp-endpoint alloy:4317 --otlp-insecure \
    --service "${PROBE_SERVICE}" "--${signal}" 20 >/dev/null 2>&1
}

emitted_traces_reach_tempo() {
  emit_telemetry traces || return 1
  contains "$(curl_in_cluster "http://tempo:3200/api/search/tag/service.name/values")" "${PROBE_SERVICE}"
}

emitted_metrics_reach_prometheus() {
  emit_telemetry metrics || return 1
  sleep 15
  contains "$(curl_in_cluster "http://prometheus-server/api/v1/label/job/values")" "${PROBE_SERVICE}"
}

emitted_logs_reach_loki() {
  emit_telemetry logs || return 1
  sleep 5
  local out
  out="$(curl_in_cluster --get "http://loki:3100/loki/api/v1/query_range" \
    --data-urlencode "query={service_name=\"${PROBE_SERVICE}\"}" \
    --data-urlencode "limit=1")"
  contains "${out}" '"resultType":"streams"' && ! contains "${out}" '"result":[]'
}

check "observability pods running" observability_pods_running
check "emitted traces arrive in tempo" emitted_traces_reach_tempo
check "emitted metrics arrive in prometheus" emitted_metrics_reach_prometheus
check "emitted logs arrive in loki" emitted_logs_reach_loki
