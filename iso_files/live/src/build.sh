#!/usr/bin/bash
# Turn the Sivablue bootc image into a Titanoboa-ready "live" image. Everything the
# retired Titanoboa inputs used to do (flatpaks-list, hook-post-rootfs, builder-distro)
# now happens here, inside the image build. See ./iso_files/live/README.md.
set -exo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${IMAGE_REF:?}" "${IMAGE_TAG:?}" "${ISO_LABEL:?}"
FLAVOR="${FLAVOR:-base}"

# /root symlink target + flatpak's bwrap need /proc/sys writable during the build
mkdir -p "$(realpath /root)"
mount -o remount,rw /proc/sys

# --- Flatpaks: baked into /var/lib/flatpak; the kickstart later rsyncs them onto the
#     installed system (see configure_iso_anaconda.sh -> install-flatpaks.ks).
curl --retry 3 -Lo /etc/flatpak/remotes.d/flathub.flatpakrepo \
    https://dl.flathub.org/repo/flathub.flatpakrepo
mapfile -t FLATPAKS < <(grep -vE '^\s*(#|$)' "$SCRIPT_DIR/flatpaks")
flatpak install -y --noninteractive flathub "${FLATPAKS[@]}"

# --- Embed the bootc image into the live env's containers-storage so the installer's
#     `ostreecontainer --transport=containers-storage` resolves it offline.
podman pull "$IMAGE_REF:$IMAGE_TAG"

# --- Live-capable initramfs. The container-native ISO contract copies
#     /usr/lib/modules/<kver>/initramfs.img verbatim; the stock initramfs cannot boot a
#     squashfs live medium, so regenerate it with the dmsquash-live dracut modules.
dnf install -y dracut-live
kernel=""
for d in /usr/lib/modules/*/; do
    [[ -f "${d}vmlinuz" ]] && { kernel="$(basename "$d")"; break; }
done
: "${kernel:?no kernel with vmlinuz found under /usr/lib/modules}"
DRACUT_NO_XATTR=1 dracut -v --force --zstd --reproducible --no-hostonly \
    --add "dmsquash-live dmsquash-live-autooverlay" \
    "/usr/lib/modules/${kernel}/initramfs.img" "${kernel}"

# --- Live session: creates the autologin liveuser + GNOME session. The old
#     builder-distro=fedora pulled this in for us; now it is explicit.
dnf install -y livesys-scripts
sed -i "s/^livesys_session=.*/livesys_session=gnome/" /etc/sysconfig/livesys
systemctl enable livesys.service livesys-late.service

# --- Anaconda installer, GNOME live tweaks, interactive kickstart
"$SCRIPT_DIR/configure_iso_anaconda.sh"

# --- EFI + BIOS GRUB staging required by the ISO contract
dnf install -y grub2-efi-x64-cdboot grub2-pc-modules
if [[ ! -d /boot/efi/EFI/fedora ]]; then
    mkdir -p /boot/efi
    for src in /usr/lib/bootupd/updates/EFI /usr/lib/efi/*/*/EFI; do
        [[ -d "$src" ]] || continue
        cp -avT "$src" /boot/efi/EFI
        break
    done
fi
[[ -d /boot/efi/EFI/fedora ]] || { echo >&2 "ERROR: EFI dir not staged at /boot/efi/EFI/fedora"; exit 1; }
[[ -d /usr/lib/grub/i386-pc ]] || { echo >&2 "ERROR: BIOS GRUB modules missing at /usr/lib/grub/i386-pc"; exit 1; }

# --- ostree needs scratch space during install; the live / is a small tmpfs overlay,
#     so mount a larger tmpfs at /var/tmp. (%% escapes to a literal % in the unit.)
rm -rf /var/tmp
mkdir -p /var/tmp
cat >/etc/systemd/system/var-tmp.mount <<'EOF'
[Unit]
Description=Larger tmpfs for /var/tmp on the live system

[Mount]
What=tmpfs
Where=/var/tmp
Type=tmpfs
Options=size=50%%,nr_inodes=1m

[Install]
WantedBy=local-fs.target
EOF
systemctl enable var-tmp.mount

# --- nvidia live tweak: GTK apps can fail to open under the proprietary driver
if [[ "$FLAVOR" == nvidia ]]; then
    mkdir -p /etc/environment.d /etc/skel/.config/environment.d
    printf 'GSK_RENDERER=gl\n' | tee \
        /etc/environment.d/99-nvidia-fix.conf \
        /etc/skel/.config/environment.d/99-nvidia-fix.conf >/dev/null
fi

# --- Mandatory ISO config for the new Titanoboa/bootc-image-builder contract
mkdir -p /usr/lib/bootc-image-builder
sed "s/@ISO_LABEL@/${ISO_LABEL}/g" "$SCRIPT_DIR/iso.yaml" \
    >/usr/lib/bootc-image-builder/iso.yaml

dnf clean all
