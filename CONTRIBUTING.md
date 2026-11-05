# Contributing to Spaceroom

Thanks for helping! Spaceroom deletes files on people's computers, so **safety reviews come before features**.

## Ground rules

- Be kind and constructive. We follow the spirit of the [Contributor Covenant](https://www.contributor-covenant.org/).
- By contributing you agree that your contribution is licensed under **GPL-3.0-or-later**.
- Every Swift file starts with `// SPDX-License-Identifier: GPL-3.0-or-later`.

## Development setup

```bash
brew install xcodegen
xcodegen generate
open Spaceroom.xcodeproj
swift test --package-path Packages/SpaceroomCore
```

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

- Keep PRs focused, with one feature or fix per PR.
- Include screenshots for UI changes.
- CI must be green: core tests and the app build.

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
