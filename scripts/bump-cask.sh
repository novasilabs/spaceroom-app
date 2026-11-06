#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Points Casks/spaceroom.rb at the release in dist/: run after `make dmg`, commit, and push
# together with (or right after) publishing the release.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)
SUM_FILE="dist/Spaceroom-$VERSION.dmg.sha256"
[ -f "$SUM_FILE" ] || { echo "✗ $SUM_FILE is missing; run make dmg first." >&2; exit 1; }
SHA=$(cut -d' ' -f1 "$SUM_FILE")

sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" Casks/spaceroom.rb
grep -q "version \"$VERSION\"" Casks/spaceroom.rb && grep -q "$SHA" Casks/spaceroom.rb \
  || { echo "✗ couldn't update Casks/spaceroom.rb" >&2; exit 1; }
echo "✓ Casks/spaceroom.rb → $VERSION ($SHA)"
