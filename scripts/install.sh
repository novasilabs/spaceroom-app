#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Installs the latest Spaceroom release into /Applications.
#
#   curl -fsSL https://raw.githubusercontent.com/novasilabs/spaceroom-app/main/scripts/install.sh | bash
#
# What it does, so you can check before running it:
#   1. asks GitHub for the newest release (pre-releases included, drafts never);
#   2. downloads Spaceroom-<version>.dmg and its .sha256, and stops if they don't match;
#   3. mounts the image read-only, copies Spaceroom.app into /Applications (or ~/Applications
#      when /Applications isn't writable), and ejects it.
# Files downloaded with curl aren't flagged as "from the internet", so macOS opens the app
# without the "can't check it for malicious software" prompt that browser downloads get.
# Nothing else is installed, and nothing runs as root.
#
# Options (environment variables):
#   SPACEROOM_VERSION=0.10.2      install that version instead of the newest
#   SPACEROOM_INSTALL_DIR=<dir>   install somewhere else
set -euo pipefail

REPO="novasilabs/spaceroom-app"
API="https://api.github.com/repos/$REPO/releases"

say() { printf '%s\n' "$*"; }
fail() { printf 'spaceroom install: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "Spaceroom runs on macOS only."
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 14 ] || fail "Spaceroom needs macOS 14 Sonoma or later (this Mac has $(sw_vers -productVersion))."

if [ -n "${SPACEROOM_VERSION:-}" ]; then
  version="${SPACEROOM_VERSION#v}"
else
  # The first non-draft release in GitHub's list is the newest one.
  version=$(curl -fsSL -H "Accept: application/vnd.github+json" "$API?per_page=10" \
    | /usr/bin/python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin) if not x["draft"]]; print(r[0]["tag_name"].lstrip("v") if r else "")') \
    || fail "couldn't ask GitHub for the latest release."
  [ -n "$version" ] || fail "no release found."
fi

base="https://github.com/$REPO/releases/download/v$version"
dmg="Spaceroom-$version.dmg"
work=$(mktemp -d "${TMPDIR:-/tmp}/spaceroom-install.XXXXXX")
mount=""
cleanup() {
  [ -n "$mount" ] && hdiutil detach -quiet "$mount" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

say "▸ Downloading Spaceroom $version"
curl -fL --progress-bar -o "$work/$dmg" "$base/$dmg" || fail "download failed."
curl -fsSL -o "$work/$dmg.sha256" "$base/$dmg.sha256" || fail "couldn't download the checksum."

say "▸ Checking the download"
(cd "$work" && shasum -a 256 -c "$dmg.sha256" >/dev/null) || fail "the checksum doesn't match; nothing was installed."

say "▸ Installing"
mount=$(hdiutil attach -nobrowse -readonly -noverify "$work/$dmg" | awk -F'\t' '/\/Volumes\//{print $NF}')
[ -d "$mount/Spaceroom.app" ] || fail "the disk image doesn't contain Spaceroom.app."

target="${SPACEROOM_INSTALL_DIR:-/Applications}"
if [ -z "${SPACEROOM_INSTALL_DIR:-}" ] && [ ! -w "$target" ]; then
  target="$HOME/Applications"
fi
mkdir -p "$target"

if pgrep -xq Spaceroom; then
  say "  Quitting the running Spaceroom first"
  osascript -e 'tell application id "com.novasilabs.spaceroom" to quit' >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do pgrep -xq Spaceroom || break; sleep 0.5; done
  pgrep -xq Spaceroom && fail "Spaceroom is still running. Quit it and run this again."
fi

# Replace the old copy (ditto keeps the code signature intact).
if [ -d "$target/Spaceroom.app" ]; then
  mv "$target/Spaceroom.app" "$work/Spaceroom-previous.app"
fi
if ! ditto "$mount/Spaceroom.app" "$target/Spaceroom.app"; then
  [ -d "$work/Spaceroom-previous.app" ] && mv "$work/Spaceroom-previous.app" "$target/Spaceroom.app"
  fail "couldn't copy Spaceroom into $target."
fi
codesign --verify --deep --strict "$target/Spaceroom.app" 2>/dev/null || fail "the installed app's signature doesn't verify."

say "✓ Spaceroom $version is in $target"
say "  Open it from Launchpad or Spotlight. Your settings and the Restore Center are kept."
