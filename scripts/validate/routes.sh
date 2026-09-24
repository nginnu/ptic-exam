GATEWAY="http://external-istio.istio-system.svc.cluster.local"

route_hosts() {
  k -n routes get httproute -o jsonpath='{range .items[*]}{.spec.hostnames[0]}{"\n"}{end}' | grep .
}

every_route_is_accepted() {
  local total accepted
  total="$(route_hosts | grep -c .)"
  accepted="$(k -n routes get httproute -o jsonpath='{range .items[*]}{.status.parents[0].conditions[?(@.type=="Accepted")].status}{"\n"}{end}' | grep -c True)"
  [ "${total}" -gt 0 ] && [ "${total}" = "${accepted}" ]
}

every_route_answers_through_the_gateway() {
  local host code
  for host in $(route_hosts); do
    code="$(run_pod apps curlimages/curl:8.11.1 -- \
      -s -o /dev/null -w '%{http_code}' --max-time 15 -H "Host: ${host}" "${GATEWAY}/")"
    case "${code}" in
      200|302|403) ;;
      *) return 1 ;;
    esac
  done
}

public_bucket_is_readable_without_credentials() {
  run_pod apps curlimages/curl:8.11.1 -- \
    -s -o /dev/null -w '%{http_code}' --max-time 15 \
    -H "Host: s3-ptic.nginnu.com" "${GATEWAY}/public/photo.jpg" | grep -q 200
}

check "every route is accepted by the gateway" every_route_is_accepted
check "every route answers through the gateway" every_route_answers_through_the_gateway
check "public bucket is readable without credentials" public_bucket_is_readable_without_credentials
