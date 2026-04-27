#!/usr/bin/env bash
# Build a Sivablue live-bootable ISO locally via Titanoboa.
# Mirrors what .github/workflows/build-iso.yml does in CI, so output should be
# bit-similar between local and CI builds.
#
# Usage: hack/local-iso-build.sh [flavor] [tag]
#   flavor: base (default) | nvidia
#   tag:    bootc image tag (default: stable)
#
# Requires: podman, just, sudo, ~20 GB free disk in this checkout.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

flavor="${1:-base}"
tag="${2:-stable}"

case "$flavor" in
    base)   image_name="sivablue" ;;
    nvidia) image_name="sivablue-nvidia" ;;
    *)
        echo "Unknown flavor '$flavor'. Use: base | nvidia" >&2
        exit 1
        ;;
esac

IMAGE_REF="ghcr.io/sir-mudkip/${image_name}:${tag}"
HOOK="$REPO_ROOT/iso_files/configure_iso_anaconda.sh"
FLATPAKS="$REPO_ROOT/iso_files/flatpaks.list"
BUILD_DIR="$REPO_ROOT/.build/${flavor}"
OUTPUT_DIR="$REPO_ROOT/output"
OUTPUT_NAME="${image_name}-${tag}-x86_64.iso"
OUTPUT_PATH="$OUTPUT_DIR/$OUTPUT_NAME"

[[ -f "$HOOK" ]]     || { echo "Hook script missing: $HOOK" >&2; exit 1; }
[[ -f "$FLATPAKS" ]] || { echo "Flatpak list missing: $FLATPAKS" >&2; exit 1; }

cat <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Sivablue ISO build (local, via Titanoboa)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Flavor:        $flavor
  Image ref:     $IMAGE_REF
  Hook:          $HOOK
  Flatpaks:      $FLATPAKS
  Build dir:     $BUILD_DIR
  Output:        $OUTPUT_PATH
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF

# Wipe any previous build (Titanoboa leaves root-owned files behind).
if [[ -d "$BUILD_DIR" ]]; then
    echo "Cleaning previous build dir..."
    sudo rm -rf "$BUILD_DIR"
fi

echo "Cloning Titanoboa..."
git clone --depth=1 https://github.com/hanthor/titanoboa "$BUILD_DIR"

# Same patches the previous Bluefin script applied — keep them; without these
# Titanoboa fails on Fedora hosts due to setfiles/SELinux and missing /dev/fuse
# in the builder container.
echo "Patching Titanoboa Justfile..."
sed -i \
    -e 's|setfiles -F -r . /etc/selinux/targeted/contexts/files/file_contexts \.|& \|\| true|' \
    -e 's|--security-opt label=disable|--security-opt label=disable --device /dev/fuse|' \
    "$BUILD_DIR/Justfile"

cp "$HOOK"     "$BUILD_DIR/hook.sh"
cp "$FLATPAKS" "$BUILD_DIR/flatpaks.list"

cd "$BUILD_DIR"

echo "Running Titanoboa build (this takes 20-40 min and pulls a multi-GB image)..."
sudo \
    TITANOBOA_BUILDER_DISTRO=fedora \
    HOOK_post_rootfs=hook.sh \
    just build "$IMAGE_REF" 1 flatpaks.list

ISO_PATH="$BUILD_DIR/output.iso"
if [[ ! -f "$ISO_PATH" ]]; then
    echo "Build finished but $ISO_PATH not found." >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
sudo mv "$ISO_PATH" "$OUTPUT_PATH"
sudo chown "$(id -u):$(id -g)" "$OUTPUT_PATH"
( cd "$OUTPUT_DIR" && sha256sum "$OUTPUT_NAME" | tee "${OUTPUT_NAME}-CHECKSUM" )

# Free the ~40 GB of intermediate squashfs/rootfs scratch that Titanoboa leaves behind.
# Keeps .build/<flavor>/ but only the cloned Titanoboa source — next run will wipe it anyway.
echo "Cleaning Titanoboa work directory..."
sudo rm -rf "$BUILD_DIR/work"

echo
echo "✓ ISO ready: $OUTPUT_PATH"
echo
echo "Boot-test in a VM (UEFI):"
echo "  qemu-img create -f qcow2 ${OUTPUT_DIR}/test.qcow2 80G"
echo "  qemu-system-x86_64 -m 8G -enable-kvm -cpu host \\"
echo "    -bios /usr/share/edk2/ovmf/OVMF_CODE.fd \\"
echo "    -cdrom $OUTPUT_PATH \\"
echo "    -drive file=${OUTPUT_DIR}/test.qcow2,if=virtio,format=qcow2"
