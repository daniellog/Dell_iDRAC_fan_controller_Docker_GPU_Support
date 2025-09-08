FROM ubuntu:latest

# Reduce apt noise
ENV DEBIAN_FRONTEND=noninteractive

# Minimal runtime deps; add jq/rocm-smi only if you need them
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ipmitool ca-certificates bash coreutils grep sed awk findutils && \
    rm -rf /var/lib/apt/lists/*

# App files
WORKDIR /app
ADD functions.sh /app/functions.sh
ADD healthcheck.sh /app/healthcheck.sh
ADD Dell_iDRAC_fan_controller.sh /app/Dell_iDRAC_fan_controller.sh
# If you created the GPU helper, include it:
# ADD gpu_temp.sh /app/gpu_temp.sh

# Make scripts executable (no 0777)
RUN chmod 0755 /app/functions.sh /app/healthcheck.sh /app/Dell_iDRAC_fan_controller.sh

# Defaults (key=value format)
# Keep both styles for compatibility: IDRAC_HOST (preferred) and IDRAC_LOGIN_STRING (legacy)
ENV IDRAC_HOST=local \
    IDRAC_USERNAME=root \
    IDRAC_PASSWORD=calvin \
    IDRAC_LOGIN_STRING=open \
    FAN_SPEED=5 \
    CPU_TEMPERATURE_THRESHOLD=50 \
    CHECK_INTERVAL=60 \
    DISABLE_THIRD_PARTY_PCIE_CARD_DELL_DEFAULT_COOLING_RESPONSE=false \
    KEEP_THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE_STATE_ON_EXIT=false \
    ENABLE_GPU_TEMP=false \
    GPU_TEMPERATURE_THRESHOLD=70 \
    GPU_BACKEND=auto \
    GPU_INDEX_FILTER=

# Optional: container health
HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD /app/healthcheck.sh

# Run the controller
ENTRYPOINT ["/app/Dell_iDRAC_fan_controller.sh"]