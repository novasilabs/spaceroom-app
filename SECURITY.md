# Security Policy

Spaceroom moves and deletes files and will later include a privileged helper, so we take security and data-safety bugs seriously.

## Reporting a vulnerability

Please **do not open a public issue**. Report privately via GitHub's **"Report a vulnerability"** button (Security → Advisories) on this repository.

Please include:
- the Spaceroom version and macOS version,
- steps to reproduce,
- the impact (for example "a crafted symlink lets a rule delete files outside its root").

We aim to acknowledge reports within 3 days and to ship a fix or mitigation within 30 days for high-severity issues.

## In scope

- Anything that lets Spaceroom remove, move, or expose data outside what the user reviewed and confirmed.
- Escaping a rule's root folder (symlinks, `..`, race conditions between scan and clean).
- Restore Center data loss (items not restorable before expiry).
- The privileged helper (from v0.5): XPC authentication, command injection, privilege escalation.
- Tampering with rule updates.

## Network endpoints

Spaceroom M0 makes **no network requests**. Future endpoints (Sparkle update feed, signed rule updates) will be listed here.
