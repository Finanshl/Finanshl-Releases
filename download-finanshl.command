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

ASSET_URL=""

RELEASE_JSON="$(curl --fail --silent --show-error --location \
    --retry 3 --retry-delay 2 \
    --header "Accept: application/vnd.github+json" \
    --header "User-Agent: Finanshl-installer" \
    "$RELEASES_API" 2>/dev/null || true)"

if [ -n "$RELEASE_JSON" ]
then
    ASSET_URL="$(printf '%s' "$RELEASE_JSON" |
        grep -o '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*"' |
        sed 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"//; s/"$//' |
        grep -- "-${ARCH}\\.dmg$" |
        sed -n '1p' || true)"
fi

# Fall back to the releases page when api.github.com is unavailable.
if [ -z "$ASSET_URL" ]
then
    RELEASE_PAGE="$(curl --fail --silent --show-error --location \
        --retry 3 --retry-delay 2 \
        --header "User-Agent: Finanshl-installer" \
        "https://github.com/${OWNER}/${REPOSITORY}/releases/latest" 2>/dev/null || true)"

    ASSET_URL="$(printf '%s' "$RELEASE_PAGE" |
        grep -oE 'href="[^"]*Finanshl-[^"]*-[^/]*-${ARCH}\\.dmg"' |
        sed 's/^href="//; s/"$//' |
        sed 's#^/#https://github.com/#' |
        sed -n '1p' || true)"
fi

if [ -z "$ASSET_URL" ]
then
    echo "Could not connect to GitHub or find a Finanshl DMG for architecture: ${ARCH}"
    echo "Please check your internet connection and try again."
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
rm -rf "/Applications/${APP_NAME}.app"
ditto "$APP_SOURCE" "/Applications/${APP_NAME}.app"

echo "Clearing macOS quarantine attributes..."
xattr -c "/Applications/${APP_NAME}.app"

echo "Starting Finanshl..."
open "/Applications/${APP_NAME}.app"

echo "Finanshl was installed successfully."
