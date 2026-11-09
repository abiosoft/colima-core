# colima-core

Dependencies for Colima

## Generating image

Generate a raw disk image compressed with gzip (`.raw.gz`) for the OS architecture, default runtime (docker), and default OS (Ubuntu).

```sh
make
```

Generate a `.raw.gz` image for another architecture. `BUILD_ARCH` must be one of `arm64`, `amd64`

```sh
BUILD_ARCH=amd64 make
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

Generate images based on Debian.

```sh
DIST=debian make
```

Test images

```sh
# test all images
make test

# test variants
make test-docker
make test-containerd
make test-incus
```
