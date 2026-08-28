#!/bin/bash

###
### build_ka9q-radio.sh
###
### Standalone ka9q-radio build script for a fresh Ubuntu 24.04 LTS host.
###
### This script:
###   - Verifies Ubuntu 24.04 LTS
###   - Verifies sudo access
###   - Installs build dependencies
###   - Clones a clean ka9q-radio source tree
###   - Checks out the requested branch/tag/commit
###   - Records the exact Git commit used
###   - Builds ka9q-radio with RX-888, HackRF, and RTL-SDR enabled
###   - Writes build provenance to ka9q-radio.buildinfo
###
### It does NOT install ka9q-radio, modify systemd, or create radio configs.
###
### Usage:
###   chmod +x build_ka9q-radio.sh
###   ./build_ka9q-radio.sh
###
### Optional environment variables:
###
###   KA9Q_REPO
###       Default: https://github.com/ka9q/ka9q-radio.git
###
###   KA9Q_REF
###       Branch, tag, or commit to build.
###       Default: main
###
###   KA9Q_WORKDIR
###       Parent directory for the source tree and build metadata.
###       Default: $HOME/ka9q-build
###
###   KA9Q_BUILD_JOBS
###       Parallel make jobs.
###       Default: number of online processors
###

set -euo pipefail

KA9Q_REPO="${KA9Q_REPO:-https://github.com/ka9q/ka9q-radio.git}"
KA9Q_REF="${KA9Q_REF:-main}"
KA9Q_COMMIT="69ed6ff"
KA9Q_WORKDIR="${KA9Q_WORKDIR:-$HOME/source/ka9q-build}"
KA9Q_BUILD_JOBS="${KA9Q_BUILD_JOBS:-$(nproc)}"

KA9Q_SOURCE_DIR="${KA9Q_WORKDIR}/ka9q-radio"
KA9Q_BUILDINFO="${KA9Q_WORKDIR}/ka9q-radio.buildinfo"

error()
{
    echo
    echo "ERROR: $*" >&2
    echo
    exit 1
}

banner()
{
    echo
    echo "============================================================"
    echo "$*"
    echo "============================================================"
    echo
}

banner "ka9q-radio Ubuntu 24.04 source build"

### VERIFY OPERATING SYSTEM

if [[ ! -r /etc/os-release ]]; then
    error "/etc/os-release was not found"
fi

# shellcheck disable=SC1091
source /etc/os-release

if [[ "${ID:-}" != "ubuntu" ]]; then
    error "This script requires Ubuntu. Detected: ${PRETTY_NAME:-unknown}"
fi

if [[ "${VERSION_ID:-}" != "24.04" ]]; then
    error "This script targets Ubuntu 24.04 LTS. Detected: ${VERSION_ID:-unknown}"
fi

echo "Operating system : ${PRETTY_NAME}"
echo "Architecture     : $(uname -m)"
echo "Build directory  : ${KA9Q_WORKDIR}"
echo "Requested ref    : ${KA9Q_REF}"

### VERIFY SUDO

if ! command -v sudo >/dev/null 2>&1; then
    error "sudo is required"
fi

sudo -v || error "sudo privileges are required"

### INSTALL BUILD DEPENDENCIES

banner "Installing build dependencies"

sudo apt-get update

sudo apt-get install -y \
    ca-certificates \
    git \
    build-essential \
    pkg-config \
    rsync \
    avahi-daemon \
    avahi-utils \
    libavahi-client-dev \
    libbsd-dev \
    libfftw3-dev \
    libiniparser-dev \
    libncurses-dev \
    libncursesw5-dev \
    libopus-dev \
    libogg-dev \
    libsamplerate0-dev \
    libliquid-dev \
    portaudio19-dev \
    libasound2-dev \
    uuid-dev \
    libusb-1.0-0-dev \
    libusb-dev \
    libhackrf-dev \
    hackrf \
    librtlsdr-dev \
    rtl-sdr

### CREATE A CLEAN SOURCE TREE

banner "Preparing clean ka9q-radio source tree"

mkdir -p "$KA9Q_WORKDIR"

if [[ -e "$KA9Q_SOURCE_DIR" ]]; then
    echo "Removing previous source tree:"
    echo "  $KA9Q_SOURCE_DIR"
    rm -rf "$KA9Q_SOURCE_DIR"
fi

echo "Cloning:"
echo "  $KA9Q_REPO"

git clone "$KA9Q_REPO" "$KA9Q_SOURCE_DIR"
cd "$KA9Q_SOURCE_DIR"
git reset --hard "$KA9Q_COMMIT"

git fetch --all --tags --prune

### CHECK OUT REQUESTED REVISION

echo
echo "Checking out:"
echo "  $KA9Q_REF"

