# Security Policy

Spaceroom moves and deletes files on people's Macs, so we treat **data-safety bugs as
security bugs**.

## Supported versions

| Version | Supported |
|---|---|
| 0.9.x (latest beta) | ✅ |
| older | ❌ |

## Reporting a vulnerability

Please **do not open a public issue**. Report privately through
[GitHub Security Advisories](https://github.com/novasilabs/spaceroom-app/security/advisories/new)
("Report a vulnerability" on the Security tab).

Please include:
- the Spaceroom version (Settings › About) and macOS version,
- steps to reproduce, ideally with a minimal folder layout,
- the impact (for example "a crafted symlink lets a rule move files outside its root").

We aim to acknowledge reports within **3 days** and to ship a fix or mitigation within
**30 days** for high-severity issues. We credit reporters in the release notes unless you
prefer otherwise.

## In scope

- Anything that removes, moves or exposes data the user didn't review and confirm.
- Escaping a rule's root folder (symlinks, `..`, races between scan and clean, identity
  swaps).
- Bypassing the ignore list, or the Restore Center's fail-closed behaviour.
- Restore Center data loss (items that can't be restored before they expire).
- Automations or Smart Care acting on data that isn't Smart Care–eligible.
- Protection or Privacy reading more than they need to (for example file contents beyond
  headers, or saved passwords).
- The privileged helper, once it exists: XPC authentication, command injection, privilege
  escalation.
- Tampering with rules or release artifacts.

## Out of scope

- The Protection scan not detecting a given piece of malware. It's a heuristic scan for
  common disguises, not an antivirus. Please open a regular issue with the sample's
  characteristics, not the sample itself.
- Gatekeeper warnings on beta builds (they aren't notarized yet).

## How Spaceroom limits its own reach

- **No network, except when you check for app updates.** Spaceroom makes no network requests
  on its own. Notifications are local. The only exception is **Applications › Updates ›
  Check for Updates**, and it runs only when you click it. It then contacts:
  - each app's own Sparkle update feed (the `SUFeedURL` in that app's Info.plist, HTTPS only);
  - `https://itunes.apple.com/lookup`, with the bundle IDs of your App Store apps.

  Requests use an ephemeral session with no cookies or cache. Spaceroom never downloads or
  installs updates itself: the app's own updater or the App Store does, and both verify the
  developer's signature.
- **No admin rights.** Nothing runs as root. Admin tasks stay locked until the privileged
  helper exists and has had its own security review.
- **Read-only where possible.** Permission databases are opened read-only, Protection reads
  file headers and tails only, and nothing found is ever executed.
- **One way out.** Every removal goes through the Restore Center, which enforces the ignore
  list and refuses all moves if the list can't be read.

## Verifying a download

Every release ships a `.sha256` next to the `.dmg`:

```bash
shasum -a 256 -c Spaceroom-0.10.0.dmg.sha256
```
