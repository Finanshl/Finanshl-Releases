#!/bin/bash
# Script to install the latest version of Finanshl on macOS

set -euo pipefail

OWNER="Finanshl"
REPOSITORY="Finanshl-Releases"
APP_NAME="Finanshl"
RELEASES_API="https://api.github.com/repos/${OWNER}/${REPOSITORY}/releases/latest"
TEMP_DIR="$(mktemp -d)"
MOUNT_POINT=""

cleanup()
{
    if [ -n "$MOUNT_POINT" ] && mount | grep -Fq "$MOUNT_POINT"
    then
        hdiutil detach "$MOUNT_POINT" -quiet || true
    fi

    rm -rf "$TEMP_DIR"
}

trap cleanup EXIT

case "$(uname -m)" in
    arm64)
        ARCH="arm64"
        ;;
    x86_64)
        ARCH="x64"
        ;;
    *)
        echo "Unsupported Mac architecture: $(uname -m)"
        exit 1
        ;;
esac

echo "Finding the latest Finanshl release for ${ARCH}..."

ASSET_URL="$(
    curl --fail --silent --show-error --location \
        --header "Accept: application/vnd.github+json" \
        --header "User-Agent: Finanshl-installer" \
        "$RELEASES_API" |
    grep -o '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*"' |
    sed 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"//; s/"$//' |
    grep -- "-${ARCH}\\.dmg$" |
    sed -n '1p' || true
)"

if [ -z "$ASSET_URL" ]
then
    echo "Could not find a Finanshl DMG for architecture: ${ARCH}"
    exit 1
fi

DMG_PATH="${TEMP_DIR}/Finanshl.dmg"

echo "Downloading Finanshl..."
curl --fail --location --show-error --progress-bar "$ASSET_URL" --output "$DMG_PATH"

echo "Opening the installer..."
MOUNT_OUTPUT="$(hdiutil attach "$DMG_PATH" -nobrowse -readonly)"
MOUNT_POINT="$(printf '%s\n' "$MOUNT_OUTPUT" | awk -F '\t' '/\/Volumes\// { print $NF; exit }')"

if [ -z "$MOUNT_POINT" ] || [ ! -d "$MOUNT_POINT" ]
then
    echo "Could not mount the Finanshl installer."
    exit 1
fi

APP_SOURCE="$(find "$MOUNT_POINT" -maxdepth 1 -name "${APP_NAME}.app" -print -quit)"

if [ -z "$APP_SOURCE" ]
then
    echo "Could not find ${APP_NAME}.app in the downloaded installer."
    exit 1
fi

echo "Installing Finanshl into /Applications..."
sudo rm -rf "/Applications/${APP_NAME}.app"
sudo ditto "$APP_SOURCE" "/Applications/${APP_NAME}.app"

echo "Clearing macOS quarantine attributes..."
sudo xattr -c "/Applications/${APP_NAME}.app"

echo "Starting Finanshl..."
open "/Applications/${APP_NAME}.app"

echo "Finanshl was installed successfully."
