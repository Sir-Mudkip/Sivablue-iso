#!/usr/bin/env bash
# Build a Sivablue live-bootable ISO locally, mirroring .github/workflows/build-iso.yml.
# Under the container-native Titanoboa contract this is two steps: build the derived
# "live" image (iso_files/live), then run Titanoboa against that local image.
#
# Usage: hack/local-iso-build.sh [flavor] [tag]
#   flavor: base (default) | nvidia
#   tag:    bootc image tag (default: stable)
#
# Requires: podman, git, sudo, ~40 GB free disk in this checkout.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

flavor="${1:-base}"
tag="${2:-stable}"

case "$flavor" in
    base)   image_name="sivablue";        iso_label="Sivablue-Live" ;;
    nvidia) image_name="sivablue-nvidia"; iso_label="Sivablue-Nvidia-Live" ;;
    *)
        echo "Unknown flavor '$flavor'. Use: base | nvidia" >&2
        exit 1
        ;;
esac

IMAGE_REF="ghcr.io/sir-mudkip/${image_name}"
LIVE_IMAGE="localhost/sivablue-live-${flavor}:${tag}"
LIVE_DIR="$REPO_ROOT/iso_files/live"
BUILD_DIR="$REPO_ROOT/.build/${flavor}"
OUTPUT_DIR="$REPO_ROOT/output"
OUTPUT_NAME="${image_name}-${tag}-x86_64.iso"
OUTPUT_PATH="$OUTPUT_DIR/$OUTPUT_NAME"

[[ -f "$LIVE_DIR/Containerfile" ]] || { echo "Missing $LIVE_DIR/Containerfile" >&2; exit 1; }

cat <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Sivablue ISO build (local, via Titanoboa)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Flavor:        $flavor
  Base image:    $IMAGE_REF:$tag
  Live image:    $LIVE_IMAGE
  ISO label:     $iso_label
  Output:        $OUTPUT_PATH
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF

# --- 1. Build the derived live image (identical to CI). Privileged: flatpak/dracut and
#        the nested `podman pull` inside the build all require it. sudo so the image lands
#        in root's store, where Titanoboa's `--mount type=image` looks for it.
echo "Building derived live image ${LIVE_IMAGE}..."
sudo podman build \
    --cap-add sys_admin --security-opt label=disable --squash \
    --build-arg BASE_IMAGE="${IMAGE_REF}:${tag}" \
    --build-arg IMAGE_REF="${IMAGE_REF}" \
    --build-arg IMAGE_TAG="${tag}" \
    --build-arg ISO_LABEL="${iso_label}" \
    --build-arg FLAVOR="${flavor}" \
    -t "${LIVE_IMAGE}" \
    "${LIVE_DIR}"

# --- 2. Run Titanoboa against the local image.
if [[ -d "$BUILD_DIR" ]]; then
    echo "Cleaning previous Titanoboa checkout..."
    sudo rm -rf "$BUILD_DIR"
fi
echo "Cloning Titanoboa..."
git clone --depth=1 https://github.com/ublue-os/titanoboa "$BUILD_DIR"

# On Fedora hosts the builder container needs /dev/fuse; the upstream run line does not
# add it. Inject it (harmless if the host does not need it).
sed -i 's|--security-opt label=disable|--security-opt label=disable --device /dev/fuse|' \
    "$BUILD_DIR/main.sh"

mkdir -p "$OUTPUT_DIR"
echo "Running Titanoboa build (this takes 20-40 min)..."
# main.sh prints the built ISO path on stdout; all its logging goes to stderr.
ISO_SRC="$(
    sudo env \
        TITANOBOA_CTR_IMAGE="$LIVE_IMAGE" \
        TITANOBOA_OUTPUT_DIR="$BUILD_DIR/output" \
        bash "$BUILD_DIR/main.sh"
)"

if [[ ! -f "$ISO_SRC" ]]; then
    echo "Build failed: no ISO produced at '$ISO_SRC'." >&2
    exit 1
fi

sudo mv "$ISO_SRC" "$OUTPUT_PATH"
sudo chown "$(id -u):$(id -g)" "$OUTPUT_PATH"
( cd "$OUTPUT_DIR" && sha256sum "$OUTPUT_NAME" | tee "${OUTPUT_NAME}-CHECKSUM" )

# Free the multi-GB squashfs/rootfs scratch Titanoboa leaves behind.
echo "Cleaning Titanoboa work directory..."
sudo rm -rf "$BUILD_DIR/output"

echo
echo "✓ ISO ready: $OUTPUT_PATH"
echo
echo "Boot-test in a VM (UEFI):"
echo "  qemu-img create -f qcow2 ${OUTPUT_DIR}/test.qcow2 80G"
echo "  qemu-system-x86_64 -m 8G -enable-kvm -cpu host \\"
echo "    -bios /usr/share/edk2/ovmf/OVMF_CODE.fd \\"
echo "    -cdrom $OUTPUT_PATH \\"
echo "    -drive file=${OUTPUT_DIR}/test.qcow2,if=virtio,format=qcow2"
