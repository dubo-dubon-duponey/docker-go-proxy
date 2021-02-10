ARG           BUILDER_BASE=dubodubonduponey/base:builder
ARG           RUNTIME_BASE=dubodubonduponey/base:runtime

#######################
# Extra builder for healthchecker
#######################
# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-healthcheck

ARG           GIT_REPO=github.com/dubo-dubon-duponey/healthcheckers
ARG           GIT_VERSION=51ebf8ca3d255e0c846307bf72740f731e6210c3
ARG           BUILD_TARGET=./cmd/http
ARG           BUILD_OUTPUT=http-health
ARG           BUILD_FLAGS="-s -w"

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION
# hadolint ignore=DL4006
RUN           env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v \
                -ldflags "$BUILD_FLAGS" -o /dist/boot/bin/"$BUILD_OUTPUT" "$BUILD_TARGET"

#######################
# Goello
#######################
# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-goello

ARG           GIT_REPO=github.com/dubo-dubon-duponey/goello
ARG           GIT_VERSION=3799b6035dd5c4d5d1c061259241a9bedda810d6
ARG           BUILD_TARGET=./cmd/server/main.go
ARG           BUILD_OUTPUT=goello-server
ARG           BUILD_FLAGS="-s -w"

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION
# hadolint ignore=DL4006
RUN           env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v \
                -ldflags "$BUILD_FLAGS" -o /dist/boot/bin/"$BUILD_OUTPUT" "$BUILD_TARGET"

#######################
# Caddy
#######################
# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-caddy

# This is 2.3.0
ARG           GIT_REPO=github.com/caddyserver/caddy
ARG           GIT_VERSION=1b453dd4fbea2f3a54362fb4c2115bab85cad1b7
ARG           BUILD_TARGET=./cmd/caddy
ARG           BUILD_OUTPUT=caddy
ARG           BUILD_FLAGS="-s -w"

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone https://$GIT_REPO .
RUN           git checkout $GIT_VERSION
# hadolint ignore=DL4006
RUN           env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v \
                -ldflags "$BUILD_FLAGS" -o /dist/boot/bin/"$BUILD_OUTPUT" "$BUILD_TARGET"

##########################
# Builder custom
##########################
# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-main

# 0.10
ARG           GIT_REPO=github.com/gomods/athens
ARG           GIT_VERSION=408fd74a9c95c019264982f020f6eaf31a1eeabe
ARG           BUILD_TARGET=./cmd/proxy
ARG           BUILD_OUTPUT=athens-proxy
ARG           BUILD_FLAGS="-s -w -X github.com/gomods/athens/pkg/build.version=$BUILD_VERSION -X github.com/gomods/athens/pkg/build.buildDate=$BUILD_CREATED"

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION
# hadolint ignore=DL4006
RUN           env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v \
                -ldflags "$BUILD_FLAGS" -o /dist/boot/bin/"$BUILD_OUTPUT" "$BUILD_TARGET"

# Also need the go runtime
RUN           cp /build/golang/go/bin/go /dist/boot/bin/

#######################
# Builder assembly
#######################
# hadolint ignore=DL3006
FROM          $BUILDER_BASE                                                                                             AS builder

COPY          --from=builder-healthcheck /dist/boot/bin /dist/boot/bin
COPY          --from=builder-goello /dist/boot/bin /dist/boot/bin
COPY          --from=builder-caddy /dist/boot/bin /dist/boot/bin
COPY          --from=builder-main /dist/boot/bin /dist/boot/bin

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot/bin -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;

#######################
# Running image
#######################
# hadolint ignore=DL3006
FROM          $RUNTIME_BASE

USER          root

# Do we really need all that shit? who uses subversion these days?
RUN           apt-get update -qq          && \
              apt-get install -qq --no-install-recommends \
                git=1:2.20.1-2+deb10u3 \
                mercurial=4.8.2-1+deb10u1 \
                git-lfs=2.7.1-1+deb10u1 && \
              apt-get -qq autoremove      && \
              apt-get -qq clean           && \
              rm -rf /var/lib/apt/lists/* && \
              rm -rf /tmp/*               && \
              rm -rf /var/tmp/*

#                bzr=2.7.0+bzr6622-15 \
#                subversion=1.10.4-1+deb10u1 && \

# XXX doesn't work?
# ENV GOROOT=/tmp/go
RUN           ln -s /tmp/go /usr/local/go

USER          dubo-dubon-duponey

COPY          --from=builder --chown=$BUILD_UID:root /dist .

### Front server configuration
# Port to use
ENV           PORT=4443
EXPOSE        4443
# Log verbosity for
ENV           LOG_LEVEL=info
# Domain name to serve
ENV           DOMAIN="go.local"
# Control wether tls is going to be "internal" (eg: self-signed), or alternatively an email address to enable letsencrypt
ENV           TLS="internal"

# Salt and realm in case anything is authenticated
ENV           SALT="eW91IGFyZSBzbyBzbWFydAo="
ENV           REALM="My precious"
# if authenticated, pass along a username and bcrypted password (call the container with the "hash" command to generate one)
ENV           USERNAME=""
ENV           PASSWORD=""

### mDNS broadcasting
# Enable/disable mDNS support
ENV           MDNS_ENABLED=true
# Name is used as a short description for the service
ENV           MDNS_NAME="Fancy Service Name"
# The service will be annonced and reachable at $MDNS_HOST.local
ENV           MDNS_HOST=go
# Type being advertised
ENV           MDNS_TYPE=_http._tcp

# Athens specific config
ENV           GO111MODULE=on
ENV           ATHENS_DISK_STORAGE_ROOT=/tmp/athens
ENV           ATHENS_STORAGE_TYPE=disk

#
VOLUME        /tmp
VOLUME        /certs

# Healthcheck (passthrough caddy->registry)
ENV           HEALTHCHECK_URL=http://127.0.0.1:10042/v2/?healthcheck
# TODO make interval configurable
HEALTHCHECK   --interval=30s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1

