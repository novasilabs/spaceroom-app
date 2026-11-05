# Changelog

All notable changes to Spaceroom are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **Space Lens:** tick files and folders in the list and choose *Review and Remove*. They go to the Restore Center like every other clean, and Undo puts the map back. Only items in your home folder can be removed. Its top-level folders, the folders directly inside `~/Library`, Keychains and Spaceroom's own data stay locked, with the reason shown.

### Fixed
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

[Unreleased]: https://github.com/novasilabs/spaceroom-app/compare/v0.9.0...HEAD
[0.9.0]: https://github.com/novasilabs/spaceroom-app/releases/tag/v0.9.0
