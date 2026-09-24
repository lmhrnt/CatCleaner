#!/bin/bash
# CatCleaner public-release readiness audit.
#
# Read-only: this script never changes xcode-select, Git remotes, Keychain,
# signing identities, workflows, source files, or release state.
#
# Exit codes:
#   0  Public-release prerequisites satisfied.
#   2  One or more required release prerequisites are still blocked.
#   64 Invalid arguments.

set -euo pipefail

MODE="human"
case "${1:-}" in
  "") ;;
  --quiet) MODE="quiet" ;;
  *)
    echo "Usage: $0 [--quiet]" >&2
    exit 64
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$ROOT"

required_failures=0
warnings=0

emit() {
  if [[ "$MODE" != "quiet" ]]; then
    printf '%-9s %-30s %s\n' "$1" "$2" "$3"
  fi
}

pass() {
  emit "PASS" "$1" "$2"
}

block() {
  emit "BLOCK" "$1" "$2"
  required_failures=$((required_failures + 1))
}

warn() {
  emit "WARN" "$1" "$2"
  warnings=$((warnings + 1))
}

info() {
  emit "INFO" "$1" "$2"
}

if [[ "$MODE" != "quiet" ]]; then
  echo "CatCleaner public-release readiness"
  echo "repo=$ROOT"
  echo
fi

# 1. Public release evidence must bind to an exact clean source tree.
git_dirty="$(git status --porcelain)"
if [[ -z "$git_dirty" ]]; then
  pass "git_worktree" "clean"
else
  block "git_worktree" "working tree has tracked or untracked changes"
fi

# 2. Full Xcode is required for SwiftUI macros, XCTest, and final app build.
# Installation alone is not sufficient: a full qualification receipt must bind
# the current HEAD/tree, Xcode version, and built app binary hashes.
set +e
developer_dir="$(${SCRIPT_DIR}/resolve-xcode.sh 2>/dev/null)"
xcode_rc=$?
set -e
if [[ $xcode_rc -eq 0 ]] && [[ -n "$developer_dir" ]]; then
  pass "full_xcode" "$developer_dir"
  if python3 scripts/check-xcode-qualification.py \
      --developer-dir "$developer_dir" >/dev/null 2>&1; then
    pass "xcode_qualification" "full XCTest/universal-app receipt matches current source and toolchain"
  else
    block "xcode_qualification" "run ./scripts/xcode-qualification.sh --full on this exact clean source"
  fi
else
  current_dir="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
  block "full_xcode" "full Xcode is required; current=${current_dir:-<none>}"
  info "xcode_qualification" "not evaluated until full Xcode is available"
fi

# 3. The product needs a CatCleaner-owned publication remote. Presence alone
# is not enough: once configured, a qualification receipt must prove GitHub
# ADMIN permission and remote default-branch HEAD parity with this source.
set +e
origin_local="$(python3 -B scripts/origin-qualification.py --local 2>/dev/null)"
origin_local_rc=$?
set -e
if [[ $origin_local_rc -eq 0 ]]; then
  origin_url="$(git remote get-url origin 2>/dev/null || true)"
  pass "catcleaner_origin" "$origin_url"
  if python3 -B scripts/origin-qualification.py --check >/dev/null 2>&1; then
    pass "origin_qualification" "ADMIN GitHub origin receipt matches current HEAD/tree and remote URLs"
  else
    block "origin_qualification" "run python3 scripts/origin-qualification.py --qualify after configuring and pushing the exact source"
  fi
else
  block "catcleaner_origin" "no valid GitHub CatCleaner origin is configured"
  info "origin_qualification" "not evaluated until a valid CatCleaner origin exists"
fi

# 4. Upstream must remain fetch-only/fail-closed for push.
upstream_fetch="$(git remote get-url upstream 2>/dev/null || true)"
upstream_push="$(git remote get-url --push upstream 2>/dev/null || true)"
if [[ "$upstream_fetch" == "https://github.com/iliyami/MacSai.git" ]] &&
   [[ "$upstream_push" == "https://example.invalid/CatCleaner-upstream-push-disabled.git" ]]; then
  pass "upstream_boundary" "Mac Sai fetch-only; push fails closed"
else
  block "upstream_boundary" "upstream remote boundary is not in the expected fail-closed state"
fi

