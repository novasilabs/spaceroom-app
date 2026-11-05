# Spaceroom

**Give your Mac room again.** Spaceroom is a free, open-source, native SwiftUI app that cleans junk, removes apps completely, and shows what's happening on your Mac. Everything it removes can be undone.

> Status: **M1 in progress** (pre-alpha). Not ready for daily use yet. See [docs/PRD.md](docs/PRD.md) for the full product plan.

## Promises

- **See everything.** Every item comes with a size, a location and a plain-language "why is this safe?".
- **Undo anything.** Cleaned items go to the Restore Center and are kept for 7 days by default, not deleted right away.
- **Nothing leaves your Mac.** No account, no telemetry. All analysis happens on-device.

## What works so far

| Area | State |
|---|---|
| App shell: sidebar, per-module gradients, design system | ✅ |
| Cleanup and Dev Cleanup: scan → review → clean → undo | ✅ (starter rule set) |
| Restore Center: timeline, restore item / operation, delete now, automatic expiry | ✅ |
| Full Disk Access onboarding with live detection | ✅ |
| Menu bar: one Spaceroom item combining the readings you pick (storage ring with free space, CPU, memory; turns amber/red when low), one popover with storage, one-click undoable actions (Trash, App Caches, DerivedData, Simulators), CPU/memory graphs, battery, network speed, Protection status, last cleanup with Undo | ✅ (M1, v1.0) |
| Smart Care: one scan across every module (safe, regenerable rules only), System Junk / Developer Junk / Trash tiles, disk-after-cleaning tile, single Undo; opens first and runs from the menu bar | ✅ (M1) |
| Space Lens: map of the home folder, startup disk or external drives as an interactive sunburst (hover, click to drill in, breadcrumb, linked size list), grows live while scanning, shows "system & hidden" space the scan can't see | ✅ (M1) |
| Applications: installed apps with size, source and last opened; uninstall with leftovers (caches, logs, settings, containers, launch agents — personal data unticked by default); leftovers of apps already removed; everything undoable via the Restore Center | ✅ (M1) |
| My Clutter: large & old files (size and age filters), duplicates confirmed by content with a protected "Keep" copy, installer downloads with their source; your own files only, never app data | ✅ (M1) |
| Restore Center bulk actions: select, Restore All / Delete All | ✅ |
| System Status: health score with what to fix, CPU (per core, load), memory and swap, network, disk, battery health and cycles, thermal state, busiest processes with Quit for apps; samples only while visible | ✅ (v0.5) |
| Startup & Background: launch agents, daemons and in-app helpers with signature badges and audit findings (program missing, app removed, empty job, unsigned, unusual location); remove your own agents via the Restore Center; SIP / Gatekeeper / FileVault / Firewall / XProtect overview | ✅ (v0.5) |
| Performance: maintenance tasks (Quick Look, “Open With” list, font caches, startup disk check) with when-it-helps notes, last run and live status; admin tasks (DNS, Spotlight, purge) shown but never run until the privileged helper exists | ✅ (v0.5) |
| Privacy: clear browser history, cookies, form autofill and download history (Safari, Chrome, Dia, Arc, Edge, Brave, Vivaldi, Firefox) plus recent-items lists, undoable from the Restore Center; never touches saved passwords or bookmarks, refuses while the browser is open; read-only review of which apps hold camera, microphone, screen recording and other permissions | ✅ (v0.5) |
| Protection: finds files disguised to trick you — programs named like photos or documents, misleading names (`invoice.pdf.app`, hidden right-to-left characters), code hidden after an image, PDFs that run JavaScript or launch programs, unsigned apps outside /Applications, downloaded scripts; reads headers only and never runs anything; findings move to the Restore Center; security strip (SIP, Gatekeeper, FileVault, Firewall, XProtect) | ✅ (v1.0) |
| ⌘K command palette: jump to any module, run actions (Smart Care, scans, Empty Trash, DerivedData, malware scan), find apps to uninstall, run automations; anything that removes files measures first and asks | ✅ (v1.0) |
| Automations: "when → do" rules (daily or weekly schedule, low disk, at login, plugged in → check and notify, Smart Care clean, empty Trash, clear old Xcode builds); only Smart Care–safe rules run unattended, cleaning goes to the Restore Center unless you choose to free space right away; missed schedules catch up once after sleep; run history with Undo and notifications | ✅ (v1.0) |

## Requirements

- macOS 14 Sonoma or later (Apple Silicon or Intel)
- To build: Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build & run

```bash
xcodegen generate
open Spaceroom.xcodeproj
```

Or from the command line:

```bash
xcodegen generate && xcodebuild -project Spaceroom.xcodeproj -scheme Spaceroom -configuration Debug build
```

Run the core engine tests:

```bash
swift test --package-path Packages/SpaceroomCore
```

## Project layout

```
App/Spaceroom/                 SwiftUI app (views, design system, app state)
Packages/SpaceroomCore/        Engine: rules, scanner, safety guard, cleaner, Restore Center store
  Sources/SpaceroomCore/Resources/Rules/   Cleaning rules (JSON) — the main place to contribute
docs/PRD.md                    Product requirements
project.yml                    XcodeGen project definition (the .xcodeproj is generated, not committed)
```

## How cleaning works

1. **Rules** (JSON) declare what may be cleaned, why it's safe, and when to skip it (for example "skip while Xcode is running").
2. The **scanner** expands each rule's paths, measures sizes, and marks items that are in use.
3. The **safety guard** refuses anything outside the rule's root folder, anything reached through a symlink, protected system and user folders, and anything that was swapped after the scan (device and inode re-check).
4. The **cleaner** moves the items into the **Restore Center**. That's an instant rename on the same disk; items on other disks go to that disk's Trash. Nothing is permanently deleted until the retention period ends or you choose **Delete now**.

If the rule set fails to load or validate, cleaning is disabled. Scanning still works.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). New cleaning rules are the most valuable contribution. Every rule needs a "why safe" text and a test.

## Credits

Spaceroom's feature set and several safety heuristics are inspired by [Mole](https://github.com/tw93/mole) by tw93 (GPL-3.0). Rules ported from Mole are marked with `"source": "mole"`. See [NOTICE](NOTICE).

## License

[GPL-3.0-or-later](LICENSE). Spaceroom is not affiliated with Apple, MacPaw (CleanMyMac) or the Mole project. "Mac" is a trademark of Apple Inc.
