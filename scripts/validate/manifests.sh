overlay_builds() {
  build_overlay "$1" >/dev/null
}

check "dev overlay builds" overlay_builds dev
check "staging overlay builds" overlay_builds staging
check "prod overlay builds" overlay_builds prod
