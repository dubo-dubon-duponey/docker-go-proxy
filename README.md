# What

Docker image for a go module proxy.

This is based on [Athens](https://github.com/gomods/athens).

## Image features

 * multi-architecture:
   * [x] linux/amd64
   * [x] linux/arm64
 * hardened:
   * [x] image runs read-only
   * [x] image runs with no capabilities
   * [x] process runs as a non-root user, disabled login, no shell
 * lightweight
   * [x] based on our slim [Debian Bookworm](https://github.com/dubo-dubon-duponey/docker-debian)
   * [x] simple entrypoint script
   * [ ] multi-stage build with ~~zero packages~~ `git`, `git-lfs`, `bzr`, `subversion`, `mercurial` installed in the runtime image
 * observable
   * [x] healthcheck
   * [x] log to stdout
   * [ ] ~~prometheus endpoint~~

## Run


```bash
docker run -d \
    --volume somewhere:/tmp/athens \
    --env ATHENS_DISK_STORAGE_ROOT=/tmp/athens \
    --env PORT=:443 \
    --env ATHENS_STORAGE_TYPE=disk \
    --publish 443:443/tcp \
    --cap-drop ALL \
    --cap-add NET_BIND_SERVICE \
    --read-only \
    docker.io/dubodubonduponey/go-proxy
```

## Notes

### Configuration reference

Using any privileged port for athens requires `--cap-add=CAP_NET_BIND_SERVICE` and `--user=root`.

Any additional argument will be passed to the athens-proxy binary.

### Prometheus

TBD

## Moar?

See [DEVELOP.md](DEVELOP.md)
