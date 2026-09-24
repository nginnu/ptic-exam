mesh_enforces_mtls() {
  [ "$(k -n istio-system get peerauthentication default -o jsonpath='{.spec.mtls.mode}')" = "STRICT" ]
}

access_logging_is_on() {
  local mesh
  mesh="$(k -n istio-system get configmap istio -o jsonpath='{.data.mesh}')"
  [ "$(printf '%s' "${mesh}" | grep -c 'accessLogFile')" -gt 0 ]
}

proxy_exports_metrics() {
  local stats
  stats="$(k -n cloudflared exec deploy/cloudflared -c istio-proxy -- \
    curl -sf --max-time 10 localhost:15020/stats/prometheus)"
  [ "$(printf '%s' "${stats}" | grep -c '^istio_')" -gt 0 ]
}

proxy_writes_access_logs() {
  local logs
  logs="$(k -n cloudflared logs -l app=cloudflared -c istio-proxy --tail=200)"
  [ "$(printf '%s' "${logs}" | grep -c '"response_code"')" -gt 0 ]
}

check "mesh enforces strict mtls" mesh_enforces_mtls
check "access logging is on" access_logging_is_on
check "proxy exports prometheus metrics" proxy_exports_metrics
check "proxy writes access logs" proxy_writes_access_logs
