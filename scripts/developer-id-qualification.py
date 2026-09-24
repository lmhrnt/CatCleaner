#!/usr/bin/env python3
"""Qualify and validate CatCleaner's local Developer ID Application identity.

Modes:
  --local    Require at least one eligible non-upstream Developer ID identity.
  --qualify  Select one identity (explicitly if ambiguous) and bind its certificate/team/validity to the current clean source.
  --check    Validate the existing receipt against the current source and Keychain.

This tool never imports, deletes, or changes certificates/keys. It deliberately
does not require a private-key signing probe because non-interactive Keychain ACLs
can reject otherwise valid identities; actual signing is verified by the
release/signing workflows after importing CatCleaner's certificate into an
ephemeral CI Keychain.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RECEIPT = ROOT / ".build/qualification/developer-id-qualification-v1.json"
UPSTREAM_TEAM_ID = "H3XLS95QV4"
UPSTREAM_NAME = "Iliya Mirzaei"
OPENSSL = "/usr/bin/openssl"

IDENTITY_RE = re.compile(
    r'^\s*\d+\)\s+([0-9A-Fa-f]{40})\s+"(Developer ID Application:[^"]+)"\s*$'
)
TEAM_RE = re.compile(r"\(([A-Z0-9]{10})\)\s*$")
SUBJECT_TEAM_RE = re.compile(r"(?:^|[,/])\s*OU\s*=\s*([A-Z0-9]{10})(?:\s*[,/]|$)")


def fail(message: str, code: int = 1) -> None:
    print(f"DEVELOPER_ID_QUALIFICATION_FAIL: {message}", file=sys.stderr)
    raise SystemExit(code)


def run_text(*args: str, check: bool = True) -> str:
    proc = subprocess.run(
        args,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if check and proc.returncode != 0:
        detail = (proc.stderr or proc.stdout).strip()
        fail(f"command failed ({proc.returncode}): {' '.join(args)}: {detail}")
    return proc.stdout.strip()


def git_clean() -> None:
    dirty = run_text("git", "status", "--porcelain")
    if dirty:
        fail("Git working tree is not clean")


def git_identity() -> tuple[str, str]:
    return (
        run_text("git", "rev-parse", "HEAD"),
        run_text("git", "rev-parse", "HEAD^{tree}"),
    )


def eligible_identities() -> list[dict[str, str]]:
    output = run_text("security", "find-identity", "-v", "-p", "codesigning")
    result: list[dict[str, str]] = []
    for line in output.splitlines():
        match = IDENTITY_RE.match(line)
        if not match:
            continue
        sha1, identity = match.groups()
        if UPSTREAM_TEAM_ID in identity or UPSTREAM_NAME.lower() in identity.lower():
            continue
        team_match = TEAM_RE.search(identity)
        if not team_match:
            continue
        team_id = team_match.group(1)
        if team_id == UPSTREAM_TEAM_ID:
            continue
        result.append(
            {
                "identity_sha1": sha1.upper(),
                "identity": identity,
                "team_id": team_id,
            }
        )
    return result


def choose_identity(
    *,
    preferred_identity: str | None = None,
    preferred_team: str | None = None,
) -> dict[str, str]:
    candidates = eligible_identities()
    requested_identity = (
        preferred_identity
        if preferred_identity is not None
        else os.environ.get("CATCLEANER_DEVELOPER_ID", "").strip()
    )
    requested_team = (
        preferred_team
        if preferred_team is not None
        else os.environ.get("CATCLEANER_TEAM_ID", "").strip()
    )

    if requested_identity:
        candidates = [
            candidate for candidate in candidates
            if candidate["identity"] == requested_identity
        ]
        if not candidates:
            fail(
                "CATCLEANER_DEVELOPER_ID does not match an eligible valid "
                "Developer ID Application identity",
                78,
            )

    if requested_team:
        if not re.fullmatch(r"[A-Z0-9]{10}", requested_team):
            fail("CATCLEANER_TEAM_ID must be a 10-character Apple Team ID", 78)
        if requested_team == UPSTREAM_TEAM_ID:
            fail("refusing upstream Mac Sai Team ID", 78)
        candidates = [
            candidate for candidate in candidates
            if candidate["team_id"] == requested_team
        ]
        if not candidates:
            fail(
                "CATCLEANER_TEAM_ID does not match an eligible Developer ID identity",
                78,
            )

    if not candidates:
        fail("no eligible Developer ID Application identity found in Keychain", 78)
    if len(candidates) > 1:
        names = ", ".join(candidate["identity"] for candidate in candidates)
        fail(
            "multiple eligible Developer ID identities found; set "
            f"CATCLEANER_DEVELOPER_ID explicitly: {names}",
            78,
        )
    return candidates[0]


def certificate_pem(identity: str) -> bytes:
    proc = subprocess.run(
        ["security", "find-certificate", "-c", identity, "-p"],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if proc.returncode != 0 or not proc.stdout:
        fail(
            "unable to read certificate for Developer ID identity: "
            + proc.stderr.decode(errors="replace").strip()
        )
    return proc.stdout


def certificate_hashes(identity: str) -> tuple[str, str]:
    output = run_text("security", "find-certificate", "-c", identity, "-Z")
    sha256_match = re.search(r"^SHA-256 hash:\s*([0-9A-Fa-f]{64})$", output, re.M)
    sha1_match = re.search(r"^SHA-1 hash:\s*([0-9A-Fa-f]{40})$", output, re.M)
    if not sha256_match or not sha1_match:
        fail("unable to extract certificate hashes")
    return sha1_match.group(1).upper(), sha256_match.group(1).upper()


def certificate_details(identity: dict[str, str]) -> dict[str, str]:
    pem = certificate_pem(identity["identity"])

    valid = subprocess.run(
        [OPENSSL, "x509", "-checkend", "0", "-noout"],
        input=pem,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if valid.returncode != 0:
        fail("Developer ID certificate is expired or not currently valid")

    details_proc = subprocess.run(
        [
            OPENSSL,
            "x509",
            "-noout",
            "-subject",
            "-issuer",
            "-serial",
            "-startdate",
            "-enddate",
        ],
        input=pem,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=False,
    )
    if details_proc.returncode != 0:
        fail(
            "unable to inspect Developer ID certificate: "
            + details_proc.stderr.decode(errors="replace").strip()
        )
    details = details_proc.stdout.decode(errors="replace").strip()

    fields: dict[str, str] = {}
    for line in details.splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        fields[key.strip()] = value.strip()

    subject = fields.get("subject", "")
    subject_team = SUBJECT_TEAM_RE.search(subject)
    if subject_team and subject_team.group(1) != identity["team_id"]:
        fail(
            "certificate subject OU does not match Developer ID Team ID: "
            f"subject={subject_team.group(1)} identity={identity['team_id']}"
        )

    cert_sha1, cert_sha256 = certificate_hashes(identity["identity"])
    if cert_sha1 != identity["identity_sha1"]:
        fail(
            "Developer ID identity hash does not match certificate SHA-1: "
            f"identity={identity['identity_sha1']} certificate={cert_sha1}"
        )

    return {
        "cert_sha1": cert_sha1,
        "cert_sha256": cert_sha256,
        "subject": subject,
        "issuer": fields.get("issuer", ""),
        "serial": fields.get("serial", ""),
        "not_before": fields.get("notBefore", ""),
        "not_after": fields.get("notAfter", ""),
    }


def local_state(
    *,
    preferred_identity: str | None = None,
    preferred_team: str | None = None,
) -> dict[str, str]:
    identity = choose_identity(
        preferred_identity=preferred_identity,
        preferred_team=preferred_team,
    )
    cert = certificate_details(identity)
    return {**identity, **cert}


def qualify() -> None:
    git_clean()
    head, tree = git_identity()
    state = local_state()

    receipt = {
        "schema": "catcleaner.developer-id-qualification/v1",
        "qualified_at_utc": datetime.now(timezone.utc).isoformat(),
        "head": head,
        "tree": tree,
        **state,
    }

    RECEIPT.parent.mkdir(parents=True, exist_ok=True)
    tmp = RECEIPT.with_suffix(".tmp")
    tmp.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(RECEIPT)

    check_receipt()
    print(f"receipt={RECEIPT}")


def check_receipt() -> None:
    git_clean()
    head, tree = git_identity()

    try:
        receipt = json.loads(RECEIPT.read_text(encoding="utf-8"))
    except FileNotFoundError:
        fail(f"qualification receipt missing: {RECEIPT}")
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"qualification receipt unreadable: {exc}")

    if receipt.get("schema") != "catcleaner.developer-id-qualification/v1":
        fail("unexpected Developer ID qualification receipt schema")
    if receipt.get("head") != head or receipt.get("tree") != tree:
        fail("Developer ID qualification receipt does not match current HEAD/tree")

    current = local_state(
        preferred_identity=str(receipt.get("identity", "")),
        preferred_team=str(receipt.get("team_id", "")),
    )
    for field in (
        "identity_sha1",
        "identity",
        "team_id",
        "cert_sha1",
        "cert_sha256",
        "subject",
        "issuer",
        "serial",
        "not_before",
        "not_after",
    ):
        if receipt.get(field) != current.get(field):
            fail(
                f"Developer ID qualification changed for {field}: "
                f"receipt={receipt.get(field)!r} current={current.get(field)!r}"
            )

    if current["team_id"] == UPSTREAM_TEAM_ID:
        fail("refusing upstream Mac Sai Team ID")

    print("CATCLEANER_DEVELOPER_ID_QUALIFICATION_PASS")
    print(f"identity={current['identity']}")
    print(f"team_id={current['team_id']}")
    print(f"cert_sha256={current['cert_sha256']}")


def main() -> int:
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--local", action="store_true")
    group.add_argument("--qualify", action="store_true")
    group.add_argument("--check", action="store_true")
    args = parser.parse_args()

    if args.local:
        candidates = eligible_identities()
        if not candidates:
            fail("no eligible Developer ID Application identity found in Keychain", 78)
        print("CATCLEANER_DEVELOPER_ID_LOCAL_PASS")
        print(f"eligible_count={len(candidates)}")
        if len(candidates) == 1:
            print(f"identity={candidates[0]['identity']}")
            print(f"team_id={candidates[0]['team_id']}")
        else:
            print("selection=qualification_receipt_or_CATCLEANER_DEVELOPER_ID_required")
        return 0
    if args.qualify:
        qualify()
        return 0

    check_receipt()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
