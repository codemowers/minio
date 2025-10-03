FROM golang:1.24-alpine AS build
ARG MINIO_VERSION=master
ENV GOTOOLCHAIN=auto
ENV CGO_ENABLED=0
RUN apk add --no-cache git ca-certificates build-base bash
WORKDIR /src
RUN git clone --depth 1 --branch "${MINIO_VERSION}" https://github.com/minio/minio.git .
RUN set -eux; \
    COMMIT_ID="$(git rev-parse --short HEAD)"; \
    VERSION="$(git describe --tags --always || echo "${COMMIT_ID}")"; \
    go build -trimpath \
      -ldflags "-s -w \
        -X github.com/minio/minio/cmd.Version=${VERSION} \
        -X github.com/minio/minio/cmd.CommitID=${COMMIT_ID}" \
      -o /out/minio ./cmd/

FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata wget
COPY --from=build --chmod=0755 /out/minio /usr/local/bin/minio
VOLUME ["/data", "/config"]
ENTRYPOINT ["minio"]
CMD ["server", "/data", "--console-address", ":9001", "--config-dir", "/config"]
