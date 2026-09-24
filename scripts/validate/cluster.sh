control_plane_count_matches() {
  [ "$(k get nodes -l node-role.kubernetes.io/control-plane --no-headers | wc -l | tr -d ' ')" \
    = "$(nodes_in_config control-plane)" ]
}

worker_count_matches() {
  [ "$(k get nodes -l '!node-role.kubernetes.io/control-plane' --no-headers | wc -l | tr -d ' ')" \
    = "$(nodes_in_config worker)" ]
}

all_nodes_ready() {
  local nodes
  nodes="$(k get nodes --no-headers)" || return 1
  [ -n "${nodes}" ] || return 1
  ! printf '%s\n' "${nodes}" | grep -qv ' Ready'
}

etcd_member_count_matches() {
  local pod
  pod="$(k -n kube-system get pods -l component=etcd -o name | head -1)"
  [ -n "${pod}" ] || return 1
  [ "$(k -n kube-system exec "${pod}" -- etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    member list | wc -l | tr -d ' ')" = "$(nodes_in_config control-plane)" ]
}

control_planes_stay_tainted() {
  [ "$(k get nodes -l node-role.kubernetes.io/control-plane \
    -o jsonpath='{range .items[*]}{.spec.taints[?(@.key=="node-role.kubernetes.io/control-plane")].effect}{"\n"}{end}' \
    | grep -c NoSchedule)" = "$(nodes_in_config control-plane)" ]
}

check "control-plane count matches the config" control_plane_count_matches
check "worker count matches the config" worker_count_matches
check "all nodes ready" all_nodes_ready
check "etcd member count matches the config" etcd_member_count_matches
check "control-plane nodes stay tainted" control_planes_stay_tainted
