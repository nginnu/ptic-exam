PG_IMAGE="ghcr.io/cloudnative-pg/postgresql:18.1"

postgres_cluster_is_healthy() {
  [ "$(k -n postgres get cluster postgres -o jsonpath='{.status.phase}')" = "Cluster in healthy state" ]
}

postgres_has_two_ready_instances() {
  [ "$(k -n postgres get cluster postgres -o jsonpath='{.status.readyInstances}')" = "2" ]
}

postgres_instances_sit_on_separate_nodes() {
  local nodes
  nodes="$(k -n postgres get pods -l cnpg.io/cluster=postgres,cnpg.io/podRole=instance -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u | grep -c .)"
  [ "${nodes}" = "2" ]
}

postgres_volumes_are_bound_on_hostpath() {
  local bound
  bound="$(k -n postgres get pvc -o jsonpath='{range .items[?(@.spec.storageClassName=="hostpath")]}{.status.phase}{"\n"}{end}' | grep -c Bound)"
  [ "${bound}" = "2" ]
}

psql_in_cluster() {
  local host="$1" sql="$2" password
  password="$(k -n postgres get secret postgres-app -o jsonpath='{.data.password}' | base64 -d)"
  run_pod postgres "${PG_IMAGE}" \
    --env=PGPASSWORD="${password}" \
    --command -- psql -h "${host}" -U ptic -d ptic -tAc "${sql}"
}

postgres_accepts_a_write() {
  psql_in_cluster postgres-rw \
    "CREATE TABLE IF NOT EXISTS probe (id int primary key, note text);
     INSERT INTO probe VALUES (1, 'ptic-probe') ON CONFLICT (id) DO UPDATE SET note = 'ptic-probe';
     SELECT note FROM probe WHERE id = 1;" | grep -q ptic-probe
}

replica_serves_the_same_row() {
  sleep 5
  psql_in_cluster postgres-ro "SELECT note FROM probe WHERE id = 1;" | grep -q ptic-probe
}

pooler_has_two_ready_instances() {
  [ "$(k -n postgres get pods -l cnpg.io/poolerName=postgres-pooler --no-headers | grep -c ' Running ')" = "2" ]
}

pooler_accepts_a_write() {
  psql_in_cluster postgres-pooler \
    "INSERT INTO probe VALUES (2, 'via-pooler') ON CONFLICT (id) DO UPDATE SET note = 'via-pooler';
     SELECT note FROM probe WHERE id = 2;" | grep -q via-pooler
}

repository_holds_no_plaintext_password() {
  ! grep -rIn -E "(password|PGPASSWORD)[\"'\''[:space:]]*[:=]" \
    "${ROOT}" \
    --include="*.yaml" --include="*.sh" --include="*.md" \
    --exclude-dir=.git 2>/dev/null |
    grep -v "secretKeyRef\|valueFrom\|\.sops\.yaml\|scripts/validate/" |
    grep -q .
}

check "postgres cluster healthy" postgres_cluster_is_healthy
check "postgres has two ready instances" postgres_has_two_ready_instances
check "postgres instances sit on separate nodes" postgres_instances_sit_on_separate_nodes
check "postgres volumes bound on hostpath" postgres_volumes_are_bound_on_hostpath
check "postgres accepts a write" postgres_accepts_a_write
check "replica serves the same row" replica_serves_the_same_row
check "pgbouncer has two ready instances" pooler_has_two_ready_instances
check "a write through pgbouncer comes back" pooler_accepts_a_write
check "repository holds no plaintext password" repository_holds_no_plaintext_password
