#!/usr/bin/env bash
# scripts/udcode-box.sh
#
# A box to work in with UDCode on an immutable Linux (Bazzite, SteamOS, Fedora
# Atomic) that has no build tools of its own: a Distrobox of Ubuntu 22.04 —
# what UDCode's AppImage and the GNUstep stack's archives are built on — with
#
#   - the patched GNUstep stack and FreeCoreData (their latest releases, in
#     /opt/gnustep) and the packages building on them needs (the stack's own
#     list);
#   - LLVM 18's clangd and lldb-dap (apt.llvm.org), gdb, make, cmake, ninja,
#     ripgrep;
#   - what the Quake and Doom 3 engines build with (SDL2, OpenAL, Vorbis, Opus);
#   - UDCode (its latest release's AppImage, unpacked: no FUSE), started with
#     GNUstep's tools on its PATH, in the host's application menu.
#
# The box shares your home, display, GPU and sound: what is built in it runs
# from it as any other program.
#
# USAGE (on the host)
#   bash udcode-box.sh                    make the box, or bring it up to date
#   bash udcode-box.sh --appimage FILE    UDCode from FILE (in your home), not the latest release
#   bash udcode-box.sh --stack VERSION    the stack's release VERSION (2026.10.19.1)
#   UDCODE_BOX=name bash udcode-box.sh    a box of another name (udcode)
#
# Then UDCode is in the application menu, or: distrobox enter udcode -- udcode
#
# REQUIREMENTS
#   distrobox (Bazzite and SteamOS have it), podman or docker; x86_64
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

BOX=${UDCODE_BOX:-udcode}
APPIMAGE=""
STACK=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --appimage) APPIMAGE=$(realpath "$2"); shift 2 ;;
        --stack) STACK=$2; shift 2 ;;
        --inside) INSIDE=1; shift ;;
        -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
        *) echo "udcode-box: what is $1?" >&2; exit 2 ;;
    esac
done

# The latest release's tag of a GitHub repository, without its "v".
latest() {
    curl -fsSL "https://api.github.com/repos/$1/releases/latest" | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -n 1
}

# ─── Inside the box ──────────────────────────────────────────────────────────

