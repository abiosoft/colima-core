# colima-core

Dependencies for Colima

## Generating image

Generate a raw disk image compressed with gzip (`.raw.gz`) for the OS architecture and default runtime (docker).

```sh
make
```

Generate a `.raw.gz` image for another architecture. `OS_ARCH` must be one of `aarch64`, `x86_64`

```sh
OS_ARCH=x86_64 make
```

Generate a `.raw.gz` image for another runtime.

```sh
make docker      # default make target
make containerd
make incus
make none
```

Generate `.raw.gz` images for all runtimes.

```sh
make all
```
