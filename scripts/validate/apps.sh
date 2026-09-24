backend_scale_matches_its_overlay() {
  local wanted running
  wanted="$(build_overlay "${ENV}" 2>/dev/null |
    awk '/^kind: HorizontalPodAutoscaler$/{h=1} h && /^  minReplicas:/{print $2; exit}')"
  [ -n "${wanted}" ] || return 1
  [ "$(k -n apps get hpa backend -o jsonpath='{.spec.minReplicas}')" = "${wanted}" ] || return 1
  running="$(k -n apps get deploy backend -o jsonpath='{.status.readyReplicas}')"
  [ -n "${running}" ] && [ "${running}" -ge "${wanted}" ]
}

backend_pods_spread_across_nodes() {
  local nodes
  nodes="$(k -n apps get pods -l app=backend -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u | grep -c .)"
  [ "${nodes}" -gt 1 ]
}

backend_hpa_reads_cpu() {
  k -n apps get hpa backend -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' | grep -q '[0-9]'
}

backend_serves_rows_from_the_database() {
  pod_output_contains apps curlimages/curl:8.11.1 ptic-probe \
    -- -sf --max-time 20 http://backend/probe
}

hpa_reads_metrics() {
  local hpa
  hpa="$(nonempty k -n apps get hpa --no-headers)" || return 1
  ! printf '%s\n' "${hpa}" | grep -q '<unknown>'
}

check "backend scale matches its overlay" backend_scale_matches_its_overlay
check "backend pods spread across nodes" backend_pods_spread_across_nodes
check "backend hpa reads cpu" backend_hpa_reads_cpu
check "backend serves rows from the database" backend_serves_rows_from_the_database

frontend_scale_matches_its_overlay() {
  local wanted running
  wanted="$(build_overlay "${ENV}" 2>/dev/null |
    awk '/name: frontend/{f=1} f && /^  minReplicas:/{print $2; exit}')"
  [ -n "${wanted}" ] || return 1
  [ "$(k -n apps get hpa frontend -o jsonpath='{.spec.minReplicas}')" = "${wanted}" ] || return 1
  running="$(k -n apps get deploy frontend -o jsonpath='{.status.readyReplicas}')"
  [ -n "${running}" ] && [ "${running}" -ge "${wanted}" ]
}

frontend_serves_its_page() {
  pod_output_contains apps curlimages/curl:8.11.1 "PTIC Platform" \
    -- -sf --max-time 20 http://frontend/
}

check "frontend scale matches its overlay" frontend_scale_matches_its_overlay
check "frontend serves its page" frontend_serves_its_page
check "hpa reads cpu from metrics-server" hpa_reads_metrics
