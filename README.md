# Sivablue-iso

Build live and autoinstaller ISOs for [Sivablue](https://github.com/Sir-Mudkip/Sivablue), a bootc-based Fedora Silverblue derivative.

Two ISO types are produced for each of two flavors (`base`, `nvidia`):

| Type | Tool | Size | UX |
|---|---|---|---|
| **Live** | [Titanoboa](https://github.com/ublue-os/titanoboa) | ~7 GB | Boot → GNOME live session → click *Install* → guided Anaconda flow |
| **Autoinstaller** | [bootc-image-builder](https://github.com/centos/bootc-image-builder) | ~3 GB | Boot → unattended kickstart install → reboot |

Both kinds install the same bootc image (`ghcr.io/sir-mudkip/sivablue{,-nvidia}:stable`) via `bootc switch --mutate-in-place` in the post-install kickstart.

## Repository layout

```
iso_files/
  configure_iso_anaconda.sh    # Titanoboa post-rootfs hook (live ISO)
  flatpaks.list                # Flatpaks preinstalled in the live env
  installer.toml               # bootc-image-builder config (base autoinstaller)
  installer-nvidia.toml        # bootc-image-builder config (nvidia autoinstaller)
hack/
  local-iso-build.sh           # Build a live ISO locally via Titanoboa
  non-live-iso-build.sh        # Build an autoinstaller ISO locally via bootc-image-builder
.github/workflows/
  build-iso.yml                # CI: builds all four ISOs, uploads to Cloudflare R2
```

## Local builds

Both scripts produce `output/<image>-<tag>-x86_64{,-installer}.iso` plus a SHA256 checksum file.

```bash
./hack/local-iso-build.sh           # Live, base flavor
./hack/local-iso-build.sh nvidia    # Live, nvidia flavor
./hack/non-live-iso-build.sh        # Autoinstaller, base flavor
./hack/non-live-iso-build.sh nvidia # Autoinstaller, nvidia flavor
```

Requirements: `podman`, `just` (for Titanoboa), `git`, `sudo`. ~20 GB free disk for live builds, ~10 GB for autoinstaller builds. On an immutable host (Bluefin/Silverblue), run from a distrobox.

Boot-test in qemu (UEFI):

```bash
qemu-img create -f qcow2 output/test.qcow2 80G
qemu-system-x86_64 -m 8G -enable-kvm -cpu host \
  -bios /usr/share/edk2/ovmf/OVMF_CODE.fd \
  -cdrom output/<your>.iso \
  -drive file=output/test.qcow2,if=virtio,format=qcow2
```

## CI builds

`gh workflow run build-iso.yml` (or the GitHub UI) runs all four matrix jobs in parallel and uploads to Cloudflare R2.

Required repo secrets:

| Secret | Purpose |
|---|---|
| `R2_ACCOUNT_ID` | Cloudflare account ID |
| `R2_ACCESS_KEY_ID` | R2 API access key |
| `R2_SECRET_ACCESS_KEY` | R2 API secret |
| `R2_BUCKET_BASE` | Bucket for `sivablue-*.iso` |
| `R2_BUCKET_NVIDIA` | Bucket for `sivablue-nvidia-*.iso` |

Files are routed to buckets by flavor; live and autoinstaller ISOs for the same flavor share a bucket and are distinguished by the `-installer` suffix.

## License

Apache 2.0. Originally derived from [ublue-os/bluefin](https://github.com/ublue-os/bluefin)'s ISO build configuration; substantially rewritten for Sivablue.
