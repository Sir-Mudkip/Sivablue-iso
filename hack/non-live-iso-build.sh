#!/usr/bin/env bash
# Build a Sivablue *autoinstaller* (non-live) ISO via bootc-image-builder.
# Sibling to hack/local-iso-build.sh, which builds the live ISO via Titanoboa.
#
# Usage: hack/installer-iso-build.sh [flavor]
#   flavor: base (default) | nvidia
#
# Output: output/sivablue{,-nvidia}-stable-x86_64-installer.iso
#
# Requires: podman, sudo, ~10 GB free disk.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

flavor="${1:-base}"

case "$flavor" in
    base)
        image_ref="ghcr.io/sir-mudkip/sivablue:stable"
        config="$REPO_ROOT/iso_files/installer.toml"
        output_name="sivablue-stable-x86_64-installer.iso"
        ;;
    nvidia)
        image_ref="ghcr.io/sir-mudkip/sivablue-nvidia:stable"
        config="$REPO_ROOT/iso_files/installer-nvidia.toml"
        output_name="sivablue-nvidia-stable-x86_64-installer.iso"
        ;;
    *)
        echo "Unknown flavor '$flavor'. Use: base | nvidia" >&2
        exit 1
        ;;
esac

OUTPUT_DIR="$REPO_ROOT/output"
WORK_DIR="$REPO_ROOT/.build/installer-${flavor}"
OUTPUT_PATH="$OUTPUT_DIR/$output_name"

[[ -f "$config" ]] || { echo "Config missing: $config" >&2; exit 1; }

cat <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Sivablue autoinstaller ISO build
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Flavor:        $flavor
  Image ref:     $image_ref
  Config:        $config
  Work dir:      $WORK_DIR
  Output:        $OUTPUT_PATH
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF

if [[ -d "$WORK_DIR" ]]; then
    echo "Cleaning previous work dir..."
    sudo rm -rf "$WORK_DIR"
fi
mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

echo "Running bootc-image-builder..."
sudo podman run \
    --rm \
    --privileged \
    --pull=newer \
    --security-opt label=type:unconfined_t \
    --net=host \
    -v "$WORK_DIR":/output \
    -v "$config":/config.toml:ro \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    quay.io/centos-bootc/bootc-image-builder:latest \
    --type iso \
    --rootfs=btrfs \
    --config /config.toml \
    "$image_ref"

ISO_PATH="$WORK_DIR/bootiso/install.iso"
if [[ ! -f "$ISO_PATH" ]]; then
    echo "Build finished but $ISO_PATH not found." >&2
    exit 1
fi

sudo mv "$ISO_PATH" "$OUTPUT_PATH"
sudo chown "$(id -u):$(id -g)" "$OUTPUT_PATH"
( cd "$OUTPUT_DIR" && sha256sum "$output_name" | tee "${output_name}-CHECKSUM" )

echo "Cleaning work directory..."
sudo rm -rf "$WORK_DIR"

echo
echo "✓ ISO ready: $OUTPUT_PATH"
echo
echo "Boot-test in a VM (UEFI, with a scratch disk for autoinstall):"
echo "  qemu-img create -f qcow2 ${OUTPUT_DIR}/test.qcow2 80G"
echo "  qemu-system-x86_64 -m 8G -enable-kvm -cpu host \\"
echo "    -bios /usr/share/edk2/ovmf/OVMF_CODE.fd \\"
echo "    -cdrom $OUTPUT_PATH \\"
echo "    -drive file=${OUTPUT_DIR}/test.qcow2,if=virtio,format=qcow2"