# 5. Public macOS distribution requires one eligible CatCleaner Developer ID
# Application identity. Once present, bind its certificate fingerprint, Team ID,
# validity window and exact source into a local qualification receipt.
set +e
developer_local="$(python3 -B scripts/developer-id-qualification.py --local 2>/dev/null)"
developer_local_rc=$?
set -e
if [[ $developer_local_rc -eq 0 ]]; then
  developer_id="$(printf '%s\n' "$developer_local" | sed -n 's/^identity=//p' | head -1)"
  pass "developer_id" "$developer_id"
  if python3 -B scripts/developer-id-qualification.py --check >/dev/null 2>&1; then
    pass "developer_id_qualification" "certificate/Team ID receipt matches current HEAD/tree and Keychain"
  else
    block "developer_id_qualification" "run python3 scripts/developer-id-qualification.py --qualify for this exact clean source"
  fi
else
  block "developer_id" "no unique eligible non-upstream Developer ID Application identity is available"
  info "developer_id_qualification" "not evaluated until an eligible Developer ID exists"
fi

# 6. Release/signing workflows may be checked in before credentials exist, but
# they must satisfy the executable fail-closed contract enforced in CI.
if python3 scripts/check-release-contract.py --scope release >/dev/null 2>&1; then
  pass "release_workflow" "fail-closed publication contract verified"
else
  block "release_workflow" "release workflow failed the fail-closed publication contract"
fi

if python3 scripts/check-release-contract.py --scope signing >/dev/null 2>&1; then
  pass "signing_workflow" "fail-closed signing/notarization contract verified"
else
  block "signing_workflow" "signing workflow failed the fail-closed verification contract"
fi

# 7. Release build sources must remain version-consistent.
if bash scripts/check-version-sync.sh >/dev/null 2>&1; then
  version="$(tr -d '[:space:]' < VERSION)"
  pass "version_sync" "$version"
else
  block "version_sync" "VERSION and MCConstants.appVersion differ"
fi

# 8. Runtime identity must not regress to upstream names.
if bash scripts/check-runtime-identity.sh >/dev/null 2>&1; then
  pass "runtime_identity" "no upstream runtime/release identifiers"
else
  block "runtime_identity" "upstream runtime identity references remain"
fi

# 9. Public branding. Generic icon is technically runnable, but not a polished
# product release. If an icon exists, reject the exact upstream Mac Sai asset.
upstream_icon_sha="216276c7544ea99500930c333b55bb740689c0b60c079ce7b4b1e4cf459ede9f"
if [[ -f Resources/AppIcon.icns ]]; then
  icon_sha="$(shasum -a 256 Resources/AppIcon.icns | awk '{print $1}')"
  if [[ "$icon_sha" == "$upstream_icon_sha" ]]; then
    block "product_icon" "AppIcon is the unchanged upstream Mac Sai asset"
  else
    pass "product_icon" "CatCleaner-owned/different AppIcon present"
  fi
else
  warn "product_icon" "no custom CatCleaner main icon; generic macOS icon will be used"
fi

# 10. These are not required for a first notarized DMG, but are required before
# enabling the corresponding product/distribution features.
if rg -q 'public static let updateChecksEnabled = false' Sources/MacCleanKit/Constants.swift; then
  warn "self_update" "self-update remains fail-closed"
else
  pass "self_update" "self-update is enabled"
fi

if rg -q 'public static let teamIdentifier: String\? = nil' Sources/MacCleanKit/Constants.swift; then
  warn "team_identifier" "privileged/XPC signing team is intentionally unconfigured"
else
  pass "team_identifier" "CatCleaner signing team is configured in source"
fi

if [[ -f Casks/catcleaner.rb ]]; then
  pass "homebrew_cask" "CatCleaner cask exists"
else
  warn "homebrew_cask" "optional Homebrew distribution is not configured"
fi

if rg -q 'CatCleaner remote installer is not enabled yet' scripts/install.sh; then
  warn "remote_installer" "remote installer remains fail-closed"
else
  pass "remote_installer" "remote installer is enabled"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  info "notary_profile" "NOTARY_PROFILE is set for this shell"
else
  warn "notary_profile" "NOTARY_PROFILE is not set in this shell"
fi

if [[ "$MODE" != "quiet" ]]; then
  echo
  echo "required_blockers=$required_failures"
  echo "warnings=$warnings"
fi

if (( required_failures > 0 )); then
  if [[ "$MODE" != "quiet" ]]; then
    echo "verdict=HOLD"
  fi
  exit 2
fi

if [[ "$MODE" != "quiet" ]]; then
  echo "verdict=READY"
fi
exit 0
