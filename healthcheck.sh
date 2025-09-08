#!/usr/bin/env bash
# healthcheck.sh — patched to optionally sanity-check GPU tooling.

set -euo pipefail

: "${IDRAC_HOST:=local}"
: "${ENABLE_GPU_TEMP:=false}"
: "${GPU_BACKEND:=auto}"

# Basic IPMI responsiveness (same spirit as original)
if [[ "${IDRAC_HOST,,}" == "local" ]]; then
  ipmitool -I open sdr >/dev/null 2>&1 || exit 1
else
  : "${IDRAC_USERNAME:=root}"
  : "${IDRAC_PASSWORD:=calvin}"
  ipmitool -I lanplus -H "$IDRAC_HOST" -U "$IDRAC_USERNAME" -P "$IDRAC_PASSWORD" sdr >/dev/null 2>&1 || exit 1
fi

# Optional: GPU tool presence when GPU monitoring enabled
if [[ "${ENABLE_GPU_TEMP,,}" == "true" ]]; then
  case "${GPU_BACKEND}" in
    auto)
      if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits >/dev/null 2>&1 || true
      elif command -v rocm-smi >/dev/null 2>&1; then
        rocm-smi --showtemp >/dev/null 2>&1 || true
      else
        # fall back to sysfs probe
        find /sys/class/drm -type f -path "*/device/hwmon/hwmon*/temp*_input" | head -n1 >/dev/null 2>&1 || true
      fi
      ;;
    nvidia)
      command -v nvidia-smi >/dev/null 2>&1 || true
      ;;
    rocm)
      command -v rocm-smi   >/dev/null 2>&1 || true
      ;;
    sysfs|*)
      # nothing mandatory
      :
      ;;
  esac
fi

exit 0