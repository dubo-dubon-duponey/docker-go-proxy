ARG           FROM_IMAGE_BUILDER=ghcr.io/dubo-dubon-duponey/base:builder-bullseye-2021-06-01@sha256:e3e3210201f6b63230d111fc0add56d4a7b384c18039bbfed72b7edac7658040
ARG           FROM_IMAGE_RUNTIME=ghcr.io/dubo-dubon-duponey/base:runtime-bullseye-2021-06-01@sha256:163b9308a142430f6b3d6f37ff84de26943ef9fc0b2c283df4c2c8e5eedadffc
ARG           FROM_IMAGE_TOOLS=builder-tools-local

#######################
# Extra builder for healthchecker
#######################
FROM          --platform=$BUILDPLATFORM $FROM_IMAGE_BUILDER                                                             AS builder-healthcheck

ARG           GIT_REPO=github.com/dubo-dubon-duponey/healthcheckers
ARG           GIT_VERSION=51ebf8c
ARG           GIT_COMMIT=51ebf8ca3d255e0c846307bf72740f731e6210c3
ARG           GO_BUILD_SOURCE=./cmd/http
ARG           GO_BUILD_OUTPUT=http-health
ARG           GO_LD_FLAGS="-s -w"
ARG           GO_TAGS="netgo osusergo"

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone --recurse-submodules git://"$GIT_REPO" . && git checkout "$GIT_COMMIT"
ARG           GOOS="$TARGETOS"
ARG           GOARCH="$TARGETARCH"

# hadolint ignore=SC2046
RUN           env GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)" go build -trimpath $(if [ "$CGO_ENABLED" = 1 ]; then printf "%s" "-buildmode pie"; fi) \
                -ldflags "$GO_LD_FLAGS" -tags "$GO_TAGS" -o /dist/boot/bin/"$GO_BUILD_OUTPUT" "$GO_BUILD_SOURCE"

#######################
# Goello
#######################
FROM          --platform=$BUILDPLATFORM $FROM_IMAGE_BUILDER                                                             AS builder-goello

ARG           GIT_REPO=github.com/dubo-dubon-duponey/goello
ARG           GIT_VERSION=7ce1fb5
ARG           GIT_COMMIT=7ce1fb5d9c739128d2644fbc1968b11efcb96ca2
ARG           GO_BUILD_SOURCE=./cmd/server
ARG           GO_BUILD_OUTPUT=goello-server
ARG           GO_LD_FLAGS="-s -w"
ARG           GO_TAGS="netgo osusergo"

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone --recurse-submodules git://"$GIT_REPO" . && git checkout "$GIT_COMMIT"
ARG           GOOS="$TARGETOS"
ARG           GOARCH="$TARGETARCH"

# hadolint ignore=SC2046
RUN           env GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)" go build -trimpath $(if [ "$CGO_ENABLED" = 1 ]; then printf "%s" "-buildmode pie"; fi) \
                -ldflags "$GO_LD_FLAGS" -tags "$GO_TAGS" -o /dist/boot/bin/"$GO_BUILD_OUTPUT" "$GO_BUILD_SOURCE"

#######################
# Caddy
#######################
FROM          --platform=$BUILDPLATFORM $FROM_IMAGE_BUILDER                                                             AS builder-caddy

# This is 2.4.0
ARG           GIT_REPO=github.com/caddyserver/caddy
ARG           GIT_VERSION=v2.4.3
ARG           GIT_COMMIT=9d4ed3a3236df06e54c80c4f6633b66d68ad3673
ARG           GO_BUILD_SOURCE=./cmd/caddy
ARG           GO_BUILD_OUTPUT=caddy
ARG           GO_LD_FLAGS="-s -w"
ARG           GO_TAGS="netgo osusergo"

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone --recurse-submodules git://"$GIT_REPO" . && git checkout "$GIT_COMMIT"
ARG           GOOS="$TARGETOS"
ARG           GOARCH="$TARGETARCH"

# hadolint ignore=SC2046
RUN           env GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)" go build -trimpath $(if [ "$CGO_ENABLED" = 1 ]; then printf "%s" "-buildmode pie"; fi) \
                -ldflags "$GO_LD_FLAGS" -tags "$GO_TAGS" -o /dist/boot/bin/"$GO_BUILD_OUTPUT" "$GO_BUILD_SOURCE"

#######################
# Assemble all locally built tools
#######################
FROM          $FROM_IMAGE_RUNTIME                                                                                       AS builder-tools-local

COPY          --from=builder-goello       /dist/boot/bin  /boot/bin
COPY          --from=builder-caddy        /dist/boot/bin  /boot/bin
COPY          --from=builder-healthcheck  /dist/boot/bin  /boot/bin

# Diversion so we can easily switch from locally built to from the tools image
FROM          $FROM_IMAGE_TOOLS                                                                                         AS builder-tools

