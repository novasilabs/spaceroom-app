# Architecture

Spaceroom is a native macOS app (SwiftUI, Swift 6 strict concurrency, macOS 14+) split into
two layers:

```
┌───────────────────────────────────────────────────────────────────┐
│ App/Spaceroom (SwiftUI)                                           │
│  AppModel ─ selection, catalog, Restore Center, ignore list        │
│  Modules/*  one @Observable model + view per sidebar module        │
│  MenuBar/  CommandPalette/  Onboarding/  Settings/  DesignSystem/  │
└───────────────▲───────────────────────────────────────────────────┘
                │ value types, async calls (no UI in the engine)
┌───────────────┴───────────────────────────────────────────────────┐
│ Packages/SpaceroomCore (Swift package)                             │
│  Rules ─ RuleCatalog ─ Scanner ─ CleanupEngine ─▶ RestoreStore     │
│  SafetyGuard  IgnoreList  FileStat  PathPattern                    │
│  DiskTree (Space Lens)  Clutter  Applications  Startup  Privacy    │
│  Protection  Maintenance  SystemMonitor  Automations  FuzzyMatch   │
└───────────────────────────────────────────────────────────────────┘
```

The engine has no SwiftUI dependency and no global state, so every piece is unit-tested
against sandboxed fake home folders (`Tests/SpaceroomCoreTests/TestSupport.swift`).

## The cleaning pipeline

1. **Rules** (`Resources/Rules/*.json`) declare paths (`~/Library/Caches/*`), a `why_safe`
   text, a minimum age, apps that must not be running, and whether Smart Care may use
   them. `RuleCatalog` validates them on load: unknown keys, wildcards anywhere except the
   last component, `**`, or roots that are too shallow (for example `~/Documents`) are all
   rejected. If validation fails, **cleaning is disabled** (fail-closed).
2. **Scanner** expands each rule's paths. It leaves an item to the most specific rule that
   claims it, measures it with `getattrlistbulk`, and attaches a `SkipReason` (in use, too
   recent, protected, ignored, …). It never modifies anything.
3. **CleanupEngine** re-verifies every selected item right before it moves. The item must
   still pass `SafetyGuard` (inside its rule's root, no symlink escape, not a protected
   folder), its app must not have started, it must not be on the ignore list, and it must be
   the **same file-system object** that was scanned (device + inode).
4. **RestoreStore** (an actor) moves items into `~/Library/Application Support/Spaceroom/
   Quarantine/<operation>/`: an instant rename on the same volume, or the volume's Trash
   for items on other disks. Items expire after the retention period (1–30 days) or when
   the user chooses *Delete Now*. Deleting makes read-only trees writable first and falls
   back to the Trash for app bundles protected by App Management.

Every other module that removes files (My Clutter, Applications, Privacy, Protection,
Startup, Automations, the menu bar and the command palette) has its own remover with its
own re-checks, but **all of them end in `RestoreStore.quarantine`**.

## The ignore list: a single choke point

`IgnoreList` holds path, app (bundle ID) and rule entries in `ignore.json`. It's enforced
twice:

- **Scans** mark matches `.ignored`, so they're never ticked.
- **`RestoreStore.quarantine`** refuses every ignored move, whichever module asked.

A path protects itself, everything inside it **and every folder that contains it**, so
cleaning a parent folder can't take an ignored file along. If `ignore.json` exists but
can't be decoded, the store is created with `.unavailable` and refuses *all* moves until
the file is fixed.

## Unattended work

Automations and Smart Care's extra tiles only use rules marked `smart_care: true` (regenerable data) and
never act on personal data, cookies or startup items. Missed schedules catch up once after
sleep, and event triggers (low disk, plugged in, login) have cooldowns. The debug snapshot
tour never starts the scheduler, and its Protection checks read a fixture folder.

## Protection

`ProtectionScanner` walks personal folders (bounded depth and file count, skipping tool
folders such as `node_modules`) and reads only what it needs: a 64-byte header, the last 256 KB of images, and PDFs (whole
when under 8 MB, otherwise the first and last 2 MB). It compares magic bytes with the extension (Mach-O, shebang,
compiled AppleScript, ELF, zip) and checks names for bidi controls and double extensions.
It also looks for payloads appended after JPEG/PNG end markers, PDF `/JavaScript` and
`/Launch` actions, and app signatures (`SecStaticCode`) together with the
`com.apple.quarantine` flag. **Nothing is ever executed.**

## Concurrency

- Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY = complete`.
- UI models are `@MainActor @Observable`. Long work runs in `Task.detached` or `nonisolated`
  async functions and hands value types back.
- `RestoreStore` and `AutomationStore` are actors. Shared mutable state elsewhere uses
  `OSAllocatedUnfairLock`.
- Live sampling (CPU, network, battery) runs only while something on screen shows it, so
  the app idles at about 0% CPU.

## Localization

App strings live in a String Catalog (`App/Spaceroom/Resources/Localizable.xcstrings`).
Engine strings use `String(localized:bundle: .module)` with `.strings` tables in
`SpaceroomCore/Resources/Localization`. Rule texts are data, translated through a `Rules`
table keyed by their English text (`Rule.localizedTitle`). See CONTRIBUTING for the sync
workflow.

## Debug tooling (Debug builds only)

- `SPACEROOM_SNAPSHOT_DIR=<dir>` runs a read-only UI tour that captures every screen.
  It never cleans, never writes the ignore list, and points Protection at fake files.
- ⌥⌘T opens the design tuning panel (motion and background parameters).
- `SPACEROOM_EXPORT_ICON=<dir>` renders the app icon set.
