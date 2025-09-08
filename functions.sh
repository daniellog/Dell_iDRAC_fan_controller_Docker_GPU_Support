#!/usr/bin/env bash
# functions.sh — original helpers + GPU-aware additions
# Shell options are set in the main script.

########################################
# Printing helpers
########################################
print_info() {
  local -r MESSAGE="$1"
  printf "[INFO] %s\n" "$MESSAGE"
}

print_warning() {
  local -r WARNING_MESSAGE="$1"
  printf "/!\\ Warning /!\\ %s.\n" "$WARNING_MESSAGE"
}

print_warning_and_exit() {
  local -r WARNING_MESSAGE="$1"
  print_warning "$WARNING_MESSAGE"
  printf "Exiting.\n"
  exit 0
}

print_error() {
  local -r ERROR_MESSAGE="$1"
  printf "/!\\ Error /!\\ %s.\n" "$ERROR_MESSAGE" >&2
}

print_error_and_exit() {
  local -r ERROR_MESSAGE="$1"
  print_error "$ERROR_MESSAGE"
  printf "Exiting.\n" >&2
  exit 1
}

# --- OPTIONAL GPU message wrappers (non-breaking) ---
gpu_print_info()    { print_info    "[GPU] $*"; }
gpu_print_warning() { print_warning "[GPU] $*"; }

########################################
# Fan control profiles (Dell vs user)
########################################
# Requires: IDRAC_LOGIN_STRING, HEXADECIMAL_FAN_SPEED, DECIMAL_FAN_SPEED

# Dell default dynamic fan control (BIOS/auto)
apply_Dell_fan_control_profile() {
  ipmitool -I "$IDRAC_LOGIN_STRING" raw 0x30 0x30 0x01 0x01 >/dev/null
  CURRENT_FAN_CONTROL_PROFILE="Dell default dynamic fan control profile"
}

# User static fan duty (manual %)
apply_user_fan_control_profile() {
  ipmitool -I "$IDRAC_LOGIN_STRING" raw 0x30 0x30 0x01 0x00 >/dev/null
  ipmitool -I "$IDRAC_LOGIN_STRING" raw 0x30 0x30 0x02 0xff "$HEXADECIMAL_FAN_SPEED" >/dev/null
  CURRENT_FAN_CONTROL_PROFILE="User static fan control profile (${DECIMAL_FAN_SPEED}%)"
}

########################################
# Conversions
########################################
# Usage: convert_decimal_value_to_hexadecimal 5 -> "0x05"
convert_decimal_value_to_hexadecimal() {
  local -r DECIMAL_NUMBER="$1"
  printf '0x%02x\n' "$DECIMAL_NUMBER"
}

# Usage: convert_hexadecimal_value_to_decimal 0x05 -> "5"
convert_hexadecimal_value_to_decimal() {
  local -r HEXADECIMAL_NUMBER="$1"
  printf '%d\n' "$HEXADECIMAL_NUMBER"
}

