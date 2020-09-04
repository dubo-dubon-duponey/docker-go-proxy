ARG           BUILDER_BASE=dubodubonduponey/base:builder
ARG           RUNTIME_BASE=dubodubonduponey/base:runtime

#######################
# Extra builder for healthchecker
#######################
# hadolint ignore=DL3006
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-healthcheck

ARG           GIT_REPO=github.com/dubo-dubon-duponey/healthcheckers
ARG           GIT_VERSION=51ebf8ca3d255e0c846307bf72740f731e6210c3

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION
# hadolint ignore=DL4006
RUN           env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v -ldflags "-s -w" \
                -o /dist/boot/bin/http-health ./cmd/http

#######################
# Goello
#######################
# hadolint ignore=DL3006
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-goello

ARG           GIT_REPO=github.com/dubo-dubon-duponey/goello
ARG           GIT_VERSION=6f6c96ef8161467ab25be45fe3633a093411fcf2

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION
# hadolint ignore=DL4006
RUN           env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v -ldflags "-s -w" \
                -o /dist/boot/bin/goello-server ./cmd/server/main.go


##########################
# Builder custom
##########################
# hadolint ignore=DL3006
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-athens

# 0.10
ARG           GIT_REPO=github.com/gomods/athens
ARG           GIT_VERSION=408fd74a9c95c019264982f020f6eaf31a1eeabe

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION

# hadolint ignore=DL4006
RUN           env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v -ldflags "-s -w -X github.com/gomods/athens/pkg/build.version=$BUILD_VERSION -X github.com/gomods/athens/pkg/build.buildDate=$BUILD_CREATED" \
                -o /dist/boot/bin/athens-proxy ./cmd/proxy

RUN           cp /build/golang/go/bin/go /dist/boot/bin/


#######################
# Builder assembly
#######################
# hadolint ignore=DL3006
FROM          $BUILDER_BASE                                                                                             AS builder

COPY          --from=builder-healthcheck /dist/boot/bin /dist/boot/bin
COPY          --from=builder-athens /dist/boot/bin /dist/boot/bin
COPY          --from=builder-goello /dist/boot/bin /dist/boot/bin

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

# mDNS
ENV           MDNS_NAME="Fancy Registry Service Name"
ENV           MDNS_HOST="registry"
ENV           MDNS_TYPE=_goproxy._tcp

# Authentication
ENV           USERNAME="dubo-dubon-duponey"
ENV           PASSWORD="plaintextpassword"
ENV           REALM="My precious goproxy"

ENV           GO111MODULE=on
ENV           ATHENS_DISK_STORAGE_ROOT=/tmp/athens
ENV           ATHENS_STORAGE_TYPE=disk
ENV           PORT=:3000

ENV           HEALTHCHECK_URL="http://127.0.0.1:3000/?healthcheck=internal"

EXPOSE        3000/tcp

HEALTHCHECK   --interval=120s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1

