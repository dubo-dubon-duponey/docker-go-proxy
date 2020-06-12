# What

Docker image for a go module proxy.

This is based on [Athens](https://github.com/gomods/athens).

## Image features

 * multi-architecture:
    * [x] linux/amd64
    * [x] linux/arm64
    * [x] linux/arm/v7
    * [x] linux/arm/v6
 * hardened:
    * [x] image runs read-only
    * [x] image runs with no capabilities
    * [x] process runs as a non-root user, disabled login, no shell
 * lightweight
    * [x] based on our slim [Debian buster version](https://github.com/dubo-dubon-duponey/docker-debian)
    * [x] simple entrypoint script
    * [ ] multi-stage build with ~~no installed~~ dependencies for the runtime image:
        * git
        * git-lfs
        * bzr
        * subversion
        * mercurial
 * observable
    * [x] healthcheck
    * [x] log to stdout
    * [ ] ~~prometheus endpoint~~ (TODO)

## Run


```bash
docker run -d \
    --volume somewhere:/tmp/athens \
    --env ATHENS_DISK_STORAGE_ROOT=/tmp/athens \
    --env ATHENS_PORT=:3000 \
    --env ATHENS_STORAGE_TYPE=disk \
    --publish 3000:3000/tcp \
    --cap-drop ALL \
    --read-only \
    dubodubonduponey/goproxy:v1
```

## Notes

### Configuration reference

Using any privileged port for athens requires `--cap-add=CAP_NET_BIND_SERVICE` and `--user=root`.

Any additional argument will be passed to the athens-proxy binary.

### Prometheus

TBD

## Moar?

See [DEVELOP.md](DEVELOP.md)
