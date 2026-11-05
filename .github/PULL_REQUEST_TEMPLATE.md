## What and why

<!-- What does this change, and why? Link the issue: Fixes #… -->

## How it was tested

- [ ] `make test` passes
- [ ] Checked in the app (screenshots below for UI changes; both languages if text changed)

## Safety (only for code that removes, moves or reads user files)

- [ ] Removal goes through `RestoreStore.quarantine`
- [ ] Each item is re-checked right before it moves (exists, same identity, inside its root)
- [ ] The ignore list is respected and covered by a test
- [ ] Nothing personal (documents, cookies, startup items) is acted on unattended

## Checklist

- [ ] New strings are in the String Catalog with an Indonesian translation (`make check-translations`)
- [ ] `CHANGELOG.md` updated under **Unreleased**
