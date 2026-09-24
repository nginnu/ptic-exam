BACKUP_BUCKET="postgres-backup"

aws_in_cluster() {
  local access secret
  access="$(k -n rustfs get secret rustfs -o jsonpath='{.data.accessKey}' | base64 -d)"
  secret="$(k -n rustfs get secret rustfs -o jsonpath='{.data.secretKey}' | base64 -d)"
  [ -n "${access}" ] && [ -n "${secret}" ] || return 1
  run_pod rustfs amazon/aws-cli:2.32.9 \
    --env=AWS_ACCESS_KEY_ID="${access}" \
    --env=AWS_SECRET_ACCESS_KEY="${secret}" \
    --env=AWS_DEFAULT_REGION=us-east-1 \
    --command -- aws --endpoint-url http://rustfs:9000 "$@"
}

continuous_archiving_is_working() {
  k -n postgres get cluster postgres \
    -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")].status}' |
    grep -qx True
}

base_backups_are_in_the_object_store() {
  contains "$(aws_in_cluster s3 ls "s3://${BACKUP_BUCKET}/postgres/base/" --recursive)" data.tar
}

wal_segments_are_in_the_object_store() {
  local primary
  primary="$(k -n postgres get cluster postgres -o jsonpath='{.status.currentPrimary}')"
  k -n postgres exec "${primary}" -c postgres -- \
    psql -U postgres -tAc "SELECT pg_switch_wal();" >/dev/null 2>&1
  for _ in $(seq 1 6); do
    if contains "$(aws_in_cluster s3 ls "s3://${BACKUP_BUCKET}/postgres/wals/" --recursive)" ".gz"; then
      return 0
    fi
    sleep 10
  done
  return 1
}

a_new_backup_completes() {
  local name="validate-$(date +%s)"
  cat <<EOF | k apply -f - >/dev/null 2>&1 || return 1
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: ${name}
  namespace: postgres
spec:
  cluster:
    name: postgres
EOF
  local phase=""
  for _ in $(seq 1 30); do
    sleep 5
    phase="$(k -n postgres get backup "${name}" -o jsonpath='{.status.phase}' 2>/dev/null)"
    case "${phase}" in completed|failed) break ;; esac
  done
  k -n postgres delete backup "${name}" >/dev/null 2>&1
  [ "${phase}" = "completed" ]
}

check "continuous archiving is working" continuous_archiving_is_working
check "a new backup completes" a_new_backup_completes
check "base backups are in the object store" base_backups_are_in_the_object_store
check "wal segments are in the object store" wal_segments_are_in_the_object_store
