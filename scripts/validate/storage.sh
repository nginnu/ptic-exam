object_store_volume_is_bound() {
  [ "$(k -n rustfs get pvc data-rustfs-0 -o jsonpath='{.status.phase}')" = "Bound" ] &&
    [ "$(k -n rustfs get pvc data-rustfs-0 -o jsonpath='{.spec.storageClassName}')" = "hostpath" ]
}

object_store_is_running() {
  [ "$(k -n rustfs get pod rustfs-0 -o jsonpath='{.status.phase}')" = "Running" ]
}

object_store_survives_a_round_trip() {
  local access secret
  access="$(k -n rustfs get secret rustfs -o jsonpath='{.data.accessKey}' | base64 -d)"
  secret="$(k -n rustfs get secret rustfs -o jsonpath='{.data.secretKey}' | base64 -d)"
  [ -n "${access}" ] && [ -n "${secret}" ] || return 1
  run_pod rustfs amazon/aws-cli:2.32.9 \
    --env=AWS_ACCESS_KEY_ID="${access}" \
    --env=AWS_SECRET_ACCESS_KEY="${secret}" \
    --env=AWS_DEFAULT_REGION=us-east-1 \
    --command -- sh -c '
      E=http://rustfs:9000
      B=ptic-validate
      echo ptic-probe > /tmp/a
      aws --endpoint-url $E s3 mb s3://$B >/dev/null 2>&1
      aws --endpoint-url $E s3 cp /tmp/a s3://$B/a >/dev/null 2>&1 &&
      aws --endpoint-url $E s3 cp s3://$B/a /tmp/b >/dev/null 2>&1 &&
      [ "$(cat /tmp/b)" = ptic-probe ] &&
      aws --endpoint-url $E s3 rb s3://$B --force >/dev/null 2>&1 &&
      echo ROUNDTRIP_OK' | grep -q ROUNDTRIP_OK
}

check "object store volume bound on hostpath" object_store_volume_is_bound
check "object store running" object_store_is_running
check "object store survives a write and read back" object_store_survives_a_round_trip
