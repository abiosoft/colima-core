# colima-core

Dependencies for Colima

## Generating image

Generate qcow image for the OS architecture and default runtime (docker).

```sh
make qcow
```

Generate qcow image for another architecture. `OS_ARCH` must be one of `aarch64`, `x86_64`

```sh
OS_ARCH=x86_64 make qcow
```

Generate qcow image for another runtime. `RUNTIME` must be one of `docker`, `containerd`, `incus`, `none`

```sh
RUNTIME=containerd make qcow
```
