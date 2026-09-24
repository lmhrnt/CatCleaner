#!/usr/bin/env python3
"""Qualify and validate CatCleaner's GitHub publication origin.

Modes:
  --local    Validate only the configured local Git remote shape/boundary.
  --qualify  Read GitHub metadata, require ADMIN permission and remote HEAD parity,
             then write a SHA-bound receipt under .build/qualification.
  --check    Validate the existing receipt against the current clean source/remotes.

No mode creates repositories, pushes commits, changes remotes, or mutates GitHub.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent.parent
RECEIPT = ROOT / ".build/qualification/origin-qualification-v1.json"
UPSTREAM_FETCH = "https://github.com/iliyami/MacSai.git"
UPSTREAM_PUSH = "https://example.invalid/CatCleaner-upstream-push-disabled.git"


def fail(message: str, code: int = 1) -> None:
    print(f"ORIGIN_QUALIFICATION_FAIL: {message}", file=sys.stderr)
    raise SystemExit(code)


def run(*args: str, check: bool = True) -> str:
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
    dirty = run("git", "status", "--porcelain")
    if dirty:
        fail("Git working tree is not clean")


def git_identity() -> tuple[str, str]:
    return (
        run("git", "rev-parse", "HEAD"),
        run("git", "rev-parse", "HEAD^{tree}"),
    )


def remote_url(name: str, push: bool = False) -> str:
    args = ["git", "remote", "get-url"]
    if push:
        args.append("--push")
    args.append(name)
    proc = subprocess.run(
        args,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    if proc.returncode != 0:
        return ""
    return proc.stdout.strip()


def parse_github_repo(url: str) -> tuple[str, str]:
    if not url:
        fail("origin remote is not configured", 78)

    if re.match(r"^https?://[^/]*@", url):
        fail("origin URL must not embed credentials")

    owner_repo = ""
    if url.startswith("git@github.com:"):
        owner_repo = url[len("git@github.com:") :]
    elif url.startswith("ssh://git@github.com/"):
        owner_repo = url[len("ssh://git@github.com/") :]
    else:
        parsed = urlparse(url)
        if parsed.scheme not in ("https", "http") or parsed.hostname != "github.com":
            fail(f"origin must point to github.com, got: {url}")
        if parsed.scheme != "https":
            fail("origin HTTP URL must use HTTPS")
        owner_repo = parsed.path.lstrip("/")

    if owner_repo.endswith(".git"):
        owner_repo = owner_repo[:-4]

    parts = [part for part in owner_repo.split("/") if part]
    if len(parts) != 2:
        fail(f"origin must be owner/repository, got: {url}")

    owner, repo = parts
    if repo.lower() != "catcleaner":
        fail(f"origin repository must be CatCleaner, got: {repo}")
    if owner.lower() == "iliyami":
        fail("origin must not be the upstream Mac Sai owner")

    return owner, repo


def local_state(*, check_upstream: bool = True) -> dict[str, str]:
    fetch = remote_url("origin")
    push = remote_url("origin", push=True)
    fetch_owner, fetch_repo = parse_github_repo(fetch)
    push_owner, push_repo = parse_github_repo(push)

    if (fetch_owner.lower(), fetch_repo.lower()) != (
        push_owner.lower(),
        push_repo.lower(),
    ):
        fail("origin fetch and push URLs must target the same CatCleaner repository")

    upstream_fetch = remote_url("upstream")
    upstream_push = remote_url("upstream", push=True)
    if check_upstream and (
        upstream_fetch != UPSTREAM_FETCH or upstream_push != UPSTREAM_PUSH
    ):
        fail("upstream fetch-only boundary is not in the expected fail-closed state")

    return {
        "fetch_url": fetch,
        "push_url": push,
        "owner": fetch_owner,
        "repo": fetch_repo,
        "slug": f"{fetch_owner}/{fetch_repo}",
        "upstream_fetch": upstream_fetch,
        "upstream_push": upstream_push,
    }


def qualify() -> None:
    git_clean()
    head, tree = git_identity()
    local = local_state()

    auth = subprocess.run(
        ["gh", "auth", "status", "-h", "github.com"],
        cwd=ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    if auth.returncode != 0:
        fail(f"GitHub CLI is not authenticated: {auth.stderr.strip()}", 78)

    repo_json_text = run(
        "gh",
        "repo",
        "view",
        local["slug"],
        "--json",
        "nameWithOwner,viewerPermission,isArchived,isPrivate,defaultBranchRef,url",
    )
    try:
        repo_info = json.loads(repo_json_text)
    except json.JSONDecodeError as exc:
        fail(f"invalid gh repo JSON: {exc}")

    if str(repo_info.get("nameWithOwner", "")).lower() != local["slug"].lower():
        fail(
            "GitHub repository identity mismatch: "
            f"expected={local['slug']} actual={repo_info.get('nameWithOwner')}"
        )
    if repo_info.get("viewerPermission") != "ADMIN":
        fail(
            "GitHub ADMIN permission is required for the publication origin: "
            f"viewerPermission={repo_info.get('viewerPermission')}"
        )
    if repo_info.get("isArchived") is True:
        fail("CatCleaner publication repository is archived")

    default_ref = repo_info.get("defaultBranchRef") or {}
    default_branch = default_ref.get("name")
    if not default_branch:
        fail("CatCleaner repository has no default branch; push the qualified source first")

    remote_ref = f"refs/heads/{default_branch}"
    ls_remote = run("git", "ls-remote", "origin", remote_ref)
    remote_lines = [line for line in ls_remote.splitlines() if line.strip()]
    if len(remote_lines) != 1:
        fail(
            "unable to resolve exactly one remote default-branch ref from origin: "
            f"ref={remote_ref} matches={len(remote_lines)}"
        )
    remote_head, resolved_ref = remote_lines[0].split(None, 1)
    if resolved_ref != remote_ref:
        fail(
            "origin default-branch ref mismatch: "
            f"expected={remote_ref} actual={resolved_ref}"
        )
    if remote_head != head:
        fail(
            "remote default branch HEAD does not match local HEAD: "
            f"remote={remote_head} local={head}"
        )

    receipt = {
        "schema": "catcleaner.origin-qualification/v1",
        "qualified_at_utc": datetime.now(timezone.utc).isoformat(),
        "head": head,
        "tree": tree,
        "fetch_url": local["fetch_url"],
        "push_url": local["push_url"],
        "repository": repo_info["nameWithOwner"],
        "viewer_permission": repo_info["viewerPermission"],
        "is_private": bool(repo_info.get("isPrivate")),
        "default_branch": default_branch,
        "remote_head_sha": remote_head,
        "github_url": repo_info.get("url"),
        "upstream_fetch": local["upstream_fetch"],
        "upstream_push": local["upstream_push"],
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
    local = local_state()

    try:
        receipt = json.loads(RECEIPT.read_text(encoding="utf-8"))
    except FileNotFoundError:
        fail(f"qualification receipt missing: {RECEIPT}")
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"qualification receipt unreadable: {exc}")

    if receipt.get("schema") != "catcleaner.origin-qualification/v1":
        fail("unexpected origin qualification receipt schema")
    if receipt.get("head") != head or receipt.get("tree") != tree:
        fail("origin qualification receipt does not match current HEAD/tree")
    if receipt.get("fetch_url") != local["fetch_url"]:
        fail("origin fetch URL changed since qualification")
    if receipt.get("push_url") != local["push_url"]:
        fail("origin push URL changed since qualification")
    if str(receipt.get("repository", "")).lower() != local["slug"].lower():
        fail("qualified GitHub repository no longer matches origin")
    if receipt.get("viewer_permission") != "ADMIN":
        fail("qualification receipt does not establish ADMIN permission")
    if receipt.get("remote_head_sha") != head:
        fail("qualification receipt remote HEAD does not match current HEAD")
    if receipt.get("upstream_fetch") != UPSTREAM_FETCH:
        fail("qualified upstream fetch URL is unexpected")
    if receipt.get("upstream_push") != UPSTREAM_PUSH:
        fail("qualified upstream push boundary is unexpected")

    print("CATCLEANER_ORIGIN_QUALIFICATION_PASS")
    print(f"repository={receipt.get('repository')}")
    print(f"head={head}")


def main() -> int:
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--local", action="store_true")
    group.add_argument("--qualify", action="store_true")
    group.add_argument("--check", action="store_true")
    args = parser.parse_args()

    if args.local:
        local = local_state(check_upstream=False)
        print("CATCLEANER_ORIGIN_LOCAL_PASS")
        print(f"repository={local['slug']}")
        return 0
    if args.qualify:
        qualify()
        return 0

    check_receipt()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