inside() {
    local sudo=""
    [[ $(id -u) == 0 ]] || sudo=sudo
    export DEBIAN_FRONTEND=noninteractive
    local arch
    arch=$(uname -m)

    echo "==> Packages"
    $sudo apt-get -q update
    $sudo apt-get -q -y install --no-install-recommends ca-certificates curl xz-utils gnupg

    echo "==> The GNUstep stack"
    local stack=${STACK:-$(latest ashalkhakov/gnustep-patches)}
    local installed
    installed=$(cat /opt/gnustep/share/gnustep-patches/version 2>/dev/null || true)
    if [[ "$installed" != "$stack" ]]; then
        curl -fsSL "https://github.com/ashalkhakov/gnustep-patches/releases/download/v$stack/gnustep-patches-$stack-ubuntu22.04-$arch.tar.xz" \
            | $sudo tar -C / --no-overwrite-dir -xJ
        echo "$stack" | $sudo tee /opt/gnustep/share/gnustep-patches/version >/dev/null
    fi
    echo "  $stack"
    grep -v '^#' /opt/gnustep/share/gnustep-patches/packages-ubuntu.txt | xargs $sudo apt-get -q -y install --no-install-recommends
    # the gnustep-2.0 runtime links with gold (or lld)
    $sudo update-alternatives --install /usr/bin/ld ld /usr/bin/ld.gold 10 >/dev/null

    echo "==> FreeCoreData"
    local freecoredata
    freecoredata=$(latest ashalkhakov/FreeCoreData)
    curl -fsSL "https://github.com/ashalkhakov/FreeCoreData/releases/download/v$freecoredata/freecoredata-$freecoredata-ubuntu22.04-$arch.tar.xz" \
        | $sudo tar -C / --no-overwrite-dir -xJ
    echo "  $freecoredata"
    # yours, as CI's runner has it: what a project builds on (udcode-deps) unpacks into it
    $sudo chown -R "$(id -u):$(id -g)" /opt/gnustep

    echo "==> LLVM 18: clangd, lldb-dap"
    if [[ ! -f /etc/apt/sources.list.d/llvm.list ]]; then
        $sudo install -d /etc/apt/keyrings
        curl -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key | $sudo tee /etc/apt/keyrings/llvm.asc >/dev/null
        echo "deb [signed-by=/etc/apt/keyrings/llvm.asc] https://apt.llvm.org/jammy/ llvm-toolchain-jammy-18 main" \
            | $sudo tee /etc/apt/sources.list.d/llvm.list >/dev/null
        $sudo apt-get -q update
    fi
    $sudo apt-get -q -y install --no-install-recommends clangd-18 lldb-18

    echo "==> Building: make, cmake, ninja, gdb, ripgrep; the engines' libraries"
    $sudo apt-get -q -y install --no-install-recommends make cmake ninja-build gdb ripgrep squashfs-tools python3 libsqlite3-dev \
        libsdl2-dev libopenal-dev libvorbis-dev libogg-dev libopus-dev libopusfile-dev libjpeg-dev zlib1g-dev

    echo "==> udcode-deps: what a project builds on"
    $sudo tee /usr/local/bin/udcode-deps >/dev/null << 'EOF'
#!/bin/sh
# What the project in this folder builds on, by the versions its
# .github/pins.env names (UDCodeKit, FreeCoreData, the stack, ...), unpacked
# into /opt/gnustep as its CI does: gnustep-release-actions' deps.sh.
set -e
[ -f .github/pins.env ] || { echo "udcode-deps: no .github/pins.env here; run it in a project's folder" >&2; exit 1; }
script=$(mktemp)
curl -fsSL -o "$script" https://raw.githubusercontent.com/ashalkhakov/gnustep-release-actions/v1/scripts/deps.sh
bash "$script" linux
rm -f "$script"
EOF
    $sudo chmod +x /usr/local/bin/udcode-deps

    echo "==> UDCode"
    local image=$APPIMAGE version
    if [[ -z "$image" ]]; then
        [[ "$arch" == x86_64 ]] || { echo "udcode-box: UDCode's AppImage is x86_64 only (--appimage FILE for another)" >&2; exit 1; }
        version=$(latest ashalkhakov/UDCodeKit)
        image=$(mktemp -d)/UDCode.AppImage
        curl -fsSL -o "$image" "https://github.com/ashalkhakov/UDCodeKit/releases/download/v$version/UDCode-$version-x86_64.AppImage"
    fi
    # Unpacked, not run: an AppImage is an ELF launcher with a squashfs image
    # after it, where its section headers end. Nothing of it runs (no FUSE),
    # and an emulated x86_64 (whose binfmt the AppImage's magic confuses) can
    # unpack it too.
    local offset work
    offset=$(python3 -c 'import struct, sys
data = open(sys.argv[1], "rb").read(64)
shoff, = struct.unpack_from("<Q", data, 0x28)
shentsize, shnum = struct.unpack_from("<HH", data, 0x3A)
print(shoff + shentsize * shnum)' "$image")
    work=$(mktemp -d)
    unsquashfs -q -n -o "$offset" -d "$work/udcode" "$image" >/dev/null
    $sudo rm -rf /opt/udcode
    $sudo mv "$work/udcode" /opt/udcode
    $sudo chmod -R a+rX /opt/udcode
    # GNUstep's tools and libraries on its PATH: what it builds and runs finds them
    $sudo tee /usr/local/bin/udcode >/dev/null << 'EOF'
#!/bin/sh
# UDCode in the box: GNUstep's environment (the stack's GNUstep.sh), then the app.
set +u
. /opt/gnustep/System/Library/Makefiles/GNUstep.sh
export PATH="/usr/lib/llvm-18/bin:$PATH"
exec /opt/udcode/AppRun "$@"
EOF
    $sudo chmod +x /usr/local/bin/udcode
    $sudo install -d /usr/share/applications /usr/share/icons/hicolor/256x256/apps
    $sudo tee /usr/share/applications/udcode.desktop >/dev/null << 'EOF'
[Desktop Entry]
Type=Application
Name=UDCode
Comment=Edit, build and debug C and Objective-C
Exec=/usr/local/bin/udcode %F
Icon=udcode
Categories=Development;IDE;
Terminal=false
EOF
    local icon
    icon=$(find /opt/udcode -maxdepth 2 -name '*.png' | head -n 1)
    [[ -n "$icon" ]] && $sudo cp "$icon" /usr/share/icons/hicolor/256x256/apps/udcode.png
    if command -v distrobox-export >/dev/null 2>&1 && distrobox-export --app udcode; then
        echo "  done: UDCode is in the application menu, or 'distrobox enter $BOX -- udcode'"
    else
        echo "udcode-box: UDCode could not be put in the host's application menu (above: why);" >&2
        echo "  start it with 'distrobox enter $BOX -- udcode'" >&2
    fi
}

if [[ -n "${INSIDE:-}" ]]; then
    inside
    exit 0
fi

# ─── On the host ─────────────────────────────────────────────────────────────

command -v distrobox >/dev/null || { echo "udcode-box: no distrobox here" >&2; exit 1; }
if ! distrobox list --no-color 2>/dev/null | awk -F'|' '{ gsub(/ /, "", $2); print $2 }' | grep -qx "$BOX"; then
    echo "==> Making the box $BOX (Ubuntu 22.04)"
    distrobox create --yes --name "$BOX" --image docker.io/library/ubuntu:22.04
fi
args=(--inside)
[[ -n "$APPIMAGE" ]] && args+=(--appimage "$APPIMAGE")
[[ -n "$STACK" ]] && args+=(--stack "$STACK")
# this script, run again inside the box: from the home it shares
copy="$HOME/.cache/udcode-box/udcode-box.sh"
mkdir -p "$(dirname "$copy")"
cp "${BASH_SOURCE[0]}" "$copy"
distrobox enter "$BOX" -- env UDCODE_BOX="$BOX" bash "$copy" "${args[@]}"
