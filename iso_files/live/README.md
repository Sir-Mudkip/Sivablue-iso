# Derived live image

Titanoboa was rewritten (mid-2026) into the [container-native ISO contract
v0.1.0](https://github.com/ondrejbudai/bootc-isos): the action now takes only an
`image-ref`, squashfs's it, and builds the ISO. It no longer accepts a flatpaks list, a
post-rootfs hook, or a builder distro, and it does **not** install a live session or an
installer of its own. Everything must be baked into the image first.

This directory builds that image: `Containerfile` (built `FROM` the Sivablue bootc image)
runs `src/build.sh`, which layers on the live/installer environment and then hands the
result to Titanoboa via `image-ref: localhost/sivablue-live-<flavor>:<tag>`.

## Non-obvious requirements the old action used to hide

- **`src/iso.yaml`** — mandatory. Without `/usr/lib/bootc-image-builder/iso.yaml` the build
  hard-errors. It defines the ISO label and GRUB entries; `root=live:CDLABEL=` must equal the
  label. `build.sh` substitutes `@ISO_LABEL@` per flavor.
- **Live initramfs** — the contract copies `/usr/lib/modules/<kver>/initramfs.img` verbatim;
  the stock initramfs can't boot a squashfs live medium, so `build.sh` regenerates it with the
  `dmsquash-live` dracut modules.
- **`livesys-scripts`** — creates the autologin live user + session. The old
  `builder-distro=fedora` pulled this in implicitly.
- **Privileged build** — `flatpak install`, `dracut`, and the nested `podman pull` (which
  embeds the image into the live env's `containers-storage` for offline install) all need
  `--cap-add sys_admin --security-opt label=disable`. Titanoboa reads the image from **root's**
  podman store, so build with `sudo podman build`.

The base images are public on GHCR, so no registry auth is needed for either the `FROM` pull
or the embedded `podman pull`.
