argocd_pods_running() {
  local pods
  pods="$(nonempty k -n argocd get pods --no-headers)" || return 1
  [ "$(printf '%s\n' "${pods}" | grep -v ' Running ' | grep -cv ' Completed ')" = "0" ]
}

cluster_is_registered_for_this_env() {
  [ "$(k -n argocd get secret in-cluster -o jsonpath='{.metadata.labels.env}')" = "${ENV}" ]
}

root_application_is_synced() {
  [ "$(k -n argocd get application root -o jsonpath='{.status.sync.status}')" = "Synced" ]
}

root_application_is_healthy() {
  [ "$(k -n argocd get application root -o jsonpath='{.status.health.status}')" = "Healthy" ]
}

every_application_is_synced() {
  local apps
  apps="$(nonempty k -n argocd get applications --no-headers)" || return 1
  ! printf '%s\n' "${apps}" | grep -qv 'Synced *Healthy'
}

no_service_is_externally_exposed() {
  [ -z "$(k get svc -A -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].metadata.name}{.items[?(@.spec.type=="NodePort")].metadata.name}')" ]
}

check "argo cd pods running" argocd_pods_running
check "cluster registered for this environment" cluster_is_registered_for_this_env
check "root application synced" root_application_is_synced
check "root application healthy" root_application_is_healthy
check "every application synced and healthy" every_application_is_synced
check "no service exposed outside the cluster" no_service_is_externally_exposed
