ARG           FROM_REGISTRY=ghcr.io/dubo-dubon-duponey

ARG           FROM_IMAGE_BUILDER=base:builder-bullseye-2021-10-15@sha256:1609d1af44c0048ec0f2e208e6d4e6a525c6d6b1c0afcc9d71fccf985a8b0643
ARG           FROM_IMAGE_AUDITOR=base:auditor-bullseye-2021-10-15@sha256:2c95e3bf69bc3a463b00f3f199e0dc01cab773b6a0f583904ba6766b3401cb7b
ARG           FROM_IMAGE_RUNTIME=base:runtime-bullseye-2021-10-15@sha256:5c54594a24e3dde2a82e2027edd6d04832204157e33775edc66f716fa938abba
ARG           FROM_IMAGE_TOOLS=tools:linux-bullseye-2021-10-15@sha256:4de02189b785c865257810d009e56f424d29a804cc2645efb7f67b71b785abde

FROM          $FROM_REGISTRY/$FROM_IMAGE_TOOLS                                                                          AS builder-tools

# one time warcrime... XXX the reason for this is that our builder image is not portable
FROM          $FROM_REGISTRY/base:golang-bullseye-2021-10-15@sha256:a35b057a1f360f1af4bc4743ca82cc3dbfce7c06599fcc6b531d592cbbf2fe12 AS builder-go
RUN           mkdir -p /dist/boot/bin; cp -R "$GOROOT" /dist/boot/bin/go

#######################
# Fetcher
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS fetcher-main

ARG           GIT_REPO=github.com/gomods/athens
ARG           GIT_VERSION=v0.11.0
ARG           GIT_COMMIT=c3020955d204693ae22d26344a700ae5ccf4b754

ENV           WITH_BUILD_SOURCE="./cmd/proxy"
ENV           WITH_BUILD_OUTPUT="athens-proxy"
ENV           WITH_LDFLAGS="-X $GIT_REPO/pkg/build.version=$GIT_VERSION -X $GIT_REPO/pkg/build.buildDate=$BUILD_CREATED"

RUN           git clone --recurse-submodules git://"$GIT_REPO" .; git checkout "$GIT_COMMIT"
RUN           --mount=type=secret,id=CA \
              --mount=type=secret,id=NETRC \
              [[ "${GOFLAGS:-}" == *-mod=vendor* ]] || go mod download

#######################
# Main builder
#######################
FROM          --platform=$BUILDPLATFORM fetcher-main                                                                    AS builder-main

ARG           TARGETARCH
ARG           TARGETOS
ARG           TARGETVARIANT
ENV           GOOS=$TARGETOS
ENV           GOARCH=$TARGETARCH

ENV           CGO_CFLAGS="${CFLAGS:-} ${ENABLE_PIE:+-fPIE}"
ENV           GOFLAGS="-trimpath ${ENABLE_PIE:+-buildmode=pie} ${GOFLAGS:-}"

RUN           export GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)"; \
              [ "${CGO_ENABLED:-}" != 1 ] || { \
                eval "$(dpkg-architecture -A "$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/^armv6$/armel/" -e "s/^armv7$/armhf/" -e "s/^ppc64le$/ppc64el/" -e "s/^386$/i386/")")"; \
                export PKG_CONFIG="${DEB_TARGET_GNU_TYPE}-pkg-config"; \
                export AR="${DEB_TARGET_GNU_TYPE}-ar"; \
                export CC="${DEB_TARGET_GNU_TYPE}-gcc"; \
                export CXX="${DEB_TARGET_GNU_TYPE}-g++"; \
                [ ! "${ENABLE_STATIC:-}" ] || { \
                  [ ! "${WITH_CGO_NET:-}" ] || { \
                    ENABLE_STATIC=; \
                    LDFLAGS="${LDFLAGS:-} -static-libgcc -static-libstdc++"; \
                  }; \
                  [ "$GOARCH" == "amd64" ] || [ "$GOARCH" == "arm64" ] || [ "${ENABLE_PIE:-}" != true ] || ENABLE_STATIC=; \
                }; \
                WITH_LDFLAGS="${WITH_LDFLAGS:-} -linkmode=external -extld="$CC" -extldflags \"${LDFLAGS:-} ${ENABLE_STATIC:+-static}${ENABLE_PIE:+-pie}\""; \
                WITH_TAGS="${WITH_TAGS:-} cgo ${ENABLE_STATIC:+static static_build}"; \
              }; \
              go build -ldflags "-s -w -v ${WITH_LDFLAGS:-}" -tags "${WITH_TAGS:-} net${WITH_CGO_NET:+c}go osusergo" -o /dist/boot/bin/"$WITH_BUILD_OUTPUT" "$WITH_BUILD_SOURCE"


#######################
# Builder assembly
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_AUDITOR                                              AS assembly

COPY          --from=builder-main   /dist/boot    /dist/boot
COPY          --from=builder-go     /dist/boot    /dist/boot

COPY          --from=builder-tools  /boot/bin/goello-server-ng  /dist/boot/bin
COPY          --from=builder-tools  /boot/bin/caddy          /dist/boot/bin
COPY          --from=builder-tools  /boot/bin/http-health    /dist/boot/bin