########################################
# Temperature retrieval (CPU/Inlet/Exhaust)
########################################
# Populates: CPU1_TEMPERATURE, CPU2_TEMPERATURE, INLET_TEMPERATURE, EXHAUST_TEMPERATURE
# Args: retrieve_temperatures $IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT $IS_CPU2_TEMPERATURE_SENSOR_PRESENT
retrieve_temperatures() {
  if (( $# != 2 )); then
    print_error "Illegal number of parameters.
Usage: retrieve_temperatures \$IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT \$IS_CPU2_TEMPERATURE_SENSOR_PRESENT"
    return 1
  fi

  local -r IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT="$1"
  local -r IS_CPU2_TEMPERATURE_SENSOR_PRESENT="$2"

  # Raw IPMI SDR read (temperature lines only)
  local DATA
  DATA="$(ipmitool -I "$IDRAC_LOGIN_STRING" sdr type temperature 2>/dev/null | grep -i 'degrees' || true)"

  # --- CPU temps ---
  # Many Dell SDRs show CPU sensors with IDs like "Temp", "CPUx Temp", or numeric sensor numbers (3.x).
  # We try common patterns; fall back to "any number preceding 'degrees C'".
  local CPU_LINES CPU_NUMS
  CPU_LINES="$(printf '%s\n' "$DATA" | grep -Ei 'CPU|Proc|Processor|Temp\s*CPU' || true)"
  if [[ -z "$CPU_LINES" ]]; then
    CPU_LINES="$DATA"
  fi
  # Extract all integers preceding 'degrees C'
  CPU_NUMS="$(printf '%s\n' "$CPU_LINES" | grep -Eo '[0-9]+ degrees C' | awk '{print $1}' || true)"

  # CPU indices are environment-dependent; default to first as CPU1, second as CPU2 (if present).
  CPU1_TEMPERATURE="$(printf '%s\n' "$CPU_NUMS" | sed -n '1p' || true)"
  CPU2_TEMPERATURE="$(printf '%s\n' "$CPU_NUMS" | sed -n '2p' || true)"

  # If CPU2 sensor not present, set to "-"
  if [[ -z "$CPU2_TEMPERATURE" || "$IS_CPU2_TEMPERATURE_SENSOR_PRESENT" != "true" ]]; then
    CPU2_TEMPERATURE="-"
  fi
  [[ -z "$CPU1_TEMPERATURE" ]] && CPU1_TEMPERATURE="-"

  # --- Inlet temp (take last match to prefer the most specific) ---
  INLET_TEMPERATURE="$(printf '%s\n' "$DATA" | grep -i 'Inlet' | grep -Eo '[0-9]+(?= degrees C)' | tail -1 || true)"
  [[ -z "$INLET_TEMPERATURE" ]] && INLET_TEMPERATURE="-"

  # --- Exhaust temp (optional) ---
  if [[ "$IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT" == "true" ]]; then
    EXHAUST_TEMPERATURE="$(printf '%s\n' "$DATA" | grep -i 'Exhaust' | grep -Eo '[0-9]+(?= degrees C)' | tail -1 || true)"
    [[ -z "$EXHAUST_TEMPERATURE" ]] && EXHAUST_TEMPERATURE="-"
  else
    EXHAUST_TEMPERATURE="-"
  fi
}

########################################
# Overheating flags (CPU)
########################################
# Populates: CPU1_OVERHEATING, CPU2_OVERHEATING  (values: "true"|"false")
# Requires: CPU_TEMPERATURE_THRESHOLD, CPU1_TEMPERATURE, CPU2_TEMPERATURE
update_overheating_flags() {
  CPU1_OVERHEATING="false"
  CPU2_OVERHEATING="false"

  if [[ "$CPU1_TEMPERATURE" =~ ^[0-9]+$ ]] && (( CPU1_TEMPERATURE > CPU_TEMPERATURE_THRESHOLD )); then
    CPU1_OVERHEATING="true"
  fi
  if [[ "$CPU2_TEMPERATURE" =~ ^[0-9]+$ ]] && (( CPU2_TEMPERATURE > CPU_TEMPERATURE_THRESHOLD )); then
    CPU2_OVERHEATING="true"
  fi
}

########################################
# GPU overheating helper (optional)
########################################
# Populates: GPU_OVERHEATING ("true"|"false"), CURRENT_GPU_MAX_TEMP (numeric or "")
# Reads: ENABLE_GPU_TEMP, GPU_TEMPERATURE_THRESHOLD, GPU_BACKEND, GPU_INDEX_FILTER
# Requires (optional): get_max_gpu_temp function (from gpu_temp.sh). If missing, fails safe.
compute_gpu_overheating() {
  GPU_OVERHEATING="false"
  CURRENT_GPU_MAX_TEMP=""

  # Only act if explicitly enabled
  if [[ "${ENABLE_GPU_TEMP,,}" != "true" ]]; then
    return 0
  fi

  # Ensure threshold is sensible
  : "${GPU_TEMPERATURE_THRESHOLD:=70}"

  if command -v get_max_gpu_temp >/dev/null 2>&1; then
    CURRENT_GPU_MAX_TEMP="$(get_max_gpu_temp || true)"
  else
    gpu_print_warning "helper not loaded (gpu_temp.sh); skipping GPU temps."
    return 0
  fi

  if [[ -n "$CURRENT_GPU_MAX_TEMP" && "$CURRENT_GPU_MAX_TEMP" =~ ^[0-9]+$ ]]; then
    gpu_print_info "max temp ${CURRENT_GPU_MAX_TEMP}°C (backend=${GPU_BACKEND:-auto} filter='${GPU_INDEX_FILTER:-}')"
    if (( CURRENT_GPU_MAX_TEMP >= GPU_TEMPERATURE_THRESHOLD )); then
      GPU_OVERHEATING="true"
    fi
  else
    gpu_print_warning "temperatures not available (backend=${GPU_BACKEND:-auto})."
  fi
}

########################################
# Third-party PCIe cooling response (Gen13 and older)
########################################
# /!\ Use ONLY for Gen13 and older servers /!\
enable_third_party_PCIe_card_Dell_default_cooling_response() {
  ipmitool -I "$IDRAC_LOGIN_STRING" raw 0x30 0xce 0x00 0x16 0x05 0x00 0x00 0x00 0x05 0x00 0x00 0x00 0x00 >/dev/null
}

# /!\ Use ONLY for Gen13 and older servers /!\
disable_third_party_PCIe_card_Dell_default_cooling_response() {
  ipmitool -I "$IDRAC_LOGIN_STRING" raw 0x30 0xce 0x00 0x16 0x05 0x00 0x00 0x00 0x05 0x00 0x01 0x00 0x00 >/dev/null
}

# Optional status reader (commented: keep original behavior)
# is_third_party_PCIe_card_Dell_default_cooling_response_disabled() {
#   local THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE
#   THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE="$(ipmitool -I "$IDRAC_LOGIN_STRING" raw 0x30 0xce 0x01 0x16 0x05 0x00 0x00 0x00)"
#   if   [[ "$THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE" == "16 05 00 00 00 05 00 01 00 00" ]]; then return 0
#   elif [[ "$THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE" == "16 05 00 00 00 05 00 00 00 00" ]]; then return 1
#   else print_error "Unexpected output: $THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE"; return 2; fi
# }

########################################
# Exit handling
########################################
# Requires: KEEP_THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE_STATE_ON_EXIT, and the *disable* might have been applied at startup.
graceful_exit() {
  apply_Dell_fan_control_profile

  if [[ "${KEEP_THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE_STATE_ON_EXIT,,}" != "true" ]]; then
    enable_third_party_PCIe_card_Dell_default_cooling_response
  fi

  print_warning_and_exit "Container stopped, Dell default dynamic fan control profile applied for safety"
}

########################################
# Server model (for logs / debugging)
########################################
# Populates: SERVER_MANUFACTURER, SERVER_MODEL
get_Dell_server_model() {
  local IPMI_FRU_CONTENT
  IPMI_FRU_CONTENT="$(ipmitool -I "$IDRAC_LOGIN_STRING" fru 2>/dev/null || true)"  # FRU = Field Replaceable Unit

  SERVER_MANUFACTURER="$(printf '%s\n' "$IPMI_FRU_CONTENT" | grep -E 'Product Manufacturer' | awk -F ': ' '{print $2}')"
  SERVER_MODEL="$(printf '%s\n' "$IPMI_FRU_CONTENT" | grep -E 'Product Name' | awk -F ': ' '{print $2}')"

  # Fallbacks for sparse FRU data
  if [[ -z "$SERVER_MANUFACTURER" ]]; then
    SERVER_MANUFACTURER="$(printf '%s\n' "$IPMI_FRU_CONTENT" | tr -s ' ' | grep -E 'Board Mfg :' | awk -F ': ' '{print $2}')"
  fi
  if [[ -z "$SERVER_MODEL" ]]; then
    SERVER_MODEL="$(printf '%s\n' "$IPMI_FRU_CONTENT" | tr -s ' ' | grep -E 'Board Product :' | awk -F ': ' '{print $2}')"
  fi

  if [[ -n "$SERVER_MANUFACTURER" || -n "$SERVER_MODEL" ]]; then
    print_info "Server: ${SERVER_MANUFACTURER:-Unknown} ${SERVER_MODEL:-Unknown}"
  fi
}