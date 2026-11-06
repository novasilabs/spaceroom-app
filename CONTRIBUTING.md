# Contributing to Spaceroom

Thanks for helping! Spaceroom deletes files on people's computers, so **safety reviews come before features**.

## Ground rules

- Be kind and constructive. See our [Code of Conduct](CODE_OF_CONDUCT.md).
- By contributing you agree that your contribution is licensed under **GPL-3.0-or-later**.
- Every Swift file starts with `// SPDX-License-Identifier: GPL-3.0-or-later`.

## Development setup

Requirements: macOS 14+, Xcode 16+, Homebrew.

```bash
make bootstrap   # brew install xcodegen, then generate Spaceroom.xcodeproj
make open        # open in Xcode
make test        # engine tests
make run         # Debug build and launch
make snapshots   # read-only UI tour → build/snapshots (English and Indonesian)
```

`make help` lists everything. The `.xcodeproj` is generated from `project.yml`, so edit
`project.yml`, not the project file. Architecture notes: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

- Swift 6 language mode with strict concurrency checking.
- Tests use **Swift Testing** (`@Test`, `#expect`).
- All user-facing strings go through String Catalogs (`Localizable.xcstrings`). Don't hard-code strings.

## Adding a cleaning rule

Rules live in `Packages/SpaceroomCore/Sources/SpaceroomCore/Resources/Rules/*.json`.

```json
{
  "id": "dev.xcode.derived-data",
  "module": "devCleanup",
  "group": "xcode",
  "title": "Xcode DerivedData",
  "why_safe": "Build intermediates. Xcode rebuilds them on the next build.",
  "rebuild_hint": "Next build takes longer",
  "paths": ["~/Library/Developer/Xcode/DerivedData/*"],
  "skip_if_running": ["com.apple.dt.Xcode"],
  "default_selected": true,
  "smart_care": true
}
```

Checklist for a rule PR:

1. `why_safe` explains in plain language what the data is and what happens after it is removed.
2. The path root is specific: at least two folders below your home folder, or three below `/`. A wildcard may only appear in the last path component, and `**` is not allowed.
3. Use `skip_if_running` / `skip_if_owner_running` when the data belongs to an app that might be using it.
4. Use `default_selected: false` for anything expensive to rebuild (for example iOS DeviceSupport or Gradle caches).
5. Only regenerable data may use `smart_care: true`.
6. Add or extend a test in `RuleCatalogTests`. The catalog validation test must pass.
7. If the rule is ported from Mole, add `"source": "mole"` and the upstream commit hash in `"source_ref"`.

PRs that touch `CleanupEngine`, `SafetyGuard`, `RestoreStore`, or rule files need review from a code owner (see `.github/CODEOWNERS`).

## Pull requests

- Keep PRs focused, with one feature or fix per PR. Open an issue first for larger changes.
- Write commit subjects in the imperative ("Add …", "Fix …"), under 72 characters.
- Include screenshots for UI changes (`make snapshots`), in both languages if the text changed.
- New behaviour comes with tests. Anything that removes files needs a test proving what it
  *doesn't* touch.
- Update `CHANGELOG.md` under **Unreleased**.
- CI must be green: engine tests, the Debug app build and the Release build.

### Safety checklist for code that removes files

- [ ] Goes through `RestoreStore.quarantine` (never `FileManager.removeItem` on user data).
- [ ] Re-checks each item right before moving it (it still exists, it's the same identity, it's inside its root).
- [ ] Respects the ignore list, and is covered by a test with an ignored item.
- [ ] Never acts on personal data, cookies or startup items unattended.

## Translations

Spaceroom ships in English and Bahasa Indonesia (`id`).

- **App text** lives in `App/Spaceroom/Resources/Localizable.xcstrings`. Use `Text("…")`, `String(localized: "…")` or `LocalizedStringResource` — never a plain `String` literal for anything users read. After adding strings, build once, then pull them into the catalog:

  ```bash
  xcrun xcstringstool sync App/Spaceroom/Resources/Localizable.xcstrings \
    $(find build/DerivedData/Build/Intermediates.noindex/Spaceroom.build/Debug -name '*.stringsdata' \
      | grep -v -e DebugSnapshots -e DesignTuningPanel | sed 's/^/--stringsdata /')
  ```

  and add the Indonesian value for each new key (keep every `%@`/`%lld` in the same order).
- **Engine text** (maintenance tasks, health advice, Protection evidence, errors) uses `String(localized: "…", bundle: .module)` in SpaceroomCore; Indonesian goes in `Packages/SpaceroomCore/Sources/SpaceroomCore/Resources/Localization/id.lproj/Localizable.strings`.
- **Cleaning rules** are data: their title, `why_safe` and `rebuild_hint` are translated in `…/id.lproj/Rules.strings`, keyed by the English text. A new rule needs its three lines there too.
- Check a language without changing your Mac: append `-AppleLanguages '(id)' -AppleLocale id_ID` to the snapshot tour command below. Users pick the app's language in System Settings › General › Language & Region › Applications.

## Building a release disk image

```bash
./scripts/make-dmg.sh
```

Builds a universal Release `Spaceroom.app`, checks its signature and writes `dist/Spaceroom-<version>.dmg`. The image has a designed window (background drawn by `scripts/dmg-background.swift`, with icon positions applied through Finder, so macOS asks once to let your terminal control Finder), an Applications shortcut, a bilingual *Read Me First* and a SHA-256 file. Pushing a `v*` tag runs the same script in the **Release** workflow and opens a draft GitHub release. Builds are ad-hoc signed and not notarized. Browser downloads therefore get the Gatekeeper prompt, and the install script (`scripts/install.sh`) and Homebrew cask (`Casks/spaceroom.rb`) avoid it.

**Release checklist:**
1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` and `CLI.version`, and move *Unreleased* in the changelog to the new version.
2. Run `make dmg` and `make cli`.
3. Run `./scripts/bump-cask.sh`.
4. Commit, publish the release with the four files, then push.

The cask's checksum must match the published DMG, or `brew install` refuses it.

## UI snapshot tour (Debug builds)

To check the main screens without clicking through them by hand:

```bash
SPACEROOM_SNAPSHOT_DIR=/tmp/spaceroom-shots \
  build/DerivedData/Build/Products/Debug/Spaceroom.app/Contents/MacOS/Spaceroom
```

The app opens each screen, scans Cleanup and Dev Cleanup (read-only, it never cleans), writes a PNG of each screen to the folder, then quits. Translucent materials render darker in these captures than on screen.

## Regenerating the app icon (Debug builds)

The icon is rendered from `AppIconArtwork` (the sidebar's glass glyph), so it always matches the in-app style:

```bash
SPACEROOM_EXPORT_ICON="$PWD/App/Spaceroom/Resources/Assets.xcassets/AppIcon.appiconset" \
  build/DerivedData/Build/Products/Debug/Spaceroom.app/Contents/MacOS/Spaceroom
```

It writes every size listed in the icon set's `Contents.json`, then quits.