RUN           setcap 'cap_net_bind_service+ep' /dist/boot/bin/caddy

RUN           RUNNING=true \
              STATIC=true \
                dubo-check validate /dist/boot/bin/*

RUN           RO_RELOCATIONS=true \
                dubo-check validate /dist/boot/bin/caddy

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;

#######################
# Running image
#######################
FROM          $FROM_REGISTRY/$FROM_IMAGE_RUNTIME

USER          root

# Do we really need all that shit? who uses subversion these days?
RUN           --mount=type=secret,uid=100,id=CA \
              --mount=type=secret,uid=100,id=CERTIFICATE \
              --mount=type=secret,uid=100,id=KEY \
              --mount=type=secret,uid=100,id=GPG.gpg \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=APT_SOURCES \
              --mount=type=secret,id=APT_CONFIG \
              apt-get update -qq && \
              apt-get install -qq --no-install-recommends \
                git=1:2.30.2-1 \
                mercurial=5.6.1-4 \
                git-lfs=2.13.2-1+b5 && \
              apt-get -qq autoremove      && \
              apt-get -qq clean           && \
              rm -rf /var/lib/apt/lists/* && \
              rm -rf /tmp/*               && \
              rm -rf /var/tmp/*

# 2.13.2-1
#                bzr=2.7.0+bzr6622-15 \
#                subversion=1.10.4-1+deb10u1 && \

# XXX doesn't work?
# ENV GOROOT=/tmp/go
#RUN           ln -s /boot/bin/go /usr/local/go
ENV           GOROOT=/boot/bin/go
ENV           PATH=$GOROOT/bin:$PATH
# Athens specific config
ENV           GO111MODULE="on"

USER          dubo-dubon-duponey

ENV           _SERVICE_NICK="go"
ENV           _SERVICE_TYPE="http"

COPY          --from=assembly --chown=$BUILD_UID:root /dist /

### Front server configuration
## Advanced settings that usually should not be changed
# Ports for http and https - recent changes in docker make it no longer necessary to have caps, plus we have our NET_BIND_SERVICE cap set anyhow - it's 2021, there is no reason to keep on venerating privileged ports
ENV           ADVANCED_PORT_HTTPS=443
ENV           ADVANCED_PORT_HTTP=80
EXPOSE        443
EXPOSE        80
# By default, tls should be restricted to 1.3 - you may downgrade to 1.2+ for compatibility with older clients (webdav client on macos, older browsers)
ENV           ADVANCED_TLS_MIN=1.3
# Name advertised by Caddy in the server http header
ENV           ADVANCED_SERVER_NAME="DuboDubonDuponey/1.0 (Caddy/2) [$_SERVICE_NICK]"
# Root certificate to trust for mTLS - this is not used if MTLS is disabled
ENV           ADVANCED_MTLS_TRUST="/certs/mtls_ca.crt"
# Log verbosity for
ENV           LOG_LEVEL="warn"
# Domain name to serve
ENV           DOMAIN="$_SERVICE_NICK.local"
ENV           ADDITIONAL_DOMAINS=""
# Control wether tls is going to be "internal" (eg: self-signed), or alternatively an email address to enable letsencrypt - use "" to disable TLS entirely
ENV           TLS="internal"
# Issuer name to appear in certificates
#ENV           TLS_ISSUER="Dubo Dubon Duponey"
# Either disable_redirects or ignore_loaded_certs if one wants the redirects
ENV           TLS_AUTO=disable_redirects
# Staging
# https://acme-staging-v02.api.letsencrypt.org/directory
# Plain
# https://acme-v02.api.letsencrypt.org/directory
# PKI
# https://pki.local
ENV           TLS_SERVER="https://acme-v02.api.letsencrypt.org/directory"
# Either require_and_verify or verify_if_given, or "" to disable mTLS altogether
ENV           MTLS="require_and_verify"
# Realm for authentication - set to "" to disable authentication entirely
ENV           AUTH="My Precious Realm"
# Provide username and password here (call the container with the "hash" command to generate a properly encrypted password, otherwise, a random one will be generated)
ENV           AUTH_USERNAME="dubo-dubon-duponey"
ENV           AUTH_PASSWORD="cmVwbGFjZV9tZV93aXRoX3NvbWV0aGluZwo="
### mDNS broadcasting
# Type to advertise
ENV           MDNS_TYPE="_$_SERVICE_TYPE._tcp"
# Name is used as a short description for the service
ENV           MDNS_NAME="$_SERVICE_NICK mDNS display name"
# The service will be annonced and reachable at $MDNS_HOST.local (set to empty string to disable mDNS announces entirely)
ENV           MDNS_HOST="$_SERVICE_NICK"
# Also announce the service as a workstation (for example for the benefit of coreDNS mDNS)
ENV           MDNS_STATION=true
# Caddy certs will be stored here
VOLUME        /certs
# Caddy uses this
VOLUME        /tmp
# Used by the backend service
VOLUME        /data
ENV           HEALTHCHECK_URL="http://127.0.0.1:10000/?healthcheck"

HEALTHCHECK   --interval=120s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1
