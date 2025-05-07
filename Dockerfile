FROM ubuntu:noble-20250415.1@sha256:6015f66923d7afbc53558d7ccffd325d43b4e249f41a6e93eef074c9505d2233

# See https://github.com/just-containers/s6-overlay/releases
ENV S6_OVERLAY_VERSION=3.2.1.0

# See https://github.com/grafana/grafana/releases
ENV GRAFANA_VERSION=11.6.1

# See https://github.com/VictoriaMetrics/VictoriaMetrics/releases
ENV VICTORIA_METRICS_VERSION=1.116.0

# See https://github.com/grafana/tempo/releases
ENV TEMPO_VERSION=2.7.2

# See https://github.com/grafana/loki/releases
ENV LOKI_VERSION=3.5.0

# See https://github.com/open-telemetry/opentelemetry-collector-releases/releases
ENV OPENTELEMETRY_COLLECTOR_VERSION=0.124.0

# This arg is set by Docker: https://docs.docker.com/extensions/extensions-sdk/extensions/multi-arch/
ARG TARGETARCH
ENV TARGETARCH=${TARGETARCH}

RUN apt-get update && apt-get install -y curl python3 python3-psutil unzip xz-utils

WORKDIR /stack

# Install s6-overlay: https://github.com/just-containers/s6-overlay
# We first map TARGETARCH to s6-overlay's architecture naming conventions based on gcc's:
# https://github.com/just-containers/s6-overlay#which-architecture-to-use-depending-on-your-targetarch
RUN bash -c 'if [ "$TARGETARCH" == "amd64" ]; then \
        S6_ARCH="x86_64"; \
    elif [ "$TARGETARCH" == "arm64" ]; then \
        S6_ARCH="aarch64"; \
    elif [ "$TARGETARCH" == "arm/v7" ]; then \
        S6_ARCH="arm"; \
    elif [ "$TARGETARCH" == "arm/v6" ]; then \
        S6_ARCH="armhf"; \
    elif [ "$TARGETARCH" == "386" ]; then \
        S6_ARCH="i686"; \
    else \
        S6_ARCH="$TARGETARCH"; \
    fi; \
    curl -sOL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" && \
    curl -sOL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" && \
    tar -C / -Jxpf s6-overlay-noarch.tar.xz && \
    tar -C / -Jxpf "s6-overlay-${S6_ARCH}.tar.xz" && \
    rm s6-overlay-noarch.tar.xz && \
    rm "s6-overlay-${S6_ARCH}.tar.xz"'
ENV S6_KEEP_ENV=1
ENTRYPOINT ["/init"]

# Install Grafana
RUN bash -c 'ARCHIVE="grafana-${GRAFANA_VERSION}.linux-${TARGETARCH}.tar.gz" && \
    curl -sOL "https://dl.grafana.com/oss/release/${ARCHIVE}" && \
    tar xfz "${ARCHIVE}" && \
    rm "${ARCHIVE}" && \
    mv "grafana-v${GRAFANA_VERSION}" grafana/ && \
    cd grafana && \
    ./bin/grafana cli --pluginsDir /data/grafana/plugins plugins install grafana-exploretraces-app 0.2.9 && \
    ./bin/grafana cli --pluginsDir /data/grafana/plugins plugins install grafana-lokiexplore-app 1.0.14 && \
    ./bin/grafana cli --pluginsDir /data/grafana/plugins plugins install grafana-clock-panel 2.1.8 && \
    ./bin/grafana cli --pluginsDir /data/grafana/plugins plugins install vonage-status-panel 2.0.2 && \
    ./bin/grafana cli --pluginsDir /data/grafana/plugins plugins install grafana-polystat-panel 2.1.14 && \
    ./bin/grafana cli --pluginsDir /data/grafana/plugins plugins install marcusolsson-treemap-panel 2.0.1'

# Install VictoriaMetrics
RUN bash -c 'ARCHIVE="victoria-metrics-linux-${TARGETARCH}-v${VICTORIA_METRICS_VERSION}.tar.gz" && \
    curl -sOL "https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/v${VICTORIA_METRICS_VERSION}/${ARCHIVE}" && \
    mkdir victoria-metrics && \
    tar xfz "${ARCHIVE}" -C victoria-metrics/ && \
    rm "${ARCHIVE}"'

# Install Tempo
RUN bash -c 'ARCHIVE="tempo_${TEMPO_VERSION}_linux_${TARGETARCH}.tar.gz" && \
    curl -sOL "https://github.com/grafana/tempo/releases/download/v${TEMPO_VERSION}/${ARCHIVE}" && \
    mkdir tempo && \
    tar xfz "${ARCHIVE}" -C tempo/ && \
    rm "${ARCHIVE}"'

# Install Loki
RUN bash -c 'ARCHIVE="loki-linux-${TARGETARCH}.zip" && \
    curl -sOL "https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/${ARCHIVE}" && \
    mkdir loki && \
    unzip "${ARCHIVE}" -d loki/ && \
    mv "loki/loki-linux-${TARGETARCH}" loki/loki && \
    rm "${ARCHIVE}"'

# Install the OpenTelemetry Collector
RUN bash -c 'ARCHIVE="otelcol-contrib_${OPENTELEMETRY_COLLECTOR_VERSION}_linux_${TARGETARCH}.tar.gz" && \
    curl -sOL "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${OPENTELEMETRY_COLLECTOR_VERSION}/${ARCHIVE}" && \
    mkdir otelcol-contrib && \
    tar xfz "${ARCHIVE}" -C otelcol-contrib/ && \
    rm "${ARCHIVE}"'

# Install OpenTelemetry Stack exporter
COPY src/opentelemetry_stack_exporter.py /stack/opentelemetry-stack-exporter/main.py

# Copy component configuration
COPY src/config/grafana-config.ini /stack/grafana/conf/custom.ini
COPY src/config/grafana-datasources.yaml /stack/grafana/conf/provisioning/datasources/datasources.yaml
COPY src/config/grafana-dashboards.yaml /stack/grafana/conf/provisioning/dashboards/dashboards.yaml
COPY src/config/grafana-opentelemetry-stack-overview-dashboard.json /provisioning/grafana/dashboards/opentelemetry-stack-overview-dashboard.json
COPY src/config/tempo-config.yaml /stack/tempo/config.yaml
COPY src/config/loki-config.yaml /stack/loki/config.yaml
COPY src/config/otelcol-contrib-config.yaml /stack/otelcol-contrib/config.yaml

# Copy s6 configuration
COPY src/s6 /etc/s6-overlay/s6-rc.d

# Ports that should be exposed
EXPOSE 3000
EXPOSE 4317
EXPOSE 4318