#######################
# Main builder
#######################
FROM          --platform=$BUILDPLATFORM $FROM_IMAGE_BUILDER                                                             AS builder-main

ARG           GIT_REPO=github.com/gomods/athens
ARG           GIT_VERSION=v0.11.0
ARG           GIT_COMMIT=c3020955d204693ae22d26344a700ae5ccf4b754
ARG           GO_BUILD_SOURCE=./cmd/proxy
ARG           GO_BUILD_OUTPUT=athens-proxy
ARG           GO_LD_FLAGS="-s -w -X $GIT_REPO/pkg/build.version=$GIT_VERSION -X $GIT_REPO/pkg/build.buildDate=$BUILD_CREATED"
ARG           GO_TAGS="netgo osusergo"

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone --recurse-submodules git://"$GIT_REPO" . && git checkout "$GIT_COMMIT"
ARG           GOOS="$TARGETOS"
ARG           GOARCH="$TARGETARCH"

# hadolint ignore=SC2046
RUN           env GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)" go build -trimpath $(if [ "$CGO_ENABLED" = 1 ]; then printf "%s" "-buildmode pie"; fi) \
                -ldflags "$GO_LD_FLAGS" -tags "$GO_TAGS" -o /dist/boot/bin/"$GO_BUILD_OUTPUT" "$GO_BUILD_SOURCE"

# XXX Also need the go runtime - ERRRRR how does that work? not the right platform mate!
# RUN           cp "$GOROOT"/bin/go /dist/boot/bin/

#######################
# Builder assembly
#######################
FROM          --platform=$BUILDPLATFORM $FROM_IMAGE_BUILDER                                                             AS builder

COPY          --from=builder-main /dist/boot/bin /dist/boot/bin

COPY          --from=builder-tools /boot/bin/goello-server  /dist/boot/bin
COPY          --from=builder-tools /boot/bin/caddy          /dist/boot/bin
COPY          --from=builder-tools /boot/bin/http-health    /dist/boot/bin

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot/bin -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;

# XXX is this going to work?
RUN           cp -R "$GOROOT" /dist/boot/bin/go

#######################
# Running image
#######################
FROM          $FROM_IMAGE_RUNTIME

USER          root

# Do we really need all that shit? who uses subversion these days?
RUN           --mount=type=secret,mode=0444,id=CA,dst=/etc/ssl/certs/ca-certificates.crt \
              --mount=type=secret,id=CERTIFICATE \
              --mount=type=secret,id=KEY \
              --mount=type=secret,id=PASSPHRASE \
              --mount=type=secret,mode=0444,id=GPG.gpg \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=APT_SOURCES \
              --mount=type=secret,id=APT_OPTIONS,dst=/etc/apt/apt.conf.d/dbdbdp.conf \
              apt-get update -qq && \
              apt-get install -qq --no-install-recommends \
                git=1:2.30.2-1 \
                mercurial=5.6.1-4 \
                git-lfs=2.13.2-1+b2 && \
              apt-get -qq autoremove      && \
              apt-get -qq clean           && \
              rm -rf /var/lib/apt/lists/* && \
              rm -rf /tmp/*               && \
              rm -rf /var/tmp/*

#                bzr=2.7.0+bzr6622-15 \
#                subversion=1.10.4-1+deb10u1 && \

# XXX doesn't work?
# ENV GOROOT=/tmp/go
#RUN           ln -s /boot/bin/go /usr/local/go
ENV GOROOT=/boot/bin/go
ENV PATH=$GOROOT/bin:$PATH

USER          dubo-dubon-duponey

COPY          --from=builder --chown=$BUILD_UID:root /dist /

### Front server configuration
# Port to use
ENV           PORT=4443
EXPOSE        4443
# Log verbosity for
ENV           LOG_LEVEL="warn"
# Domain name to serve
ENV           DOMAIN="go.local"
# Control wether tls is going to be "internal" (eg: self-signed), or alternatively an email address to enable letsencrypt
ENV           TLS="internal"

# Realm in case access is authenticated
ENV           REALM="My Precious Realm"
# Provide username and password here (call the container with the "hash" command to generate a properly encrypted password, otherwise, a random one will be generated)
ENV           USERNAME=""
ENV           PASSWORD=""

### mDNS broadcasting
# Enable/disable mDNS support
ENV           MDNS_ENABLED=false
# Name is used as a short description for the service
ENV           MDNS_NAME="Athens mDNS display name"
# The service will be annonced and reachable at $MDNS_HOST.local
ENV           MDNS_HOST="go"
# Type to advertise
ENV           MDNS_TYPE="_http._tcp"

# Athens specific config
ENV           GO111MODULE="on"

# Caddy certs will be stored here
VOLUME        /certs

# Caddy uses this
VOLUME        /tmp

# Athens cache will be stored there
VOLUME        /data

ENV           HEALTHCHECK_URL="http://127.0.0.1:10000/?healthcheck"

HEALTHCHECK   --interval=120s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1
