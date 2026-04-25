#!/bin/sh
set -eu

IMAGE="${IMAGE:-itdoginfo/openwrt-sdk-apk:09102025}"
WORKDIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
OUT_DIR="${OUT_DIR:-$WORKDIR/out-apk}"
JOBS="${JOBS:-1}"
VERBOSE="${VERBOSE:-s}"
COPY_ALL_APK="${COPY_ALL_APK:-0}"
PODKOP_META_VERSION="${PODKOP_META_VERSION:-latest}"
LUCI_META_VERSION="${LUCI_META_VERSION:-latest}"

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --podkop-version VALUE   metadata version for podkop package (default: latest)
  --luci-version VALUE     metadata version for LuCI package (default: latest)
  --jobs VALUE             make -j value (default: 1)
  --verbose VALUE          make V= value (default: s)
  --copy-all               copy all .apk artifacts (default: off)
  --help                   show this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --podkop-version)
            [ $# -lt 2 ] && { echo "missing value for $1" >&2; exit 1; }
            PODKOP_META_VERSION="$2"
            shift 2
            ;;
        --luci-version)
            [ $# -lt 2 ] && { echo "missing value for $1" >&2; exit 1; }
            LUCI_META_VERSION="$2"
            shift 2
            ;;
        --jobs)
            [ $# -lt 2 ] && { echo "missing value for $1" >&2; exit 1; }
            JOBS="$2"
            shift 2
            ;;
        --verbose)
            [ $# -lt 2 ] && { echo "missing value for $1" >&2; exit 1; }
            VERBOSE="$2"
            shift 2
            ;;
        --copy-all)
            COPY_ALL_APK="1"
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if ! command -v docker >/dev/null 2>&1; then
    echo "docker is required" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"

# Clean previous artifacts in output folder only.
find "$OUT_DIR" -mindepth 1 -maxdepth 1 -type f -name '*.apk' -delete

cat <<INFO
[build-apk] Image:   $IMAGE
[build-apk] Workdir: $WORKDIR
[build-apk] Out dir: $OUT_DIR
[build-apk] Jobs:    $JOBS
[build-apk] Copy all: $COPY_ALL_APK
[build-apk] Podkop meta version: $PODKOP_META_VERSION
[build-apk] LuCI meta version:   $LUCI_META_VERSION
INFO

docker run --rm \
    -v "$WORKDIR:/workspace" \
    -v "$OUT_DIR:/out" \
    -e JOBS="$JOBS" \
    -e VERBOSE="$VERBOSE" \
    -e COPY_ALL_APK="$COPY_ALL_APK" \
    -e PODKOP_META_VERSION="$PODKOP_META_VERSION" \
    -e LUCI_META_VERSION="$LUCI_META_VERSION" \
    --entrypoint /bin/sh \
    "$IMAGE" -c '
set -eu

cd /builder

rm -rf /builder/package/feeds/utilities/podkop
rm -rf /builder/package/feeds/luci/luci-app-podkop
mkdir -p /builder/package/feeds/utilities
mkdir -p /builder/package/feeds/luci
cp -a /workspace/podkop /builder/package/feeds/utilities/podkop
cp -a /workspace/luci-app-podkop /builder/package/feeds/luci/luci-app-podkop

# Override metadata version labels used in runtime/UI without breaking APK semver package versioning.
sed -i "s/^SHADOWPROXY_METADATA_VERSION:=.*/SHADOWPROXY_METADATA_VERSION:=${PODKOP_META_VERSION}/" /builder/package/feeds/utilities/podkop/Makefile
sed -i "s/^SHADOWPROXY_METADATA_VERSION:=.*/SHADOWPROXY_METADATA_VERSION:=${LUCI_META_VERSION}/" /builder/package/feeds/luci/luci-app-podkop/Makefile

make defconfig
make package/feeds/utilities/podkop/compile -j"${JOBS}" V="${VERBOSE}"
make package/feeds/luci/luci-app-podkop/compile -j"${JOBS}" V="${VERBOSE}"

TMP_LIST="$(mktemp)"
find /builder -type f -name "*.apk" > "$TMP_LIST"

if [ ! -s "$TMP_LIST" ]; then
    echo "[build-apk] No .apk artifacts found after build" >&2
    rm -f "$TMP_LIST"
    exit 2
fi

while IFS= read -r apk_path; do
    apk_name="$(basename "$apk_path")"
    if [ "$COPY_ALL_APK" = "1" ]; then
        cp -f "$apk_path" /out/
        continue
    fi

    case "$apk_name" in
        shadowproxy-*.apk|luci-app-shadowproxy-*.apk|luci-i18n-podkop-*.apk)
            cp -f "$apk_path" /out/
            ;;
    esac
done < "$TMP_LIST"

rm -f "$TMP_LIST"
'

APK_COUNT=$(find "$OUT_DIR" -maxdepth 1 -type f -name '*.apk' | wc -l | tr -d ' ')
if [ "$APK_COUNT" = "0" ]; then
    echo "[build-apk] Build finished but no .apk copied to $OUT_DIR" >&2
    exit 3
fi

echo "[build-apk] Done. Copied $APK_COUNT apk file(s):"
find "$OUT_DIR" -maxdepth 1 -type f -name '*.apk' -print | sort
