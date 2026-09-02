# syntax=docker/dockerfile:1

ARG SING_BOX_VERSION=v1.13.14
ARG CLOUDFLARED_VERSION=2026.8.3


# ==================================================
# sing-box
# ==================================================

FROM ghcr.io/sagernet/sing-box:${SING_BOX_VERSION} AS sing-box


# ==================================================
# cloudflared
# ==================================================

FROM cloudflare/cloudflared:${CLOUDFLARED_VERSION} AS cloudflared


# ==================================================
# Runtime
# ==================================================

FROM alpine:3.21

RUN apk add --no-cache \
    ca-certificates \
    gettext \
    tini \
    procps \
    jq \
    iproute2


COPY --from=sing-box \
    /usr/local/bin/sing-box \
    /usr/local/bin/sing-box


COPY --from=cloudflared \
    /usr/local/bin/cloudflared \
    /usr/local/bin/cloudflared


WORKDIR /app


COPY config.json.template \
    /app/config.json.template


COPY start.sh \
    /app/start.sh


COPY healthcheck.sh \
    /app/healthcheck.sh


RUN chmod +x \
    /app/start.sh \
    /app/healthcheck.sh


RUN mkdir -p /data


HEALTHCHECK \
    --interval=30s \
    --timeout=10s \
    --start-period=30s \
    --retries=3 \
    CMD ["/app/healthcheck.sh"]


ENTRYPOINT ["/sbin/tini", "--", "/app/start.sh"]
