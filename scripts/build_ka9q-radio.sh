#!/bin/bash

###
### SIGedge
###
### build_ka9q-radio
###
###
### 20260828-1617
###
### Build ka9q-radio from source and record the exact Git commit.
###
### This script may be executed directly or sourced by a parent SIGedge script.
###
### Expected parent environment:
###   SIGEDGE_SOURCE
###
### Optional environment:
###   KA9Q_REPO       Git repository URL
###   KA9Q_REF        Branch, tag, or commit to build
###   KA9Q_BUILD_JOBS Parallel build jobs
###
### Defaults:
###   KA9Q_REPO=https://github.com/ka9q/ka9q-radio.git
###   KA9Q_REF=main
###   KA9Q_BUILD_JOBS=$(nproc)
###

# SIGedge directory tree
SIGEDGE_ENV_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
SIGEDGE_HOME="$(cd -- "$(dirname -- "$SIGEDGE_ENV_FILE")/.." && pwd)"
SIGEDGE_ROOT=$SIGEDGE_HOME
SIGEDGE_SOURCE=$SIGEDGE_ROOT/source
SIGEDGE_ETC=$SIGEDGE_ROOT/etc
SIGEDGE_CONFIG=$SIGEDGE_ROOT/config
SIGEDGE_DEVICES=$SIGEDGE_HOME/devices
SIGEDGE_SCRIPTS=$SIGEDGE_HOME/scripts
SIGEDGE_PACKAGES=$SIGEDGE_HOME/packages
SIGEDGE_DEBS=$SIGEDGE_HOME/debs

# SIGedge install support files
SIGEDGE_INSTALLED=$SIGEDGE_ETC/INSTALLED_PKGS
SIGEDGE_PKGLIST=$SIGEDGE_PACKAGES/PACKAGES
SIGEDGE_INSTALLED_DEVICES=$SIGEDGE_ETC/INSTALLED_DEVICES
SIGEDGE_DEVLIST=$SIGEDGE_DEVICES/DEVICES
SIGEDGE_SCREEN_STANDARD=$SIGEDGE_SCRIPTS/screen_standard_setup
SIGEDGE_SCREEN_SERVER=$SIGEDGE_SCRIPTS/screen_server_setup
SIGEDGE_BANNER_COLOR="\e[0;104m\e[K"   # blue
SIGEDGE_BANNER_RESET="\e[0m"

# Detect architecture (x86_64, ARMv8)
SIGEDGE_HWARCH=`lscpu|grep Architecture|awk '{print $2}'`
# Detect Operating system (Debian GNU/Linux 13 (Trixie) or Ubuntu 24.04 LTS)
SIGEDGE_OSNAME=`cat /etc/os-release|grep "PRETTY_NAME"|awk -F'"' '{print $2}'`
# Is Platform good for install- true or false - we start with false
SIGEDGE_CERTIFIED="false"
# What is the IP Address
SIGEDGE_IPADDR=`ip -br address | grep UP | awk '{print $1}'`

KA9Q_REPO="${KA9Q_REPO:-https://github.com/ka9q/ka9q-radio.git}"
KA9Q_REF="${KA9Q_REF:-main}"
KA9Q_BUILD_JOBS="${KA9Q_BUILD_JOBS:-$(nproc)}"

if [[ -n "${SIGEDGE_SOURCE:-}" ]]; then
    KA9Q_SOURCE_ROOT="$SIGEDGE_SOURCE"
else
    KA9Q_SOURCE_ROOT="$(pwd)"
fi

KA9Q_SOURCE_DIR="${KA9Q_SOURCE_ROOT}/ka9q-radio"
KA9Q_BUILDINFO="${KA9Q_SOURCE_ROOT}/ka9q-radio.buildinfo"

ka9q_build_return()
{
    local rc="$1"

    if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
        return "$rc"
    fi

    exit "$rc"
}

ka9q_build_error()
{
    echo -e "${SIGEDGE_BANNER_COLOR:-}"
    echo -e "${SIGEDGE_BANNER_COLOR:-} ##  ERROR: $*"
    echo -e "${SIGEDGE_BANNER_RESET:-}"
}

echo -e "${SIGEDGE_BANNER_COLOR:-}"
echo -e "${SIGEDGE_BANNER_COLOR:-} ##  build : ka9q-radio"
echo -e "${SIGEDGE_BANNER_RESET:-}"

