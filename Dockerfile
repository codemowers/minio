# -------------------------
#  Build stage
# -------------------------
FROM --platform=$BUILDPLATFORM golang:1.22-alpine AS build

ARG MINIO_VERSION=master
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT

ENV CGO_ENABLED=0

RUN apk add --no-cache git ca-certificates build-base bash

WORKDIR /src
RUN git clone --depth 1 --branch "${MINIO_VERSION}" https://github.com/minio/minio.git .

# Build for the requested target; set GOARM from variant if needed
RUN set -eux; \
    if [ "${TARGETARCH}" = "arm" ]; then \
      case "${TARGETVARIANT}" in v6) export GOARM=6 ;; v7) export GOARM=7 ;; esac; \
    fi; \
    export GOOS="${TARGETOS}" GOARCH="${TARGETARCH}"; \
    COMMIT_ID="$(git rev-parse --short HEAD)"; \
    VERSION="$(git describe --tags --always || echo "${COMMIT_ID}")"; \
    go build -trimpath \
      -ldflags "-s -w \
        -X github.com/minio/minio/cmd.Version=${VERSION} \
        -X github.com/minio/minio/cmd.CommitID=${COMMIT_ID}" \
      -o /out/minio ./cmd/

# -------------------------
#  Runtime stage
# -------------------------
FROM alpine:3.20

# Minimal runtime deps
RUN apk add --no-cache ca-certificates tzdata wget

# Create writable dirs and make them UID-agnostic:
# - chgrp to 0 (root group)
# - grant group same perms as owner (g=u)
# - this matches OpenShift's random UID (supplemental GID 0) and Docker --user <uid>
RUN set -eux; \
    mkdir -p /data /config; \
    chgrp -R 0 /data /config /usr/local/bin; \
    chmod -R g=u /data /config /usr/local/bin

COPY --from=build /out/minio /usr/local/bin/minio

VOLUME ["/data", "/config"]
EXPOSE 9000 9001

# Healthcheck (optional)
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD wget -qO- http://127.0.0.1:9000/minio/health/ready || exit 1

# Do NOT pin USER here → truly UID-agnostic.
# You can run with any UID, e.g.:
#   docker run --user 10000:0 ...
# Or let OpenShift inject a random UID with GID 0.
ENTRYPOINT ["minio"]
CMD ["server", "/data", "--console-address", ":9001", "--config-dir", "/config"]
