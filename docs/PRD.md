# PRD — Spaceroom: a native macOS cleaner & system care app

| | |
|---|---|
| **Status** | Draft v0.2 — all open questions resolved, ready for M0 |
| **Date** | 2026-11-04 |
| **Name** | **Spaceroom** — marketed as "Spaceroom for Mac" (decided 2026-11-04). CLI: `spaceroom`. Bundle ID: TBD (e.g. `com.<org>.spaceroom`) |
| **Platform** | **macOS 14 Sonoma+** (decided 2026-11-04), Apple Silicon + Intel, SwiftUI-native; Liquid Glass on macOS 26+ |
| **License** | **GPL-3.0-or-later** — free & open source (decided 2026-11-04) |
| **References** | [CleanMyMac](https://cleanmymac.com/) (UX benchmark), [Mole](https://github.com/tw93/mole) (feature/safety benchmark) |

---

## 1. Summary

Spaceroom is a native SwiftUI Mac app that frees disk space, removes apps completely, keeps the Mac fast, and shows what is happening on the system. It takes the **polished, one-button, illustrated UX of CleanMyMac** and combines it with the **depth, transparency and developer focus of Mole** (dev-artifact purge, installer cleanup, app slimming, live status, dry-run, operations log).

Our differentiator is **trust**: every action is explained, previewed, reversible, and logged. Nothing is deleted that the user cannot see, understand, and undo.

## 2. Problem

- Macs fill up silently: caches, logs, Xcode DerivedData, `node_modules`, Docker images, old installers, app leftovers.
- **CleanMyMac** is beautiful but opaque ("trust us, 12 GB of junk"), subscription-priced, and weak for developers.
- **Mole** is powerful and transparent but is a terminal tool: unusable for most people, and even developers lack visual browsing, history, and undo. `clean`, `purge` and `installer` delete permanently.
- Nothing on the market combines a beautiful consumer UX with developer-grade cleanup and full reversibility.

## 3. Goals & non-goals

### Goals
1. **One click to a healthy Mac** — Smart Care scan + clean in < 60 s on a typical machine.
2. **Zero-regret cleaning** — every deletion is reversible for N days (Restore Center), with a plain-language reason why it is safe.
3. **Best-in-class developer cleanup** — Xcode, simulators, Docker, package managers, build artifacts.
4. **Native, fast, beautiful** — SwiftUI, 60 fps animations, < 150 MB RAM idle, menu bar app < 30 MB.
5. **Privacy first** — no account, no telemetry by default, all analysis on-device.

### Non-goals (v1)
- A proprietary antivirus engine (we do a persistence/startup audit instead; see §6.8).
- Cloud storage cleanup (Google Drive / Dropbox / OneDrive APIs) — post-v1.
- Windows/Linux versions.
- Mac App Store distribution (sandbox makes the product impossible; see §9).

## 4. Target users

| Persona | Needs | Key modules |
|---|---|---|
| **Everyday user** "Rina" — MacBook Air 256 GB, "storage almost full" popups | One button, reassurance, no jargon | Smart Care, Cleanup, Space Lens, Uninstaller |
| **Developer** "Dimas" — Xcode, Node, Docker, 30 projects | Reclaim tens of GB safely, knows what DerivedData is, wants control | Dev Cleanup, Space Lens, Status, CLI |
| **Power user / IT** — manages several Macs | Startup audit, scheduling, logs, scripting | Startup & Background, Automations, History, CLI |

## 5. Competitive feature matrix

| Capability | CleanMyMac | Mole CLI | **Spaceroom** |
|---|:-:|:-:|:-:|
| One-click Smart Care | ✅ | ❌ | ✅ |
| System junk / caches / logs | ✅ | ✅ | ✅ |
| Leftovers of already-deleted apps | ⚠️ | ✅ | ✅ |
| Uninstaller w/ leftovers | ✅ | ✅ | ✅ + config-reference finder |
| App updater | ✅ | ❌ | ✅ (v1.0) |
| Dev artifacts (`node_modules`, `target`, DerivedData…) | ⚠️ | ✅ | ✅ grouped by project, git-aware |
| Installer files (.dmg/.pkg/.xip) | ⚠️ | ✅ | ✅ |
| Strip Intel code from universal apps | ❌ | ✅ | ✅ |
| Disk map (Space Lens) | ✅ | ✅ (TUI) | ✅ sunburst + treemap + **growth history** |
| Duplicates / similar photos | ✅ | ❌ | ✅ |
| Large & old files | ✅ | ❌ | ✅ |
| Maintenance tasks (DNS, Spotlight, LaunchServices…) | ✅ | ✅ | ✅ with skip-reasons |
| Startup / login / background items | ✅ | ❌ | ✅ + signature & persistence audit |
| Malware scan | ✅ (own engine) | ❌ | ⚠️ persistence audit + XProtect status only |
| Privacy (browser data, recent items) | ✅ | ❌ | ✅ |
| Live status + health score | Menu app | ✅ | ✅ window + menu bar |
| Dry run / preview | Review step | ✅ | ✅ always |
| **Undo / quarantine** | Trash only | Trash only for some | ✅ **Restore Center for everything** |
| Operations log / history | ❌ | ✅ | ✅ visual timeline |
| Whitelist / ignore list | ✅ | ✅ | ✅ |
| Scheduling / automation | ⚠️ reminders | ❌ | ✅ rules |
| CLI | ❌ | ✅ | ✅ (v1.0, same engine) |
| Price / license | Subscription, proprietary | Free, GPL-3.0 | **Free, GPL-3.0** |

## 6. Information architecture — new menu

CleanMyMac's sidebar is reorganised so that each item answers a user question, and three new modules (marked **NEW**) are added.

```
┌──────────────────────────┐
│  ◉ Smart Care            │  "Just make my Mac better"
│                          │
│  CLEAN                   │
│  ◌ Cleanup               │  system junk, caches, logs, trash, mail, photos junk
│  ◌ Dev Cleanup     NEW   │  Xcode, simulators, Docker, package managers, build artifacts
│  ◌ My Clutter            │  large & old, duplicates, similar photos, installers, downloads
│                          │
│  UNDERSTAND              │
│  ◌ Space Lens            │  visual disk map + growth over time
│  ◌ System Status   NEW   │  live CPU/RAM/disk/net/battery/thermals + health score
│                          │
│  MANAGE                  │
│  ◌ Applications          │  uninstaller, updater, leftovers, app slimming
│  ◌ Startup & Background  │  login items, launch agents/daemons, extensions + audit
│  ◌ Performance           │  maintenance tasks, RAM, heavy consumers
│  ◌ Privacy               │  browser data, recent items, permissions review
│                          │
│  ─────────────           │
│  ◌ Restore Center  NEW   │  quarantine + history timeline + undo
│  ◌ Automations     NEW   │  schedules & rules  (v1.0)
└──────────────────────────┘
```

Each module follows **one consistent 3-state flow** (CleanMyMac's strongest UX trait):

1. **Intro** — illustration, one-sentence promise, big circular **Scan** button.
2. **Results** — headline number ("8.4 GB can be cleaned"), category cards, primary **Clean** button, secondary **Review Details**.
3. **Done** — what changed, space reclaimed, "Undo" link to Restore Center, suggestion of the next module.

**Review Details** opens a two-pane view: categories on the left with checkboxes and sizes, items on the right with path, size, last-used date, **"Why is this safe?"** explanation, Reveal in Finder, Quick Look, and "Always ignore".

### 6.1 Smart Care (one-click)
- Runs in parallel: Cleanup (safe set), Dev Cleanup (safe set only — caches, not projects), Trash, Installers older than 30 d, maintenance tasks due, startup items flagged, app updates available.
- Result screen: up to 5 tiles (Cleanup / Protection / Speed / Applications / Clutter), each with its own toggle and "Review".
- **Run** executes all enabled tiles; per-tile progress rings.
- Never touches user documents, photos, or project folders in one-click mode.

### 6.2 Cleanup
Categories (each a rule set, see §8.3):
- User caches, system caches (admin), app logs, system logs (admin), crash reports, diagnostic reports
- Language files (unused localizations) — opt-in, off by default
- Broken preferences / broken login items
- Leftovers of already-uninstalled apps (Mole `clean`)
- Mail attachments & downloads (read-only Mail folders, quarantined only)
- Photos junk (caches, not originals)
- iOS/iPadOS device backups & software updates (`.ipsw`)
- Trash bins (user + external volumes, separately toggled)
- Browser caches (Safari, Chrome, Arc, Firefox, Edge, Brave)
- In-use items are skipped with a reason ("Slack is running — close it to clean 1.2 GB").

### 6.3 Dev Cleanup — NEW
For developers; hidden behind a one-time "Are you a developer?" detection (Xcode/Homebrew/Node presence) but always reachable.

| Group | Targets |
|---|---|
| **Xcode** | DerivedData, Archives (keep latest N per app), iOS DeviceSupport for unused OS versions, unavailable/old Simulators & runtimes, Previews cache, module cache |
| **Containers** | Docker/OrbStack/Colima: dangling images, stopped containers, build cache (via their CLIs, never raw file deletion) |
| **Package managers** | Homebrew cache & old versions, npm/pnpm/yarn/bun caches, pip/uv/poetry, Cargo registry, Go mod cache, Gradle/Maven, CocoaPods, SwiftPM, Ruby gems, Composer |
| **Project artifacts** (Mole `purge`) | `node_modules`, `target`, `.build`, `build`, `dist`, `.next`, `.turbo`, `__pycache__`, `.venv`, `Pods` — grouped by project |
| **IDE** | JetBrains caches & old IDE versions, VS Code/Cursor extension caches, old Android SDK/emulator images |

Safety rules (from Mole, extended):
- Project artifacts touched in the last 7 days are unselected by default.
- Never delete git-tracked files; skip nested repos; skip dirs containing keypairs/`.env` deployment files.
- Show "rebuild cost" hint ("`npm install` to restore, ~2 min").
- Scan roots configurable (default: `~/Developer`, `~/Projects`, `~/GitHub`, `~/dev`, `~/code`).

### 6.4 My Clutter
- **Large & Old files** — size/age filters, kind facets (video, archives, disk images…).
- **Duplicates** — size → partial hash → full hash (BLAKE3/SHA-256); smart "keep the original" auto-select (oldest, in Photos library, not in Downloads).
- **Similar photos** — Vision `VNFeaturePrintObservation` clustering; picks best (sharpness, faces, resolution). Photos library items go through PhotoKit deletion (lands in "Recently Deleted").
- **Installers** (Mole `installer`) — `.dmg .pkg .mpkg .iso .xip` + installer `.zip` in Downloads, Desktop, Homebrew cache, Mail, Messaging apps; shows source app via `kMDItemWhereFroms`.
- **Downloads** — sorted by age and "already installed" (e.g. the DMG of an app you already have).

### 6.5 Space Lens
- Fast full-disk scan (`getattrlistbulk`, parallel, APFS-aware for clones/purgeable space).
- Two views: **Sunburst** (CleanMyMac-style bubbles/rings) and **Treemap**; list sidebar sorted by size.
- Drill-down, breadcrumb, Quick Look, Reveal, Move to Trash (via Restore Center).
- **NEW — Growth history**: stores lightweight snapshots of top-level folder sizes; shows "what grew since last week" (e.g. "+14 GB in `~/Library/Containers/com.docker.docker`").
- External volumes listed separately; partial sizes marked `≈`.

### 6.6 System Status — NEW (from Mole `status`)
- Live dashboard: CPU (total + per core, P/E cores), memory pressure & swap, disk usage & I/O, network throughput, battery health & cycle count, thermals/fans (where available), uptime.
- **Health score** (0–100, colour-coded) from CPU, memory pressure, disk free %, SMART, thermals, battery, uptime — with "what would improve it" tips that link to modules.
- Top processes with "sustained high CPU" alerts (read-only; Quit/Force Quit require confirmation).
- Same data powers the menu bar app (§6.12).

### 6.7 Applications
- **Uninstaller** — list with size, last opened, source (App Store / Developer ID / Homebrew cask / Setapp), architecture. Removes app + LaunchAgents, prefs, containers, caches, app support.
  - Personal data (settings, plugins, browser profiles) unselected by default, choose per path (Mole behaviour).
  - Shared data kept if another installed app uses it.
  - Homebrew casks uninstalled via `brew uninstall --cask` to keep brew state consistent.
  - **Config references**: lists lines in shell rc files, hooks, and MCP configs that reference the app — shown, never edited automatically.
- **Leftovers** — files from apps no longer installed.
- **Updater** (v1.0) — Sparkle appcasts, Homebrew casks, Mac App Store (open store page); release notes inline.
- **Slim apps** (Mole `slim`, Apple Silicon only) — strip Intel slice from Developer ID universal apps; works on a copy, verifies code signature + Gatekeeper before swapping, original to Restore Center. Skips App Store, Apple, Rosetta-flagged, and running apps.
- **Reset app** — remove prefs/caches only, keep app (fixes misbehaving apps).

### 6.8 Startup & Background
- All persistence locations: Login Items, `SMAppService` background items, `~/Library/LaunchAgents`, `/Library/LaunchAgents|Daemons`, privileged helpers, kernel/system extensions, browser extensions, Quick Look/Spotlight plugins, cron, login hooks.
- **Audit badges**: signed by Apple / identified developer / **unsigned** / **notarisation missing** / **parent app missing (orphan)** / **launches from temp or hidden dir**.
- Toggle enable/disable (reversible) vs remove (via Restore Center).
- XProtect / Gatekeeper / SIP / FileVault / Firewall status panel ("Security posture") — honest replacement for a bundled antivirus in v1.

### 6.9 Performance
- Maintenance tasks with last-run date and **skip reasons** (Mole `optimize`): flush DNS, rebuild Spotlight index, rebuild LaunchServices DB, refresh QuickLook & icon caches, run periodic scripts, verify startup disk, reindex Mail, free purgeable space, thin local Time Machine snapshots.
- Free up RAM (`purge`) — clearly labelled as temporary.
- Heavy consumers — apps using sustained CPU/energy over the last hour.

### 6.10 Privacy
- Browser history, cookies, autofill, download history per browser & profile (with "keep logged in on these sites" allowlist).
- Recent items lists, Finder recents, QuickLook thumbnails cache.
- Permissions review (TCC): which apps have Camera, Mic, Screen Recording, Full Disk Access, Accessibility — read-only list with "Open in System Settings" (we cannot and should not modify TCC).

### 6.11 Restore Center — NEW (our key differentiator)
- Every deletion goes through a **quarantine** (`~/Library/Application Support/Spaceroom/Quarantine`, same-volume `rename` so it is instant and free of copy cost; cross-volume items go to that volume's Trash).
- Retention: 7 days default (configurable 0–30). Auto-purge when disk is critically low, oldest first, with notification.
- **Timeline**: each operation is a card (module, time, items, space) → expand → restore one item, a category, or the whole operation.
- Exportable operations log (JSON) — compatible spirit with Mole `history`.
- Exceptions (explicitly labelled in UI): cache categories marked "regenerable" may skip quarantine if the user enables "Delete caches immediately".

### 6.12 Menu bar app (status bar) — MVP
A separate lightweight login-item agent (`MenuBarAgent`), usable even when the main window is closed. It is the place users look at every day, so it is a first-class product surface, not an add-on.

#### 6.12.1 What shows in the menu bar itself
The user picks one or more **status items**. Each metric can be its own item (iStat-style), or they can be combined into one compact item.

| Status item | Display options | Example |
|---|---|---|
| **Storage** (default ON) | free GB · used % · mini pie/ring icon · ring + free GB | `◔ 128 GB` |
| CPU | % · mini sparkline · per-core bars | `▂▅▇▃ 23%` |
| Memory | pressure dot · used GB · % | `● 11.2 GB` |
| Network | ↑↓ throughput · combined | `↓1.2 ↑0.3 MB/s` |
| Battery / power | % + health · wattage in/out · time left | `⚡︎ 87% · 34 W` |
| Thermals / fans | °C · fan RPM (where available) | `52°` |
| Health score | coloured dot or number | `● 92` |
| **Rotate** mode | cycles chosen metrics every N s in one compact item | — |

- **Colour states**: storage ring turns amber below 15 % free and red below 5 %; memory dot follows macOS memory pressure (green/amber/red). Monochrome option for minimalists.
- **Volume picker**: choose which disk the storage item reflects (startup disk by default, or "lowest free space of all mounted").
- Text uses monospaced digits so the menu bar does not jitter.

#### 6.12.2 Popover (click)
Modular cards the user can reorder or hide (drag to reorder in Settings → Menu Bar):

1. **Storage card** — segmented bar by category (Apps · Documents · Developer · System Data · Trash · Quarantine · Purgeable) with free space, per-volume rows for external disks (with Eject button), and iCloud Drive "stored only in cloud" size.
2. **Disk forecast** — *NEW*: "At the current rate, full in ~23 days", computed from Space Lens snapshots (§6.5) on-device.
3. **What grew today** — top 3 folders that grew since yesterday ("+3.2 GB Docker", "+1.1 GB DerivedData") with "Clean" / "Show in Space Lens".
4. **Quick actions** — Empty Trash (shows size), Purge DerivedData, Clean Installers, Free RAM, Eject All, Flush DNS. One click, all go through Restore Center.
5. **Health** — health score ring + CPU / RAM / network / battery sparklines (last 60 s while open).
6. **Top processes** — top 5 by CPU or memory, Quit button (confirm).
7. **Last cleanup** — "Freed 8.4 GB · 2 h ago · Undo".
8. Footer — Open Spaceroom · Smart Care now · Settings.

```
                        ◔ 128 GB  ▂▅▇▃ 23%  ● 11 GB
                       ┌──────────────────────────────────┐
                       │ Macintosh HD          128 GB free │
                       │ ████████▓▓▓▒▒░░░░░░░░░  of 494 GB │
                       │ Apps Docs Dev Sys Trash  Free     │
                       │ ⏏ Samsung T7          1.2 TB free │
                       │──────────────────────────────────│
                       │ 📈 Full in ~23 days at this rate  │
                       │ +3.2 GB Docker   +1.1 GB Xcode  ›│
                       │──────────────────────────────────│
                       │ [Empty Trash 2.1 GB] [DerivedData]│
                       │ [Installers 0.6 GB]  [Free RAM]   │
                       │──────────────────────────────────│
                       │ ● 92 Health  CPU ▂▃▅▃ RAM ▅▅▆▅    │
                       │ node 180%  Chrome 4.1 GB     Quit │
                       │──────────────────────────────────│
                       │ Freed 8.4 GB · 2 h ago     Undo  │
                       │ Open Spaceroom  Smart Care    ⚙︎   │
                       └──────────────────────────────────┘
```

#### 6.12.3 Smart contextual alerts (all optional, rate-limited, never scare-ware)
| Trigger | Notification / popover banner |
|---|---|
| Free space drops below threshold | "Only 9 GB left — 6.1 GB can be freed safely" → Clean |
| An app is dragged to Trash | "Remove 340 MB of leftovers from Figma too?" |
| `.dmg` / `.pkg` finished downloading and the app is now installed | "Figma is installed. Delete the 210 MB installer?" |
| External drive mounted | Drive name, free space, Eject button |
| Folder grows fast (> X GB in an hour) | "DerivedData grew 6 GB in the last hour" |
| Process uses sustained high CPU (> 5 min) | "node is using 180 % CPU for 6 min" → Show / Quit |
| Memory pressure red | Top memory users + Free RAM |
| Time Machine local snapshots > X GB | "Local snapshots use 24 GB" → Thin |
| Battery health drops / cycle-count milestone | Informational |

- **Quiet rules**: automatically silent during Focus, screen sharing, full-screen apps, and presentations; max N alerts per day.

#### 6.12.4 Interactions
- **Drag & drop onto the menu bar icon**: drop an app → uninstall flow; drop a folder → open it in Space Lens; drop files → quarantine.
- **Global hotkey** (default ⌥⌘Space) opens the popover; ⌘K inside it opens the command palette.
- Right-click the icon → quick menu (Empty Trash, Smart Care, Pause monitoring, Quit).
- Hover tooltip on the storage item → one-line breakdown.

#### 6.12.5 Companion surfaces (v1.0)
- **WidgetKit widgets** (desktop & Notification Center): storage ring, health score, disk forecast — sharing code with the popover cards.
- **App Intents / Shortcuts**: "Get free disk space", "Empty Trash", "Run Smart Care".

#### 6.12.6 Performance budget
- Idle RAM < 30 MB, CPU ≈ 0 % when the popover is closed.
- Sampling: storage every 60 s (plus FSEvents on volume changes), CPU/RAM/network every 2 s only while visible in the menu bar; 1 s while the popover is open.
- No disk scanning from the menu bar agent; "what grew" reads the main app's snapshots.

### 6.13 Automations — NEW (v1.0)
- Rule builder: *When* (schedule, disk free < X GB, on login, on power adapter) → *Do* (scan only & notify / clean safe set / empty trash / purge DerivedData older than N days).
- Runs via a `SMAppService` login item agent; never runs anything that requires review without user approval.

### 6.14 Settings
General (launch at login, menu bar), Ignore list (paths, apps, categories — fail-closed if unreadable, like Mole), Restore Center retention, Dev scan roots, Notifications, Permissions status (Full Disk Access, helper), Updates (Sparkle), Advanced (export/import config, logs).

### 6.15 Command palette & CLI
- **⌘K command palette**: jump to any module, run "Empty Trash", "Purge DerivedData", search files in Space Lens.
- **`spaceroom` CLI (v1.0)** sharing the same engine: `spaceroom scan|clean|purge|status --json --dry-run`. Lets developers script it and lets AI agents drive it safely.

## 7. UX & visual design

**Design language** — inspired by CleanMyMac's approach (not its assets or branding):
- Full-bleed window with **per-module gradient backgrounds** (e.g. Smart Care violet→blue, Cleanup green→teal, Dev Cleanup indigo→cyan, Space Lens orange→pink, Restore Center slate). Sidebar is translucent material over the gradient.
- On macOS 26+: adopt **Liquid Glass** (`.glassEffect`) for sidebar, buttons, and cards; fall back to `.ultraThinMaterial` on 14–15.
- Each module has an **original illustration / SF Symbol composition** with subtle idle animation (custom-made; we do not reuse CleanMyMac artwork).
- **Primary action**: one large circular button bottom-centre with animated ring progress during scan; becomes a numeric counter ("4.2 GB… 8.4 GB") as results stream in.
- Results stream in live (`AsyncStream`) — never a frozen spinner.
- Typography: SF Pro Rounded for numbers/headlines, SF Pro for body. Sizes humanised ("8.4 GB", "used 3 months ago").
- Motion: spring transitions between Intro → Scanning → Results → Done (`matchedGeometryEffect` for the main button); respects Reduce Motion.
- Sound: optional, subtle completion sound.
- Accessibility: full VoiceOver labels, keyboard navigation for every action, Dynamic Type-like scaling, contrast check on every gradient.
- Min window 1000×680; sidebar collapsible.

**Main window wireframe — Results state**

```
┌────────────────────────────────────────────────────────────────────┐
│ ● ● ●                                                   ⌘K  ⚙︎     │
├───────────────┬────────────────────────────────────────────────────┤
│ ◉ Smart Care  │                                                    │
│               │                 [ illustration ]                   │
│ CLEAN         │                                                    │
│ ◌ Cleanup     │            8.4 GB of junk can be removed           │
│ ◌ Dev Cleanup │      Safe to delete — everything goes to Restore   │
│ ◌ My Clutter  │            Center for 7 days.                      │
│               │                                                    │
│ UNDERSTAND    │   ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐      │
│ ◌ Space Lens  │   │System  │ │Xcode   │ │Trash   │ │Installers     │
│ ◌ Status      │   │3.1 GB ✓│ │4.0 GB ✓│ │0.9 GB ✓│ │0.4 GB ✓│      │
│               │   └────────┘ └────────┘ └────────┘ └────────┘      │
│ MANAGE        │                                                    │
│ ◌ Applications│               Review Details                       │
│ ◌ Startup     │                                                    │
│ ◌ Performance │                  ╭──────────╮                      │
│ ◌ Privacy     │                  │  Clean   │                      │
│ ──────        │                  ╰──────────╯                      │
│ ◌ Restore     │                                                    │
└───────────────┴────────────────────────────────────────────────────┘
```

**Onboarding (first launch)**
1. Welcome — 3 promises: *See everything · Undo anything · Nothing leaves your Mac*.
2. Grant Full Disk Access — animated guide, deep link to System Settings, live detection when granted.
3. Optional helper install (admin features) — explained, skippable.
4. "Are you a developer?" auto-detected; confirm.
5. Run first Smart Care.

## 8. Technical architecture

### 8.1 Stack
- **Swift 6** (strict concurrency), **SwiftUI** + `@Observable`, AppKit bridges only where needed (Quick Look, NSWorkspace, drag & drop).
- Swift Charts for Status/Space history; custom `Canvas` for Sunburst/Treemap.
- Persistence: SwiftData (or GRDB) for history, snapshots, quarantine index.
- Updates: Sparkle 2. Crash reports: opt-in only.

### 8.2 Modules (Swift packages)
```
Spaceroom.app
├── App (SwiftUI views, navigation, design system)
├── CleanerKit         – core engine (scanner, rules, actions, quarantine)
│   ├── FileScanner    – getattrlistbulk walker, parallel, cancellable, APFS-aware sizes
│   ├── RuleEngine     – declarative cleaning rules (§8.3)
│   ├── Actions        – quarantine/trash/delete/cli-command, dry-run everywhere
│   └── RestoreStore   – quarantine index + operation log
├── SystemKit          – CPU/mem/disk/net/battery/thermal via host_statistics, IOKit, sysctl
├── AppsKit            – app inventory, bundle/ID matching, leftovers, slimming (lipo + codesign verify)
├── DevKit             – dev tool detectors, project artifact finder (git-aware)
├── MediaKit           – duplicates (hashing), similar photos (Vision)
├── PrivilegedHelper   – SMAppService daemon, XPC, minimal audited command set
├── MenuBarAgent       – MenuBarExtra login-item agent, shares SystemKit
└── spaceroom (CLI)    – ArgumentParser front-end over CleanerKit (v1.0)
```

### 8.3 Rule engine (data-driven, updatable)
Cleaning targets are declarative, versioned JSON, shippable as signed updates without an app release:
```json
{
  "id": "xcode.derived-data",
  "group": "dev.xcode",
  "title": "Xcode DerivedData",
  "why_safe": "Build intermediates. Xcode rebuilds them on next build.",
  "paths": ["~/Library/Developer/Xcode/DerivedData/*"],
  "min_age_days": 0,
  "skip_if_running": ["com.apple.dt.Xcode"],
  "requires_admin": false,
  "default_selected": true,
  "smart_care": true,
  "action": "quarantine"
}
```
- Path validation: canonicalise, refuse symlink escapes, refuse anything outside rule roots, never touch SIP-protected paths, re-check file identity (inode + mtime) right before acting (Mole's TOCTOU guard).
- App-leftover mapping DB (bundle ID → known paths) for 800+ apps, community-maintainable.

### 8.4 Permissions & privilege
- **Full Disk Access** required for full functionality; app degrades gracefully without it (shows which categories are limited).
- **Privileged helper** via `SMAppService.daemon`, XPC with code-signing requirement checks on both sides; only a fixed set of operations (delete in system cache dirs, run maintenance commands). No arbitrary shell.
- Admin auth via Authorization Services (Touch ID supported by the system prompt).
- Not sandboxed → distributed outside Mac App Store, **Developer ID signed + notarised**, hardened runtime.

### 8.5 Performance budgets
| Metric | Target |
|---|---|
| Cold launch to interactive | < 1 s |
| Smart Care scan (500 GB SSD, FDA) | < 30 s |
| Space Lens full scan (1 M files) | < 20 s, streaming results |
| Idle RAM — main app / menu bar agent | < 150 MB / < 30 MB |
| UI | 60 fps (120 on ProMotion) during scans |

## 9. Safety, privacy & legal

- **Never delete without preview.** One-click modes only include rules flagged `smart_care: true` (regenerable data).
- **Quarantine by default**; permanent deletion is an explicit, labelled choice.
- **Fail-closed**: if the ignore list or rule DB fails to load/verify, cleaning is disabled (scanning still works).
- **No network** except Sparkle updates, rule DB updates (signed), and app updater checks — all disclosable and toggleable.
- **No telemetry by default**; opt-in anonymous crash reports only.
- **No copying** of CleanMyMac artwork, icons, copy, or trademarks — design is inspired, not cloned.

### 9.1 Open-source model (decided: GPL-3.0)
- **License**: whole project (app, CleanerKit, helper, CLI, rule DB) under **GPL-3.0-or-later**. `LICENSE` at repo root, SPDX header in every source file.
- **Mole reuse**: because Mole is GPL-3.0, we may port its cleaning-target lists, safety heuristics (purge activity window, git/keypair protection, identity re-check, installer locations) and app-leftover knowledge. Every ported rule keeps a `source: "mole"` field and the upstream commit hash; `NOTICE`/README credit Mole (tw93/mole) as upstream inspiration. Spaceroom is a separate product with a distinct name, not a fork.
- **Dependencies** must be GPL-3.0-compatible: Sparkle (MIT), swift-argument-parser (Apache-2.0), GRDB (MIT) — all OK. Avoid any proprietary SDK (e.g. closed malware engines) in the core.
- **Rule DB is a first-class open artifact**: `rules/` folder of JSON with schema + CI validation; community PRs for new apps/dev tools are the main contribution path. Each rule PR needs a "why safe" text and a test fixture.
- **Distribution**: GitHub Releases (signed + notarised DMG with Sparkle appcast) and a Homebrew cask. Build-from-source instructions; self-built copies use ad-hoc signing and show a notice that the privileged helper requires a Developer ID build.
- **Trust signals**: reproducible-build notes, public security policy (`SECURITY.md`), threat model doc for the privileged helper, all network endpoints listed in README.
- **Sustainability**: GitHub Sponsors / Open Collective; no paywalled features, no nag screens. Optional in-app "Support the project" link in Settings → About only.
- **Governance**: `CONTRIBUTING.md`, Code of Conduct, CODEOWNERS for `CleanerKit/Actions` and `PrivilegedHelper` (extra review required for anything that deletes or escalates).

## 10. Success metrics

| Metric | Target (90 days post-launch) |
|---|---|
| Median space reclaimed in first Smart Care | ≥ 5 GB (≥ 20 GB for developers) |
| Restores per 1 000 cleans (proxy for "regret") | < 5 |
| Data-loss bug reports | 0 |
| Crash-free sessions | ≥ 99.8 % |
| Weekly active / installs | ≥ 40 % |
| Onboarding FDA grant rate | ≥ 75 % |

(Metrics measured only from opt-in users or voluntary surveys, consistent with §9.)

## 11. Release plan

| Milestone | Scope | Exit criteria |
|---|---|---|
| **M0 — Foundations** (wk 1–3) | GitHub org + repo (GPL-3.0, CONTRIBUTING, SECURITY), Xcode project with String Catalogs, design system, app shell & sidebar, FileScanner, RuleEngine, RestoreStore, FDA onboarding | Scan + quarantine + restore one rule end-to-end |
| **M1 — MVP / v0.1** (wk 4–9) | Smart Care, Cleanup, Dev Cleanup, Space Lens (sunburst), Uninstaller + Leftovers, Installers, Restore Center, Menu bar status | Internal dogfood on 10 Macs, zero data-loss incidents |
| **v0.5 — Beta** (wk 10–14) | System Status full, Startup & Background audit, Performance, Large & Old, Duplicates, Privacy, privileged helper, Sparkle | Public beta, notarised |
| **v1.0** (wk 15–20) | Similar photos, App Updater, Slim apps, Space growth history, Automations, ⌘K palette, `spaceroom` CLI, localisation (EN + ID) | Success metrics instrumentation, docs site |
| **Post-v1** | Cloud cleanup, malware signatures (or 3rd-party engine), multi-Mac dashboard, Widgets, Shortcuts/App Intents | — |

## 12. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Deleting something important | Critical (trust) | Quarantine default, conservative rules, identity re-check, extensive fixture tests, dogfooding |
| Users refuse Full Disk Access | High | Clear onboarding, graceful degraded mode, show exactly what is locked |
| macOS changes paths/permissions yearly | Medium | Data-driven rules, OS-version gating per rule, beta testing on each macOS beta |
| A community-contributed rule deletes user data | Critical | Rule schema validation in CI, mandatory fixture test + "why safe", CODEOWNERS review, rules default to quarantine |
| Malicious fork redistributed under similar name | Medium | Only official channels (GitHub Releases, Homebrew cask) listed; notarised builds with our Team ID; trademark the name |
| "Cleaner apps are scams" perception | Medium | Honest numbers (no inflated junk), no scare tactics, open rule DB |
| Privileged helper attack surface | High | Minimal XPC command set, code-signing requirement validation, security review before beta |

## 13. Open questions

Resolved:
- ~~Business model / license~~ → **Free & open source, GPL-3.0-or-later; Mole rules may be ported with attribution** (§9.1).
- ~~Product name~~ → **Spaceroom** ("Spaceroom for Mac" in marketing; no "Mac" in the product name per Apple trademark guidelines); CLI command `spaceroom`. "Roomy" was rejected because a commercial Mac cleaner already uses that name.
- ~~Minimum macOS~~ → **macOS 14 Sonoma**. Gives us `@Observable`, SwiftData, `SMAppService`, `MenuBarExtra` and Swift Charts natively; Liquid Glass (`.glassEffect`) is used behind `if #available(macOS 26, *)` with material fallbacks on 14–15.
- ~~Malware~~ → **v1 ships the persistence audit + security posture panel only** (§6.8). Any future scan engine must be GPL-compatible (ClamAV signatures and/or YARA rules); evaluated post-v1.
- ~~Localisation~~ → **English + Bahasa Indonesia at launch (v1.0)**. String Catalogs (`.xcstrings`) from M0 so no string is hard-coded; community translations via PRs afterwards.
- ~~Quarantine retention~~ → **7 days default, configurable 0–30 days**; oldest items auto-purged first when free space is critically low, with a notification (§6.11).
- ~~Repo home~~ → **new GitHub organisation** (proposed `spaceroom-app` — free on GitHub as of 2026-11-04; `spaceroom` is taken) so maintainers can be added later and the project is not tied to a personal account.

All open questions are resolved. Next step: **M0 — Foundations** (§11).
