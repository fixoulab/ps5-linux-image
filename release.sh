#!/bin/bash
# Packs a built image for publication: compresses it to .img.xz and writes
# the matching .sha256 file next to it, ready to attach to a GitHub release.
#
#   ./release.sh                     # output/ps5-proxmox9.img
#   ./release.sh --distro debian     # output/ps5-debian.img
#   ./release.sh --image some.img    # any image file
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DISTRO="proxmox9"
IMG=""
XZ_LEVEL=4
# GitHub refuses release assets of 2 GiB and more.
ASSET_LIMIT="${ASSET_LIMIT:-2147483648}"

usage() {
    echo "Usage: $0 [--distro <distro>] [--image <path>] [--level <0-9>]"
    echo ""
    echo "Options:"
    echo "  --distro   Distro whose image to pack: output/ps5-<distro>.img (default: proxmox9)"
    echo "  --image    Path to the image to pack, instead of --distro"
    echo "  --level    xz compression level (default: 4, same as the upstream releases)"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --distro)  DISTRO="$2";   shift 2 ;;
        --image)   IMG="$2";      shift 2 ;;
        --level)   XZ_LEVEL="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

[ -n "$IMG" ] || IMG="$SCRIPT_DIR/output/ps5-${DISTRO}.img"

if [ ! -f "$IMG" ]; then
    echo "No image at $IMG"
    echo "Build it first: ./build_image.sh --distro $DISTRO"
    exit 1
fi
command -v xz >/dev/null || { echo "xz is required (apt install xz-utils)"; exit 1; }
case "$XZ_LEVEL" in
    [0-9]) ;;
    *) echo "--level must be a digit from 0 to 9"; exit 1 ;;
esac

OUT_DIR="$(cd "$(dirname "$IMG")" && pwd)"
NAME="$(basename "$IMG")"
XZ="$OUT_DIR/$NAME.xz"
SUM="$XZ.sha256"

if [ ! -w "$OUT_DIR" ]; then
    echo "Cannot write to $OUT_DIR (owned by another user?)."
    echo "Fix it with: sudo chown \"\$USER\" \"$OUT_DIR\""
    exit 1
fi

echo "Compressing $NAME with xz -$XZ_LEVEL on all cores, this takes a few minutes..."
trap 'rm -f "$XZ.tmp"' EXIT
xz -T0 "-$XZ_LEVEL" -c "$IMG" > "$XZ.tmp"

echo "Checking the archive..."
xz -t "$XZ.tmp"
mv -f "$XZ.tmp" "$XZ"
trap - EXIT

# Run from the output directory so the .sha256 file holds a bare file name and
# "sha256sum -c" works for whoever downloads both files.
( cd "$OUT_DIR" && sha256sum "$NAME.xz" > "$NAME.xz.sha256" )

SIZE=$(stat -c %s "$XZ")
echo ""
echo "Release files:"
echo "  $XZ ($(numfmt --to=iec-i --suffix=B "$SIZE"))"
echo "  $SUM"
echo ""
echo "sha256: $(cut -d' ' -f1 "$SUM")"

if [ "$SIZE" -ge "$ASSET_LIMIT" ]; then
    echo ""
    echo "WARNING: the archive is too large for a GitHub release asset (limit: 2 GiB)."
    echo "Split it, and publish the parts together with the .sha256 file:"
    echo "  split -b 1900M -d \"$XZ\" \"$XZ.part-\""
    echo "Users rejoin them with:"
    echo "  cat $NAME.xz.part-* > $NAME.xz"
fi
