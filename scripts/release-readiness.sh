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

# 1. Full Xcode is required for SwiftUI macros, XCTest, and final app build.
# Resolve it locally without changing global xcode-select.
set +e
developer_dir="$(${SCRIPT_DIR}/resolve-xcode.sh 2>/dev/null)"
xcode_rc=$?
set -e
if [[ $xcode_rc -eq 0 ]] && [[ -n "$developer_dir" ]]; then
  pass "full_xcode" "$developer_dir"
else
  current_dir="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
  block "full_xcode" "full Xcode is required; current=${current_dir:-<none>}"
fi

# 2. The product needs a CatCleaner-owned publication remote.
origin_url="$(git remote get-url origin 2>/dev/null || true)"
if [[ -n "$origin_url" ]] && [[ "$origin_url" != *"MacSai"* ]]; then
  pass "catcleaner_origin" "$origin_url"
else
  block "catcleaner_origin" "no CatCleaner-owned origin remote is configured"
fi

# 3. Upstream must remain fetch-only/fail-closed for push.
upstream_fetch="$(git remote get-url upstream 2>/dev/null || true)"
upstream_push="$(git remote get-url --push upstream 2>/dev/null || true)"
if [[ "$upstream_fetch" == "https://github.com/iliyami/MacSai.git" ]] &&
   [[ "$upstream_push" == "https://example.invalid/CatCleaner-upstream-push-disabled.git" ]]; then
  pass "upstream_boundary" "Mac Sai fetch-only; push fails closed"
else
  block "upstream_boundary" "upstream remote boundary is not in the expected fail-closed state"
fi

# 4. Public macOS distribution requires a real Developer ID Application cert.
developer_id="$(
  security find-identity -v -p codesigning 2>/dev/null |
    sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' |
    head -1
)"
if [[ -z "$developer_id" ]]; then
  block "developer_id" "no Developer ID Application identity found in Keychain"
elif [[ "$developer_id" == *"H3XLS95QV4"* ]] || [[ "$developer_id" == *"Iliya Mirzaei"* ]]; then
  block "developer_id" "upstream Mac Sai Developer ID must not be reused: $developer_id"
else
  pass "developer_id" "$developer_id"
fi

# 5. Release publishing workflows intentionally stay disabled until the above
# identities and secrets are CatCleaner-owned.
if rg -q '^name: CatCleaner Release \(disabled\)$' .github/workflows/release.yml; then
  block "release_workflow" "publishing workflow is intentionally disabled"
else
  pass "release_workflow" "release workflow is enabled"
fi

if rg -q '^name: CatCleaner Signing Verification \(disabled\)$' .github/workflows/verify-signing.yml; then
  block "signing_workflow" "signing verification workflow is intentionally disabled"
else
  pass "signing_workflow" "signing verification workflow is enabled"
fi

# 6. Release build sources must remain version-consistent.
if bash scripts/check-version-sync.sh >/dev/null 2>&1; then
  version="$(tr -d '[:space:]' < VERSION)"
  pass "version_sync" "$version"
else
  block "version_sync" "VERSION and MCConstants.appVersion differ"
fi

# 7. Runtime identity must not regress to upstream names.
forbidden="$(
  rg -n     'com\.macclean|macclean://|brew upgrade --cask mac-sai|Mac Sai\.app|MacSai-'     Sources Package.swift     scripts/build-dmg.sh     scripts/dev-install.sh     scripts/install.sh     scripts/uninstall.sh     scripts/setup-homebrew-tap.sh     2>/dev/null || true
)"
if [[ -z "$forbidden" ]]; then
  pass "runtime_identity" "no upstream runtime/release identifiers"
else
  block "runtime_identity" "upstream runtime identity references remain"
fi

# 8. Public branding. Generic icon is technically runnable, but not a polished
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

# 9. These are not required for a first notarized DMG, but are required before
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
