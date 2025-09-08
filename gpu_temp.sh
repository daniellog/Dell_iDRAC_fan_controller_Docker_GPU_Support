#!/usr/bin/env bash
# gpu_temp.sh — helper to read max GPU temperature (°C) from inside container.
# Backends: nvidia (nvidia-smi), rocm (rocm-smi), sysfs (drm/hwmon).

set -euo pipefail

get_max_gpu_temp() {
  local backend="${GPU_BACKEND:-auto}"
  local idx_filter="${GPU_INDEX_FILTER:-}"
  local -a temps=()

  # Autodetect
  if [[ "$backend" == "auto" ]]; then
    if command -v nvidia-smi >/dev/null 2>&1; then
      backend="nvidia"
    elif command -v rocm-smi >/dev/null 2>&1; then
      backend="rocm"
    else
      backend="sysfs"
    fi
  fi

  case "$backend" in
    nvidia)
      local q="--query-gpu=temperature.gpu --format=csv,noheader,nounits"
      if [[ -n "$idx_filter" ]]; then
        IFS=',' read -r -a want <<< "$idx_filter"
        for i in "${want[@]}"; do
          local t
          t="$(nvidia-smi -i "$i" $q 2>/dev/null | head -n1 || true)"
          [[ "$t" =~ ^[0-9]+$ ]] && temps+=("$t")
        done
      else
        while IFS= read -r line; do
          [[ "$line" =~ ^[0-9]+$ ]] && temps+=("$line")
        done < <(nvidia-smi $q 2>/dev/null || true)
      fi
      ;;
    rocm)
      local lines
      lines="$(rocm-smi --showtemp 2>/dev/null || true)"
      if [[ -n "$idx_filter" ]]; then
        IFS=',' read -r -a want <<< "$idx_filter"
        for i in "${want[@]}"; do
          local t
          t="$(grep -E "GPU\[$i\].*:[[:space:]]*[0-9]+(\.[0-9]+)?c" <<<"$lines" | head -n1 | sed -E 's/.*:\s*([0-9]+).*/\1/' || true)"
          [[ "$t" =~ ^[0-9]+$ ]] && temps+=("$t")
        done
      else
        while IFS= read -r t; do
          [[ "$t" =~ ^[0-9]+$ ]] && temps+=("$t")
        done < <(grep -Eo "[[:space:]]([0-9]+)(\.[0-9]+)?c" <<<"$lines" | sed -E 's/[^0-9]*([0-9]+).*/\1/')
      fi
      ;;
    sysfs)
      # Read millidegree temps exposed under DRM/HWMon and convert to °C
      while IFS= read -r p; do
        if [[ -n "$idx_filter" ]]; then
          IFS=',' read -r -a want <<< "$idx_filter"
          if [[ "$p" =~ /card([0-9]+)/ ]]; then
            local n="${BASH_REMATCH[1]}"
            if printf ',%s,' "${want[*]}" | grep -q ",$n,"; then
              local m
              m="$(cat "$p" 2>/dev/null || true)"
              [[ "$m" =~ ^[0-9]+$ ]] && temps+=("$(( m/1000 ))")
            fi
          fi
        else
          local m
          m="$(cat "$p" 2>/dev/null || true)"
          [[ "$m" =~ ^[0-9]+$ ]] && temps+=("$(( m/1000 ))")
        fi
      done < <(find /sys/class/drm -type f -path "*/device/hwmon/hwmon*/temp*_input" 2>/dev/null || true)
      ;;
    *)
      # Unknown backend
      ;;
  esac

  if (( ${#temps[@]} == 0 )); then
    echo ""
    return 0
  fi

  local max="${temps[0]}"
  for t in "${temps[@]}"; do
    (( t > max )) && max="$t"
  done
  echo "$max"
}