# Changelog

All notable changes to Spaceroom are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.10.2] - 2026-11-07

### Fixed
- **Restore Center**
  - Cleaned files could be deleted for good if the index wasn't saved (full disk, crash, the CLI writing at the same time). Each clean now writes a journal before moving anything. Unknown folders are adopted from the journal, or go to the Trash if there's none; they're never deleted outright. The index is written under a lock and merged with what's on disk.
  - An app restored under a new name kept working only as a folder; it's now `Foo (restored).app`.
  - Expiry runs every hour, not only when the window opens. Choosing a shorter retention asks before deleting older items.
  - *Delete Now* empties items kept in another drive's Trash too.
  - Items that went missing stop counting as restorable.
- **My Clutter**
  - Duplicates could remove the last copy after the copy to keep was removed in another tab. The keeper is now picked again from what's left.
  - Ticks are kept per tab, so Large & Old never shows the Installers and Duplicates pre-ticks.
  - Only downloaded installers (Downloads, Desktop) are pre-ticked.
  - A new scan cancels the old one, which could otherwise overwrite it.
- **Applications**
  - Uninstalling Chrome no longer takes Chrome Canary's data. The same goes for any installed app whose ID starts with the one being removed, and for launch agents.
  - Leftovers of an app that's running now are skipped.
  - Smart Care's Applications tile rescans each time instead of reusing a stale list.
  - *Remove Data* refreshes the list.
  - Uninstall waits for the leftover scan.
  - The Leftovers tab shows when it's still looking.
- **Space Lens**
  - *Always Ignore* after a startup-disk scan really protects the item now: ignore paths are canonical.
  - A removal that finishes after Undo or a new scan no longer overwrites the newer map.
  - Hard-linked files count once across the whole scan.
- **Smart Care:** Undo, *Free Up Now* and the headline cover the Protection and Applications tiles too.
- **Review Details:** ticking one item of an unticked category ticks just that item.
- **Running programs**
  - Project build folders check for programs running from them, at scan and at clean time.
  - The clean-time check for a running app matches the scan's (`com.foo.plist`).
- **Startup:** a job is stopped only once its plist has actually moved.
- **Protection**
  - Code appended to a JPEG or PNG is found by walking the image's structure, so a large payload can't hide behind its own `FF D9`.
  - Downloaded scripts are reported when they're hidden, and when they're bundles (`.workflow`, `.scptd`).
  - Migrating the old ignore list no longer loses it when it can't be saved.
- **Privacy:** Undo waits until the browser is closed.
- **Docker:** the build cache is pruned with `--all`, matching the size shown, and image sizes are labelled "up to".
- **Status:** rates and charts start fresh when you come back to the screen.
- **Automations:** a run can't start twice.
- **CLI:** `spaceroom restore` no longer counts failed items as restored, and `clean` checks again right before moving that the app isn't open.
- **Other:** remaining English-only texts are translated.
- **Disk image:** the build now waits for Finder to save the window background, retries, and fails instead of shipping a plain window. 0.10.1's image had lost its design this way.

## [0.10.1] - 2026-11-07

### Fixed
- **Removed apps could still be opened.** macOS kept launching an app from the Restore Center (Spotlight, *Open With*, its links, `open -b`) for as long as it was kept. Apps are now stored under a name that isn't an app bundle, and they get their name back when restored. This also applies to apps removed by Protection, Space Lens and the Trash rule.
- **Running programs were moved out from under themselves.** Protection and Space Lens now check every running process by path and skip anything running, with "Quit it first". Uninstalling also catches a running helper or second copy, not just the app's bundle ID.
- **Space Lens could remove apps**, which skipped their leftovers and the running check. Apps, and folders with apps in them (checked on disk right before removal), are now left to Applications.
- **Uninstall missed data kept in vendor folders**, such as `Application Support/Google/AndroidStudio2025.2` or `Caches/JetBrains/IntelliJIdea2025.1`. Exact names and versioned names are matched; similar products (Google/Chrome for Testing) are not.
- Uninstalling an old copy of Spaceroom no longer lists the running Spaceroom's own data, which can't be moved into itself.

