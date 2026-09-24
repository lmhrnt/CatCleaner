#!/usr/bin/env python3
"""Validate CatCleaner's fail-closed GitHub release/signing workflow contract.

Uses only the Python standard library so CI/local checks do not depend on
PyYAML or actionlint.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RELEASE = ROOT / ".github/workflows/release.yml"
SIGNING = ROOT / ".github/workflows/verify-signing.yml"

UPSTREAM_TEAM_ID = "H3XLS95QV4"
FORBIDDEN_UPSTREAM_MARKERS = (
    "homebrew-macsai",
    "MacSai-",
    "notarytool store-credentials \"MacSai\"",
)


def fail(message: str) -> None:
    print(f"RELEASE_CONTRACT_FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError as exc:
        fail(f"cannot read {path.relative_to(ROOT)}: {exc}")


def require(source: str, needle: str, label: str) -> None:
    if needle not in source:
        fail(f"{label}: missing required marker: {needle}")


def forbid(source: str, needle: str, label: str) -> None:
    if needle in source:
        fail(f"{label}: forbidden marker present: {needle}")


def top_level_on_keys(source: str, label: str) -> list[str]:
    lines = source.splitlines()
    try:
        start = lines.index("on:")
    except ValueError:
        fail(f"{label}: missing top-level on: block")

    keys: list[str] = []
    for line in lines[start + 1 :]:
        if line and not line.startswith((" ", "\t")):
            break
        match = re.match(r"^  ([A-Za-z0-9_-]+):(?:\s.*)?$", line)
        if match:
            keys.append(match.group(1))
    return keys


def permission_value(source: str, key: str, label: str) -> str:
    match = re.search(
        rf"(?m)^permissions:\s*$\n(?:^[ \t].*\n)*?^  {re.escape(key)}:\s*([^#\s]+)\s*$",
        source,
    )
    if not match:
        fail(f"{label}: permissions.{key} is missing")
    return match.group(1)


def validate_common(source: str, label: str) -> None:
    keys = top_level_on_keys(source, label)
    if keys != ["workflow_dispatch"]:
        fail(f"{label}: only workflow_dispatch is allowed, found={keys!r}")

    for marker in FORBIDDEN_UPSTREAM_MARKERS:
        forbid(source, marker, label)

    require(source, f'[[ "$APPLE_TEAM_ID" != "{UPSTREAM_TEAM_ID}" ]]', label)
    require(source, f'[[ "$identity" != *"{UPSTREAM_TEAM_ID}"* ]]', label)
    require(source, "CATCLEANER_CERTIFICATE_P12_BASE64", label)
    require(source, "CATCLEANER_CERTIFICATE_PASSWORD", label)
    require(source, "CATCLEANER_APPLE_ID", label)
    require(source, "CATCLEANER_APP_PASSWORD", label)
    require(source, "CATCLEANER_TEAM_ID", label)
    require(source, 'profile="CatCleaner-CI-$' + '{GITHUB_RUN_ID}"', label)
    require(source, "xcrun notarytool store-credentials", label)
    require(source, "--keychain \"$keychain\"", label)
    require(source, "./scripts/build-dmg.sh --notarize", label)
    require(source, "codesign --verify --deep --strict", label)
    require(source, "spctl --assess --type execute", label)
    require(source, "xcrun stapler validate", label)
    require(source, 'security delete-keychain "$RUNNER_TEMP/catcleaner-ci.keychain-db"', label)


def validate_release() -> None:
    label = "release"
    source = read(RELEASE)

    require(source, "name: CatCleaner Release", label)
    validate_common(source, label)

    if permission_value(source, "contents", label) != "write":
        fail("release: permissions.contents must be write")

    publish_block = re.search(
        r"(?ms)^      publish:\s*$"
        r".*?^        required:\s*true\s*$"
        r".*?^        type:\s*boolean\s*$"
        r".*?^        default:\s*false\s*$",
        source,
    )
    if not publish_block:
        fail("release: publish input must be required boolean with default false")

    require(source, "if: $" + "{{ inputs.publish == true }}", label)
    require(source, '[[ "$GITHUB_REF" == refs/tags/v* ]]', label)
    require(source, '[[ "$GITHUB_REF_NAME" == "v$' + '{version}" ]]', label)
    require(source, "./scripts/check-version-sync.sh", label)
    require(source, "git diff --exit-code", label)
    require(source, 'gh release create "$GITHUB_REF_NAME" "$DMG_PATH"', label)
    require(source, "--verify-tag", label)

    print("RELEASE_WORKFLOW_CONTRACT_PASS")


def validate_signing() -> None:
    label = "signing"
    source = read(SIGNING)

    require(source, "name: CatCleaner Signing Verification", label)
    validate_common(source, label)

    if permission_value(source, "contents", label) != "read":
        fail("signing: permissions.contents must be read")

    forbid(source, "gh release create", label)
    forbid(source, "contents: write", label)
    require(source, "./scripts/check-version-sync.sh", label)
    require(source, "git diff --exit-code", label)

    print("SIGNING_WORKFLOW_CONTRACT_PASS")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--scope",
        choices=("all", "release", "signing"),
        default="all",
        help="contract subset to validate",
    )
    args = parser.parse_args()

    if args.scope in ("all", "release"):
        validate_release()
    if args.scope in ("all", "signing"):
        validate_signing()

    if args.scope == "all":
        print("CATCLEANER_RELEASE_CONTRACT_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
