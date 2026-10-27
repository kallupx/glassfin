#!/usr/bin/env python3
"""Every String Catalog uses development language en, with en and fi translated.

Aligns with the shared catalog rule: sourceLanguage is en, and each key has
en and fi string units whose state is translated. Tests compare CopyKey values,
not the translated display text.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_CATALOG = ROOT / "Apps/Shared/Resources/Localizable.xcstrings"
COPY_SWIFT = ROOT / "Apps/Shared/Sources/DesignSystem/Copy.swift"
LOCALES = ("en", "fi")
SPECIFIER = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|f|lf|@)")
COPY_CASE = re.compile(r'case\s+\w+\s*=\s*"([^"]+)"')


def fail(message: str) -> None:
    print(f"check-string-catalogs: {message}", file=sys.stderr)


def specifiers(value: str) -> list[str]:
    return SPECIFIER.findall(value)


def check_catalog(path: Path) -> list[str]:
    errors: list[str] = []
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        return [f"{path}: invalid JSON ({error})"]
    if payload.get("sourceLanguage") != "en":
        errors.append(f"{path}: sourceLanguage must be en")
    strings = payload.get("strings")
    if not isinstance(strings, dict) or not strings:
        errors.append(f"{path}: strings must be a non-empty object")
        return errors
    for key, entry in strings.items():
        localizations = entry.get("localizations") if isinstance(entry, dict) else None
        if not isinstance(localizations, dict):
            errors.append(f"{path}: {key} has no localizations")
            continue
        values: dict[str, str] = {}
        for locale in LOCALES:
            unit = (localizations.get(locale) or {}).get("stringUnit") or {}
            state = unit.get("state")
            value = unit.get("value")
            if state != "translated" or not isinstance(value, str) or value == "":
                errors.append(f"{path}: {key} locale {locale} must be a non-empty translated string")
                continue
            values[locale] = value
        if set(values) == set(LOCALES) and specifiers(values["en"]) != specifiers(values["fi"]):
            errors.append(f"{path}: {key} en/fi format specifiers differ")
    return errors


def copy_keys() -> set[str]:
    text = COPY_SWIFT.read_text(encoding="utf-8")
    return set(COPY_CASE.findall(text))


def main() -> int:
    catalogs = sorted(ROOT.glob("**/*.xcstrings"))
    catalogs = [path for path in catalogs if ".build" not in path.parts and "checkouts" not in path.parts]
    errors: list[str] = []
    if APP_CATALOG not in catalogs:
        errors.append(f"missing {APP_CATALOG.relative_to(ROOT)}")
    for path in catalogs:
        errors.extend(check_catalog(path))
    if APP_CATALOG.exists():
        payload = json.loads(APP_CATALOG.read_text(encoding="utf-8"))
        catalog_keys = set(payload.get("strings", {}))
        keys = copy_keys()
        if catalog_keys != keys:
            missing = sorted(keys - catalog_keys)
            extra = sorted(catalog_keys - keys)
            if missing:
                errors.append("catalog is missing CopyKey values: " + ", ".join(missing))
            if extra:
                errors.append("catalog has keys without CopyKey: " + ", ".join(extra))
    if errors:
        for message in errors:
            fail(message)
        return 1
    print(f"check-string-catalogs: passed ({len(catalogs)} catalog(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