### Added
- **Applications:** a *Remove everything, including personal data* switch for a true deep clean (still restorable). There's also a note when other copies of the app are on the Mac, on a disk image or in a build folder, since they stay launchable. Spaceroom itself points to the new **Settings › Uninstall Spaceroom…**, which moves the app, its settings and its data (including the Restore Center) to the Trash, then quits.
- **Startup:** after removing a launch agent whose app is still installed, Spaceroom says the app may add it back, and how to stop it for good.
- **Privacy:** a note that browser sync (Chrome Sync, iCloud for Safari) can bring history back from other devices.

## [0.10.0] - 2026-11-06

### Added
- **`spaceroom` command-line tool:** `scan`, `clean` (`--dry-run`, `--yes`), `status`, `history` and `restore <id>`, with `--json` output. It uses the same rules, safety checks, ignore list and Restore Center as the app. `clean` takes the categories ticked by default, asks before moving anything, and refuses to run while the app is open. Build it with `make cli` or install it with `make install-cli`. Releases attach a universal tarball.
- **Applications › Updates:** checks for newer versions, but only when you click *Check for Updates*. It reads Sparkle feeds over HTTPS, using each app's own `SUFeedURL`, and asks Apple's App Store lookup about App Store apps. Beta channels and releases for newer macOS are skipped. *Open to Update* lets the app's own updater install, and *Open App Store* goes to the store page. Spaceroom never downloads or installs anything itself. "Slim apps" (stripping architectures) is deliberately not offered: it breaks code signatures.
- **My Clutter › Similar Photos:** groups bursts, retakes and edited copies using Apple's Vision feature prints, entirely on the Mac. It compares photos in the same folder taken within a day of each other, from 200 KB up, the 8,000 newest. You can choose how alike they must be: *Nearly identical*, *Similar* or *Loosely similar*. The best photo of each group (most pixels, then largest file) is marked Keep and can't be ticked. Nothing is ticked for you; *Tick All but the Best* does it in one click. Photos inside the Photos library aren't included.
- **Space Lens growth history:** each complete scan saves folder sizes (three levels deep, 10 MB and up, the last 30 scans per folder) to `~/Library/Application Support/Spaceroom/SpaceLens`. The next scan shows what grew or shrank since then, in the header and on every row, and marks new folders.
- **Space Lens on external drives:** items on local, writable external drives can be removed too. They go to that drive's Trash and are tracked by the Restore Center. Time Machine drives, a drive's system folders and its hidden top-level folders are refused.
- **Space Lens › Treemap:** switch between the sunburst and a squarified treemap with two levels of nesting. Both charts outline the items you've ticked.
- **Cleanup:** three new categories. **Mail attachments** are copies of attachments you opened; the originals stay in your mailboxes. **Photos caches** are the face and scene analysis working files. **Broken preferences** are preference files that are empty or don't parse; Apple's own are never included, and none are ticked by default. A new `content_check` rule field supports the last one. Files macOS won't let Spaceroom read are never counted as broken.
- **Dev Cleanup › Docker:** a card that shows Docker's build cache and untagged ("dangling") images, then lets Docker remove them (`docker builder prune`, `docker image prune`, never `-a`). It works with Docker Desktop, OrbStack, Colima and Rancher Desktop. This is the one clean that can't go to the Restore Center, so it has its own button and says so first. Containers, volumes and tagged images are never touched, and Spaceroom never starts Docker.
- **Dev Cleanup › Project build folders:** `node_modules`, web framework caches (`.next`, `.nuxt`, `.svelte-kit`, `.turbo`, `.parcel-cache`), Rust and Maven `target`, SwiftPM `.build`, Gradle `build`, CocoaPods `Pods` and Python virtual environments. Only projects with no changes for 30 days qualify, counting your own files and Git's index but not the build folders. Anything Git tracks is never offered. Searches `~/development`, `~/Developer`, `~/Projects`, `~/code`, `~/Documents` and similar folders. Never cleaned unattended.
- **Space Lens:** tick files and folders in the list and choose *Review and Remove*. They go to the Restore Center like every other clean, and Undo puts the map back. Only items in your home folder can be removed. Its top-level folders, the folders directly inside `~/Library`, Keychains and Spaceroom's own data stay locked, with the reason shown.

