#!/usr/bin/env bash
# Dell_iDRAC_fan_controller.sh
# Patched to (optionally) include GPU temperatures in control logic.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# --- Existing repo helpers ---
# shellcheck source=functions.sh
. "${SCRIPT_DIR}/functions.sh"

# --- New GPU helper (added file) ---
if [[ -f "${SCRIPT_DIR}/gpu_temp.sh" ]]; then
  # shellcheck source=gpu_temp.sh
  . "${SCRIPT_DIR}/gpu_temp.sh"
fi

########################################
# Environment (originals preserved)
########################################
FAN_SPEED="${FAN_SPEED:-5}"
IDRAC_HOST="${IDRAC_HOST:-local}"               # "local" uses /dev/ipmi0
IDRAC_USERNAME="${IDRAC_USERNAME:-root}"
IDRAC_PASSWORD="${IDRAC_PASSWORD:-calvin}"
CHECK_INTERVAL="${CHECK_INTERVAL:-60}"
CPU_TEMPERATURE_THRESHOLD="${CPU_TEMPERATURE_THRESHOLD:-50}"

DISABLE_THIRD_PARTY_PCIE_CARD_DELL_DEFAULT_COOLING_RESPONSE="${DISABLE_THIRD_PARTY_PCIE_CARD_DELL_DEFAULT_COOLING_RESPONSE:-false}"
KEEP_THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE_STATE_ON_EXIT="${KEEP_THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE_STATE_ON_EXIT:-false}"

# --- New: GPU options (all optional) ---
ENABLE_GPU_TEMP="${ENABLE_GPU_TEMP:-false}"               # "true" to include GPU temps
GPU_TEMPERATURE_THRESHOLD="${GPU_TEMPERATURE_THRESHOLD:-70}"
GPU_BACKEND="${GPU_BACKEND:-auto}"                        # auto|nvidia|rocm|sysfs
GPU_INDEX_FILTER="${GPU_INDEX_FILTER:-}"                  # e.g. "0,2" ; blank = all visible

########################################
# Startup banner (using existing print_* helpers)
########################################
print_info "Starting Dell iDRAC fan controller (GPU-aware patch)"
print_info "Host=${IDRAC_HOST}  Fan=${FAN_SPEED}%  CPU_Thresh=${CPU_TEMPERATURE_THRESHOLD}°C  Interval=${CHECK_INTERVAL}s"
print_info "EnableGPU=${ENABLE_GPU_TEMP}  GPU_Thresh=${GPU_TEMPERATURE_THRESHOLD}°C  Backend=${GPU_BACKEND}  Filter='${GPU_INDEX_FILTER}'"

# Validate local IPMI if requested
if [[ "${IDRAC_HOST,,}" == "local" ]]; then
  if [[ ! -e /dev/ipmi0 ]]; then
    print_error "/dev/ipmi0 not present; set IDRAC_HOST to your iDRAC IP for IPMI over LAN."
    exit 1
  fi
fi

# Get server model (best-effort)
get_Dell_server_model || true

# Optionally adjust Dell cooling response at start
if [[ "${DISABLE_THIRD_PARTY_PCIE_CARD_DELL_DEFAULT_COOLING_RESPONSE,,}" == "true" ]]; then
  disable_third_party_pcie_card_Dell_default_cooling_response || true
fi

# Always return to BIOS on exit
graceful_exit_trap() {
  print_warning "Exiting: restoring BIOS fan control."
  apply_Dell_fan_control_profile || true
  if [[ "${KEEP_THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE_STATE_ON_EXIT,,}" != "true" ]] \
     && [[ "${DISABLE_THIRD_PARTY_PCIE_CARD_DELL_DEFAULT_COOLING_RESPONSE,,}" == "true" ]]; then
    enable_third_party_pcie_card_Dell_default_cooling_response || true
  fi
}
trap graceful_exit_trap EXIT INT TERM

########################################
# Main control loop (kept original flow)
########################################
while true; do
  sleep "${CHECK_INTERVAL}"

  # Retrieve all usual temperatures (repo function; populates globals, prints nicely)
  retrieve_temperatures || true

  # The repo already computes overheating booleans for CPUs (if present)
  # We add an optional GPU overheating boolean.
  GPU_OVERHEATING=false
  CURRENT_GPU_MAX_TEMP=""

  if [[ "${ENABLE_GPU_TEMP,,}" == "true" ]]; then
    if command -v get_max_gpu_temp >/dev/null 2>&1; then
      CURRENT_GPU_MAX_TEMP="$(get_max_gpu_temp || true)"
      if [[ -n "$CURRENT_GPU_MAX_TEMP" && "$CURRENT_GPU_MAX_TEMP" =~ ^[0-9]+$ ]]; then
        print_info "GPU max temp: ${CURRENT_GPU_MAX_TEMP}°C"
        if (( CURRENT_GPU_MAX_TEMP >= GPU_TEMPERATURE_THRESHOLD )); then
          GPU_OVERHEATING=true
        fi
      else
        print_warning "GPU temps not available (backend=${GPU_BACKEND})."
      fi
    else
      print_warning "GPU helper not loaded; skipping GPU temps."
    fi
  fi

  # Decide profile:
  # - If CPU1_OVERHEATING or CPU2_OVERHEATING (set by repo), or GPU_OVERHEATING => BIOS
  # - Else => manual fan at FAN_SPEED
  if [[ "${CPU1_OVERHEATING:-false}" == "true" ]] \
     || [[ "${CPU2_OVERHEATING:-false}" == "true" ]] \
     || [[ "${GPU_OVERHEATING}" == "true" ]]; then
    print_warning "High temperature detected (CPU1=${CPU1_TEMPERATURE:-NA}°C CPU2=${CPU2_TEMPERATURE:-NA}°C GPU=${CURRENT_GPU_MAX_TEMP:-NA}°C) -> BIOS control"
    apply_Dell_fan_control_profile || true
  else
    print_info "Temps OK (CPU1=${CPU1_TEMPERATURE:-NA}°C CPU2=${CPU2_TEMPERATURE:-NA}°C GPU=${CURRENT_GPU_MAX_TEMP:-NA}°C) -> manual ${FAN_SPEED}%"
    apply_user_fan_control_profile "${FAN_SPEED}" || true
  fi
done