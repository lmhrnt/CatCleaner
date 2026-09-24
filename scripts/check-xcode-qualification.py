#!/usr/bin/env python3
"""Validate the full local Xcode qualification receipt for the current source."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_RECEIPT = ROOT / ".build/qualification/xcode-qualification-v1.json"
QUALIFIED_APP = ROOT / ".build/qualification/CatCleaner.app"
MAIN_EXE = QUALIFIED_APP / "Contents/MacOS/MacClean"
MENU_EXE = (
    QUALIFIED_APP
    / "Contents/Library/LoginItems/MacCleanMenu.app/Contents/MacOS/MacCleanMenu"
)


def fail(message: str) -> None:
    print(f"XCODE_QUALIFICATION_FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def run(*args: str, env: dict[str, str] | None = None) -> str:
    try:
        return subprocess.check_output(
            args,
            cwd=ROOT,
            env=env,
            text=True,
            stderr=subprocess.STDOUT,
        ).strip()
    except (OSError, subprocess.CalledProcessError) as exc:
        fail(f"command failed: {' '.join(args)}: {exc}")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exc:
        fail(f"cannot hash {path.relative_to(ROOT)}: {exc}")
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--developer-dir", required=True)
    parser.add_argument("--receipt", type=Path, default=DEFAULT_RECEIPT)
    args = parser.parse_args()

    receipt_path = args.receipt
    if not receipt_path.is_absolute():
        receipt_path = ROOT / receipt_path

    try:
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        fail(f"qualification receipt missing: {receipt_path}")
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"qualification receipt unreadable: {exc}")

    if receipt.get("schema") != "catcleaner.xcode-qualification/v1":
        fail("unexpected receipt schema")
    if receipt.get("mode") != "full":
        fail("receipt is not from --full qualification")
    if receipt.get("artifact_app") != ".build/qualification/CatCleaner.app":
        fail("receipt does not bind the immutable qualification app snapshot")

    if run("git", "status", "--porcelain"):
        fail("Git working tree is not clean")

    head = run("git", "rev-parse", "HEAD")
    tree = run("git", "rev-parse", "HEAD^{tree}")
    if receipt.get("head") != head:
        fail(f"HEAD changed: receipt={receipt.get('head')} current={head}")
    if receipt.get("tree") != tree:
        fail(f"tree changed: receipt={receipt.get('tree')} current={tree}")

    developer_dir = str(Path(args.developer_dir).expanduser().resolve())
    receipt_developer_dir = str(Path(str(receipt.get("developer_dir", ""))).expanduser().resolve())
    if receipt_developer_dir != developer_dir:
        fail(
            "developer dir changed: "
            f"receipt={receipt_developer_dir} current={developer_dir}"
        )

    env = os.environ.copy()
    env["DEVELOPER_DIR"] = developer_dir
    xcode_version = run("xcodebuild", "-version", env=env).splitlines()
    if receipt.get("xcode_version") != xcode_version:
        fail(
            "Xcode version changed: "
            f"receipt={receipt.get('xcode_version')!r} current={xcode_version!r}"
        )

    binaries = {
        "main_sha256": MAIN_EXE,
        "menu_sha256": MENU_EXE,
    }
    for field, path in binaries.items():
        if not path.is_file():
            fail(f"qualified app binary missing: {path.relative_to(ROOT)}")
        current_sha = sha256(path)
        if receipt.get(field) != current_sha:
            fail(
                f"qualified binary changed for {path.name}: "
                f"receipt={receipt.get(field)} current={current_sha}"
            )

    source_version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    if receipt.get("app_version") != source_version:
        fail(
            f"version changed: receipt={receipt.get('app_version')} current={source_version}"
        )

    print("CATCLEANER_XCODE_QUALIFICATION_RECEIPT_PASS")
    print(f"head={head}")
    print(f"tree={tree}")
    print(f"developer_dir={developer_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
