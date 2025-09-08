FROM ubuntu:latest

ENV DEBIAN_FRONTEND=noninteractive

# Minimal deps; note: use gawk (awk is virtual)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ipmitool ca-certificates bash coreutils grep sed gawk findutils && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
ADD functions.sh /app/functions.sh
ADD healthcheck.sh /app/healthcheck.sh
ADD Dell_iDRAC_fan_controller.sh /app/Dell_iDRAC_fan_controller.sh
# If you added GPU helper:
# ADD gpu_temp.sh /app/gpu_temp.sh

RUN chmod 0755 /app/functions.sh /app/healthcheck.sh /app/Dell_iDRAC_fan_controller.sh

# Defaults (avoid secrets here!)
ENV IDRAC_HOST=local \
    IDRAC_USERNAME=root \
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

# Don’t bake passwords; pass at runtime:
#   docker run -e IDRAC_PASSWORD=... ...
# (If you *must*, use ARG and build-time secrets, not ENV.)

HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD /app/healthcheck.sh
ENTRYPOINT ["/app/Dell_iDRAC_fan_controller.sh"]