if git show-ref --verify --quiet "refs/remotes/origin/${KA9Q_REF}"; then
    git checkout -B "$KA9Q_REF" "origin/$KA9Q_REF"
else
    git checkout --detach "$KA9Q_REF"
fi

### RECORD EXACT SOURCE REVISION

KA9Q_COMMIT="$(git rev-parse HEAD)"
KA9Q_COMMIT_SHORT="$(git rev-parse --short=12 HEAD)"
KA9Q_COMMIT_DATE="$(git show -s --format='%cI' HEAD)"
KA9Q_COMMIT_SUBJECT="$(git show -s --format='%s' HEAD)"
KA9Q_DESCRIBE="$(git describe --always --dirty --tags 2>/dev/null || git rev-parse --short HEAD)"
KA9Q_BUILD_DATE="$(date --iso-8601=seconds)"
KA9Q_BUILD_HOST="$(hostname)"
KA9Q_BUILD_ARCH="$(uname -m)"

echo
echo "Source revision"
echo "  Repository : $KA9Q_REPO"
echo "  Requested  : $KA9Q_REF"
echo "  Commit     : $KA9Q_COMMIT"
echo "  Commit date: $KA9Q_COMMIT_DATE"
echo "  Subject    : $KA9Q_COMMIT_SUBJECT"
echo

### WRITE BUILD PROVENANCE BEFORE COMPILATION

cat > "$KA9Q_BUILDINFO" <<EOF
KA9Q_REPO="$KA9Q_REPO"
KA9Q_REF="$KA9Q_REF"
KA9Q_COMMIT="$KA9Q_COMMIT"
KA9Q_COMMIT_SHORT="$KA9Q_COMMIT_SHORT"
KA9Q_COMMIT_DATE="$KA9Q_COMMIT_DATE"
KA9Q_COMMIT_SUBJECT="$KA9Q_COMMIT_SUBJECT"
KA9Q_DESCRIBE="$KA9Q_DESCRIBE"
KA9Q_BUILD_DATE="$KA9Q_BUILD_DATE"
KA9Q_BUILD_HOST="$KA9Q_BUILD_HOST"
KA9Q_BUILD_ARCH="$KA9Q_BUILD_ARCH"
KA9Q_SOURCE_DIR="$KA9Q_SOURCE_DIR"
KA9Q_ENABLE_RX888="1"
KA9Q_ENABLE_HACKRF="1"
KA9Q_ENABLE_RTLSDR="1"
EOF

### BUILD

banner "Building ka9q-radio"

make clean

make -j"$KA9Q_BUILD_JOBS" \
    ENABLE_RX888=1 \
    ENABLE_HACKRF=1 \
    ENABLE_RTLSDR=1

### VERIFY BUILD OUTPUT

RADIOD_PATH="$(find "$KA9Q_SOURCE_DIR" -type f -name radiod -perm -111 2>/dev/null | head -1 || true)"

if [[ -z "$RADIOD_PATH" ]]; then
    error "Build completed but an executable radiod binary was not found"
fi

CONTROL_PATH="$(find "$KA9Q_SOURCE_DIR" -type f -name control -perm -111 2>/dev/null | head -1 || true)"
MONITOR_PATH="$(find "$KA9Q_SOURCE_DIR" -type f -name monitor -perm -111 2>/dev/null | head -1 || true)"

{
    echo "KA9Q_RADIOD_PATH=\"$RADIOD_PATH\""
    echo "KA9Q_CONTROL_PATH=\"$CONTROL_PATH\""
    echo "KA9Q_MONITOR_PATH=\"$MONITOR_PATH\""
} >> "$KA9Q_BUILDINFO"

### REPORT SDR FRONT-END MODULES

echo
echo "SDR front-end modules found:"

for module in rx888 hackrf rtlsdr; do
    module_path="$(find "$KA9Q_SOURCE_DIR" -type f -name "${module}.so" 2>/dev/null | head -1 || true)"

    if [[ -n "$module_path" ]]; then
        echo "  ${module}: $module_path"
        upper_module="$(echo "$module" | tr '[:lower:]' '[:upper:]')"
        echo "KA9Q_${upper_module}_MODULE=\"$module_path\"" >> "$KA9Q_BUILDINFO"
    else
        echo "  ${module}: no standalone .so found"
    fi
done

### FINAL SUMMARY

banner "ka9q-radio build completed"

echo "Built commit:"
echo "  $KA9Q_COMMIT"
echo
echo "Source directory:"
echo "  $KA9Q_SOURCE_DIR"
echo
echo "radiod:"
echo "  $RADIOD_PATH"
echo
echo "Build metadata:"
echo "  $KA9Q_BUILDINFO"
echo
echo "No files were installed outside the build directory."
echo "No systemd services or radio configurations were changed."
echo
