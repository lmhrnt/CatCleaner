#!/usr/bin/env python3
"""Static/synthetic contract checks for CatCleaner qualification gates.

This check is intentionally independent of local GitHub repositories, Xcode,
Developer ID certificates, and network access.
"""

from __future__ import annotations

import contextlib
import importlib.util
import io
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load_module(name: str, relative: str):
    path = ROOT / relative
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise AssertionError(f"cannot load {relative}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def expect_rejected(fn, value: str) -> None:
    stderr = io.StringIO()
    try:
        with contextlib.redirect_stderr(stderr):
            fn(value)
    except SystemExit as exc:
        if exc.code not in (1, 78):
            raise AssertionError(f"unexpected rejection code for {value}: {exc.code}") from exc
    else:
        raise AssertionError(f"invalid value was accepted: {value}")


def require_text(relative: str, needles: tuple[str, ...]) -> None:
    text = (ROOT / relative).read_text(encoding="utf-8")
    for needle in needles:
        if needle not in text:
            raise AssertionError(f"{relative}: missing contract marker: {needle}")


def main() -> int:
    origin = load_module("catcleaner_origin_qualification", "scripts/origin-qualification.py")
    developer = load_module(
        "catcleaner_developer_id_qualification",
        "scripts/developer-id-qualification.py",
    )

    accepted_origins = (
        "https://github.com/lmhrnt/CatCleaner.git",
        "git@github.com:lmhrnt/CatCleaner.git",
        "ssh://git@github.com/lmhrnt/CatCleaner.git",
    )
    for url in accepted_origins:
        owner, repo = origin.parse_github_repo(url)
        assert owner == "lmhrnt"
        assert repo == "CatCleaner"

    rejected_origins = (
        "http://github.com/lmhrnt/CatCleaner.git",
        "https://user@example.com@github.com/lmhrnt/CatCleaner.git",
        "https://gitlab.com/lmhrnt/CatCleaner.git",
        "https://github.com/iliyami/CatCleaner.git",
        "https://github.com/lmhrnt/Other.git",
        "https://github.com/lmhrnt/team/CatCleaner.git",
    )
    for url in rejected_origins:
        expect_rejected(origin.parse_github_repo, url)

    identity_line = (
        '  1) ABCDEF0123456789ABCDEF0123456789ABCDEF01 '
        '"Developer ID Application: Example Owner (ABCDE12345)"'
    )
    match = developer.IDENTITY_RE.match(identity_line)
    assert match is not None
    assert match.group(1).upper() == "ABCDEF0123456789ABCDEF0123456789ABCDEF01"
    assert developer.TEAM_RE.search(match.group(2)).group(1) == "ABCDE12345"

    subject = (
        "subject=CN = Developer ID Application: Example Owner (ABCDE12345), "
        "OU = ABCDE12345, O = Example"
    )
    subject_team = developer.SUBJECT_TEAM_RE.search(subject)
    assert subject_team is not None
    assert subject_team.group(1) == "ABCDE12345"

    require_text(
        "scripts/release-readiness.sh",
        (
            "origin-qualification.py --local",
            "origin-qualification.py --check",
            "developer-id-qualification.py --local",
            "developer-id-qualification.py --check",
            "check-xcode-qualification.py",
        ),
    )
    require_text(
        ".github/workflows/release.yml",
        ("./scripts/xcode-qualification.sh --full", "runs-on: macos-15"),
    )
    require_text(
        ".github/workflows/verify-signing.yml",
        ("./scripts/xcode-qualification.sh --full", "runs-on: macos-15"),
    )

    print("CATCLEANER_QUALIFICATION_CONTRACT_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