### DEPENDENCY CHECK

for cmd in git make gcc; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        ka9q_build_error "Required command not found: $cmd"
        ka9q_build_return 1
    fi
done

### SOURCE

mkdir -p "$KA9Q_SOURCE_ROOT" || {
    ka9q_build_error "Unable to create source directory: $KA9Q_SOURCE_ROOT"
    ka9q_build_return 1
}

if [[ -d "${KA9Q_SOURCE_DIR}/.git" ]]; then
    echo "Updating existing ka9q-radio source tree"
    git -C "$KA9Q_SOURCE_DIR" fetch --all --tags --prune || {
        ka9q_build_error "Unable to update ka9q-radio repository"
        ka9q_build_return 1
    }
else
    echo "Cloning ka9q-radio"
    rm -rf "$KA9Q_SOURCE_DIR"
    git clone "$KA9Q_REPO" "$KA9Q_SOURCE_DIR" || {
        ka9q_build_error "Unable to clone ka9q-radio"
        ka9q_build_return 1
    }
fi

### CHECKOUT REQUESTED REF

cd "$KA9Q_SOURCE_DIR" || {
    ka9q_build_error "Unable to enter $KA9Q_SOURCE_DIR"
    ka9q_build_return 1
}

if git show-ref --verify --quiet "refs/remotes/origin/${KA9Q_REF}"; then
    git checkout -B "$KA9Q_REF" "origin/$KA9Q_REF" || {
        ka9q_build_error "Unable to checkout origin/$KA9Q_REF"
        ka9q_build_return 1
    }
else
    git checkout --detach "$KA9Q_REF" || {
        ka9q_build_error "Unable to checkout ref: $KA9Q_REF"
        ka9q_build_return 1
    }
fi

### RECORD EXACT SOURCE REVISION BEFORE BUILD

KA9Q_COMMIT="$(git rev-parse HEAD)" || {
    ka9q_build_error "Unable to determine ka9q-radio commit"
    ka9q_build_return 1
}

KA9Q_COMMIT_SHORT="$(git rev-parse --short=12 HEAD)"
KA9Q_COMMIT_DATE="$(git show -s --format='%cI' HEAD)"
KA9Q_COMMIT_SUBJECT="$(git show -s --format='%s' HEAD)"
KA9Q_DESCRIBE="$(git describe --always --dirty --tags 2>/dev/null || git rev-parse --short HEAD)"
KA9Q_BUILD_DATE="$(date --iso-8601=seconds)"
KA9Q_BUILD_HOST="$(hostname)"
KA9Q_BUILD_ARCH="$(uname -m)"

echo
echo "ka9q-radio source revision"
echo "  Repository : $KA9Q_REPO"
echo "  Requested  : $KA9Q_REF"
echo "  Commit     : $KA9Q_COMMIT"
echo "  Commit date: $KA9Q_COMMIT_DATE"
echo "  Description: $KA9Q_COMMIT_SUBJECT"
echo

### BUILD

echo "Cleaning previous build artifacts"
make clean || {
    ka9q_build_error "make clean failed"
    ka9q_build_return 1
}

echo "Building ka9q-radio using ${KA9Q_BUILD_JOBS} parallel jobs"
make -j"$KA9Q_BUILD_JOBS" || {
    ka9q_build_error "ka9q-radio build failed"
    ka9q_build_return 1
}

### VERIFY CORE BUILD OUTPUT

if [[ ! -x "${KA9Q_SOURCE_DIR}/src/radiod" ]]; then
    ka9q_build_error "Build completed but src/radiod was not found"
    ka9q_build_return 1
fi

### WRITE BUILD METADATA

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
EOF

chmod 0644 "$KA9Q_BUILDINFO"

### SUMMARY

echo
echo -e "${SIGEDGE_BANNER_COLOR:-}"
echo -e "${SIGEDGE_BANNER_COLOR:-} ##  build : ka9q-radio - Completed"
echo -e "${SIGEDGE_BANNER_RESET:-}"
echo
echo "Built from commit:"
echo "  $KA9Q_COMMIT"
echo
echo "Build metadata:"
echo "  $KA9Q_BUILDINFO"
echo
echo "Core binary:"
echo "  ${KA9Q_SOURCE_DIR}/src/radiod"

ka9q_build_return 0
