# colima-core

Dependencies for Colima

## Generating image

Generate qcow image for the OS architecture.

```sh
make qcow
```

Generate qcow image for the another architecture. `OS_ARCH` must be one of `aarch64`, `x86_64`

```sh
OS_ARCH=x86_64 make qcow
```