### Changed
- **New bundle identifier:** `com.novasilabs.spaceroom` (was `io.github.spaceroom-app.spaceroom`). Your settings carry over on first launch, and the Restore Center and ignore list stay where they are. macOS ties permissions to the identifier, so after updating you need to grant **Full Disk Access** again, and allow notifications again if you use Automations.

### Fixed
- Command-line tools (Git, Docker) write their output to a temporary file instead of a pipe, so a tool started at the same moment elsewhere can't hold the pipe open and stall the scan.
- Categories inside folders that macOS protects (such as Mail's container) now show *Needs Full Disk Access* instead of disappearing.
- **Space Lens:** a fast double-click could open the same folder twice ("Library › Library"), and clicking an outer ring skipped the folders in between in the breadcrumb.

## [0.9.0] - 2026-11-05

First public beta. Ad-hoc signed and not yet notarized (see the README for the
first-launch steps).

### Added
- **Smart Care:** one scan across system junk, developer junk and the Trash, plus
  Protection, Speed and Applications tiles with their own toggles and a single Undo.
- **Cleanup** and **Dev Cleanup:** scan → review → clean → undo, with 16 rules covering user
  caches, logs, browser caches, the Trash, Xcode, simulators and package-manager caches.
- **My Clutter:** large and old files, duplicates confirmed by content (one copy is always
  kept) and installer downloads.
- **Space Lens:** a live sunburst map of any folder or disk, with drill-in and a size list.
- **System Status:** a health score with advice, plus live CPU, memory, swap, network, disk,
  battery and thermal state, and the busiest processes.
- **Applications:** uninstall with leftovers (personal data unticked), and find leftovers of
  removed apps.
- **Startup & Background:** a launch item audit with signature checks, and a security
  overview (SIP, Gatekeeper, FileVault, Firewall, XProtect).
- **Protection:** finds files disguised to trick you into running them (programs posing as
  documents, misleading names, payloads hidden in images, active PDFs, unsigned apps,
  downloaded scripts). It reads headers only.
- **Performance:** maintenance tasks with honest skip reasons. Admin tasks stay locked
  until the helper exists.
- **Privacy:** clears browser traces and recent items (never passwords or bookmarks), and
  shows a read-only review of app permissions.
- **Automations:** "when → do" rules that only run Smart Care–safe cleaning.
- **Restore Center:** everything cleaned is restorable for 1–30 days, with bulk restore and
  bulk delete.
- **Ignore list:** *Always Ignore* from any module, enforced by every scan and by the
  Restore Center, and fail-closed.
- **Menu bar:** one item combining storage, CPU and memory, with a popover of quick cleans,
  health, battery, network and Protection status.
- **⌘K command palette** with fuzzy search, plus quick cleans that measure first and ask.
- A five-step **welcome tour**, including Full Disk Access with live detection.
- **Bahasa Indonesia** translation.
- Release packaging (`scripts/make-dmg.sh`): a universal app in a designed disk image.

[Unreleased]: https://github.com/novasilabs/spaceroom-app/compare/v0.10.2...HEAD
[0.10.2]: https://github.com/novasilabs/spaceroom-app/compare/v0.10.1...v0.10.2
[0.10.1]: https://github.com/novasilabs/spaceroom-app/compare/v0.10.0...v0.10.1
[0.10.0]: https://github.com/novasilabs/spaceroom-app/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/novasilabs/spaceroom-app/releases/tag/v0.9.0
