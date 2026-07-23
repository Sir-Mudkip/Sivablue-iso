# Sivablue-iso

Build live and anaconda-iso ISOs for [Sivablue](https://github.com/Sir-Mudkip/Sivablue), a bootc-based Fedora Silverblue derivative.

Two ISO types are produced for each of two flavors (`base`, `nvidia`):

| Type | Tool | Size | UX |
|---|---|---|---|
| **Live ISO** | [Titanoboa](https://github.com/ublue-os/titanoboa) | ~7.5 GB | Boot → GNOME live session → Install through the live gnome session |
| **Anaconda-iso** | [bootc-image-builder](https://github.com/centos/bootc-image-builder) | ~6 GB | Boot → kickstart install → reboot |

Both kinds install the same bootc image (`ghcr.io/sir-mudkip/sivablue{,-nvidia}:stable`) via `bootc switch --mutate-in-place` in the post-install kickstart.

The slight benefit of the live-iso is that many of the flatpaks are installed for your first boot. The install process between the live and anaconda ISOs is identical, except the live version will give you a gnome session to look around if so desired and a number of pre-installed flatpaks. The anaconda-iso version will install install all flatpaks on an initial boot, provided there is an internet connection.

You can download the live ISOs from below:
- [Standard Image](https://download.sivablue.uk/sivablue-stable-x86_64.iso)
- [Standard Image Checksum](https://download.sivablue.uk/sivablue-stable-x86_64.iso-CHECKSUM)
- [Nvidia Image](https://download.sivablue.uk/sivablue-nvidia-stable-x86_64.iso)
- [Nvidia Image Checksum](https://download.sivablue.uk/sivablue-nvidia-stable-x86_64.iso-CHECKSUM)

> [!NOTE]
> The anaconda-iso ISOs are *not* built in CI — they remain available as a local-only convenience via `hack/non-live-iso-build.sh`.

## Repository layout

```bash
hack                                
├── local-iso-build.sh         # Local Live ISO builder
└── non-live-iso-build.sh      # Local Anaconda-iso builder
iso_files
├── live                        # Derived "live" image, then fed to Titanoboa
│   ├── Containerfile           #   built FROM the Sivablue bootc image
│   └── src
│       ├── build.sh            #   bakes in live session, live initramfs, installer
│       ├── configure_iso_anaconda.sh  # Anaconda Live + interactive kickstart
│       ├── flatpaks            #   flatpaks baked into the live session
│       └── iso.yaml            #   required ISO label + GRUB entries
├── installer-nvidia.toml       # Toml config for Nvidia Anaconda-iso
└── installer.toml              # Toml config for Base Anaconda-iso
```

> [!NOTE]
> Since Titanoboa moved to the [container-native ISO contract](https://github.com/ondrejbudai/bootc-isos), it only takes an `image-ref` and embeds no customization of its own. So `iso_files/live/` builds a derived image that bakes in the live session, a `dmsquash-live` initramfs, and the Anaconda installer, and *that* image is what Titanoboa turns into an ISO. See `iso_files/live/README.md`.
                                  
## Local builds                                                                                 

I recommend spinning up a [burnable container and mounting the current directory](https://distrobox.it/). This will allow you to install the pre-requisites if you don't have them and don't want to muddy your personal systems.

Both scripts produce `output/<image>-<tag>-x86_64{,-installer}.iso` plus a SHA256 checksum file.

```bash
./hack/local-iso-build.sh           # Live, base flavor
./hack/local-iso-build.sh nvidia    # Live, nvidia flavor
./hack/non-live-iso-build.sh        # Anaconda-iso, base flavor
./hack/non-live-iso-build.sh nvidia # Anaconda-iso, nvidia flavor
```

Requirements: `podman`, `git`, `sudo`, and a bit of space on your computer.

Boot-test in whatever VM software you have since it's just an ISO file. Assign about 60GB to get "everything" including Kali and Metasploit.

## CI builds

If you don't plan to make your own CI pipeline, then you can skip the rest of this.

`gh workflow run build-iso.yml` (or the GitHub UI) builds the **live** ISOs for both flavors in parallel and uploads them to a single Cloudflare R2 bucket. 

Required repo secrets:

| Secret | Purpose |
|---|---|
| `R2_ACCOUNT_ID` | Cloudflare account ID |
| `R2_ACCESS_KEY_ID` | R2 API access key |
| `R2_SECRET_ACCESS_KEY` | R2 API secret |
| `R2_BUCKET` | Bucket for both `sivablue-*.iso` and `sivablue-nvidia-*.iso` |

The download links can be seen above.

## License

Apache 2.0. Originally derived from [ublue-os/bluefin](https://github.com/ublue-os/bluefin)'s ISO build configuration; substantially rewritten for Sivablue.
