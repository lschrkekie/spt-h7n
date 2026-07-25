#!/bin/bash -e

# Install the BepInEx client plugins into a local SPT client install (a real
# player's install, or a Fika headless client such as
# ghcr.io/zhliau/fika-headless-docker): the Fika client plugin, SAIN + its
# dependencies (BigBrain, Waypoints - Expanded Navmesh), Dynamic Maps,
# Temporary Fixes, ABPS, HandsAreNotBusy, WTT - Content Backport +
# WTT-CommonLib, Content Backport - Prestiges, and Show Me The Money.
#
# The mod list itself (names + download URLs) lives in mods-manifest.json
# next to this script, not in this file - edit that to bump a version or
# add/remove a mod, both this script and install-client-mods.ps1 read it.
#
# These are BepInEx client plugins - they must be installed on every client
# that renders a raid (human players AND headless clients), not just on the
# dedicated server. Pure server-side mods (Server Value Modifier, Better Keys
# NG, Lacy's PvE Tweaks, APBS) are intentionally NOT included here - they're
# installed server-side only via the egg's INSTALL_OTHER_MODS /
# MOD_URLS_TO_DOWNLOAD mechanism. SVM's config GUI (Greed.exe) has its own
# setup steps documented in MODS-GUIDE.md section 6.
#
# NOTE: WTT - Content Backport alone is ~3.5GB - this script's total download
# is large. Make sure SPT_PATH has several GB free before running.
#
# Usage: install-client-mods.sh [SPT_PATH] [MANIFEST]
#   SPT_PATH defaults to $SPT_PATH env var; if neither is set, you will be
#   prompted for it interactively. Must be the root of an SPT client install
#   (contains BepInEx/ and SPT/).
#   MANIFEST is a local path or http(s) URL to a mods-manifest.json. Defaults
#   to mods-manifest.json next to this script.

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
spt_path=${1:-${SPT_PATH:-}}
manifest=${2:-${MANIFEST:-"$script_dir/mods-manifest.json"}}

if [[ -z "$spt_path" ]]; then
    read -rp "Path to your SPT client install (folder containing BepInEx/): " spt_path
fi

if [[ ! -d "$spt_path" ]]; then
    echo "FATAL: '$spt_path' does not exist."
    exit 1
fi
spt_path=$(cd "$spt_path" && pwd)

if [[ ! -d "$spt_path/BepInEx" ]]; then
    echo "FATAL: '$spt_path' does not look like an SPT client install (no BepInEx/ found)."
    exit 1
fi

for cmd in curl unzip jq; do
    command -v "$cmd" >/dev/null || { echo "FATAL: '$cmd' is required but not found in PATH."; exit 1; }
done

sevenzip_bin=""
for candidate in 7zz 7z; do
    if command -v "$candidate" >/dev/null; then
        sevenzip_bin=$candidate
        break
    fi
done
if [[ -z "$sevenzip_bin" ]]; then
    echo "FATAL: 7-Zip (7zz or 7z) is required but not found in PATH."
    exit 1
fi

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

manifest_file="$tmp_dir/mods-manifest.json"
if [[ "$manifest" == http://* || "$manifest" == https://* ]]; then
    echo "Fetching manifest from $manifest"
    curl -fsSL "$manifest" -o "$manifest_file"
else
    [[ -f "$manifest" ]] || { echo "FATAL: manifest '$manifest' not found."; exit 1; }
    manifest_file=$manifest
fi
jq -e '.mods | type == "array"' "$manifest_file" >/dev/null || { echo "FATAL: '$manifest_file' has no top-level 'mods' array."; exit 1; }

installed=()

install_mod() {
    local name=$1 url=$2
    echo "=== $name ==="

    local mod_download_dir=$tmp_dir/$name/download
    local mod_extract_dir=$tmp_dir/$name/extract
    mkdir -p "$mod_download_dir" "$mod_extract_dir"

    echo "  Downloading..."
    (cd "$mod_download_dir" && curl -f -S -L --progress-bar -A "Mozilla/5.0" -J -O "$url")

    local archive
    archive=$(find "$mod_download_dir" -type f | head -1)

    # Detect the archive format from its magic bytes rather than trusting the
    # downloaded filename - some curl/server combinations name the file after
    # the last URL path segment (e.g. a version number with no extension)
    # instead of the real filename, which breaks extension-based detection.
    # unzip is used for .zip specifically (not 7z) because it correctly turns
    # backslash-separated paths some Windows-built zips use into real nested
    # directories on Linux; 7z just leaves the backslashes in the filename.
    local magic
    magic=$(od -An -N6 -tx1 "$archive" | tr -d ' \n')
    echo "  Extracting..."
    case "$magic" in
        504b*)         unzip "$archive" -d "$mod_extract_dir" ;;
        377abcaf271c*) "$sevenzip_bin" x -y "$archive" -o"$mod_extract_dir" ;;
        *) echo "FATAL: unrecognized archive type for $name ($archive)"; exit 1 ;;
    esac

    echo "  Installing..."
    if [[ -d "$mod_extract_dir/BepInEx/plugins" ]]; then
        mkdir -p "$spt_path/BepInEx/plugins"
        cp -rf "$mod_extract_dir/BepInEx/plugins/." "$spt_path/BepInEx/plugins/"
    fi

    if [[ -d "$mod_extract_dir/BepInEx/patchers" ]]; then
        mkdir -p "$spt_path/BepInEx/patchers"
        cp -rf "$mod_extract_dir/BepInEx/patchers/." "$spt_path/BepInEx/patchers/"
    fi

    if [[ -d "$mod_extract_dir/SPT/user/mods" ]]; then
        mkdir -p "$spt_path/SPT/user/mods"
        cp -rf "$mod_extract_dir/SPT/user/mods/." "$spt_path/SPT/user/mods/"
    fi

    if [[ -d "$mod_extract_dir/EscapeFromTarkov_Data/Managed" ]]; then
        if [[ -d "$spt_path/EscapeFromTarkov_Data/Managed" ]]; then
            cp -f "$mod_extract_dir/EscapeFromTarkov_Data/Managed/"*.dll "$spt_path/EscapeFromTarkov_Data/Managed/" 2>/dev/null || true
        else
            echo "  Note: $name ships EscapeFromTarkov_Data/Managed DLLs, but '$spt_path' has no such folder (no real game client installed here) - skipped."
        fi
    fi

    echo "  $name installed."
    installed+=("$name")
}

while IFS=$'\t' read -r name url; do
    install_mod "$name" "$url"
done < <(jq -r '.mods[] | [.name, .url] | @tsv' "$manifest_file")

echo
echo "Done. Installed: ${installed[*]}"
echo "Restart the client/headless container so BepInEx picks up the new plugins."
