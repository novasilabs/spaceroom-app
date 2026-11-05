#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Fails when an app string, engine string table or cleaning rule lacks Bahasa Indonesia,
or when a translation's format placeholders don't match the English."""
import glob, json, re, subprocess, sys

SPEC = re.compile(r"%(\d+\$)?(lld|ld|d|@|f|\.\df|%)")
problems = []

def check_specifiers(key, value, where):
    if sorted(SPEC.findall(key)) != sorted(SPEC.findall(value)):
        problems.append(f"{where}: placeholders differ: {key!r} → {value!r}")

def strings_table(path):
    out = subprocess.run(["plutil", "-convert", "json", "-o", "-", path], capture_output=True, text=True, check=True)
    return json.loads(out.stdout)

# App String Catalog
catalog = json.load(open("App/Spaceroom/Resources/Localizable.xcstrings"))
for key, entry in catalog["strings"].items():
    if entry.get("extractionState") == "stale" or entry.get("shouldTranslate") is False:
        continue
    unit = entry.get("localizations", {}).get("id", {}).get("stringUnit")
    if not unit or unit.get("state") != "translated":
        problems.append(f"app: missing Indonesian for {key!r}")
    else:
        check_specifiers(key, unit["value"], "app")

# Engine tables
base = "Packages/SpaceroomCore/Sources/SpaceroomCore/Resources/Localization/id.lproj"
for key, value in strings_table(f"{base}/Localizable.strings").items():
    check_specifiers(key, value, "engine")

rules = strings_table(f"{base}/Rules.strings")
for path in glob.glob("Packages/SpaceroomCore/Sources/SpaceroomCore/Resources/Rules/*.json"):
    for rule in json.load(open(path))["rules"]:
        for field in ("title", "why_safe", "rebuild_hint"):
            text = rule.get(field)
            if text and text not in rules:
                problems.append(f"rules: {rule['id']}.{field} has no Indonesian in Rules.strings")

if problems:
    print("\n".join(problems))
    sys.exit(1)
print(f"✓ translations complete ({len(catalog['strings'])} app strings, {len(rules)} rule texts)")
