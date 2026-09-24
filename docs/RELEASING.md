# Releasing CatCleaner

CatCleaner is an independent downstream product derived from Mac Sai.

**Release publishing is fail-closed right now.** The repository contains
manual release/signing workflows, but publishing requires an existing matching
version tag, an explicit `publish=true` dispatch, CatCleaner-owned signing
secrets, and successful signing/notarization verification. The project must not
reuse the upstream project's signing identity, notarization credentials, GitHub
release feed, Homebrew tap, or visual branding.

## Current release state

Run the read-only readiness audit first:

```bash
./scripts/release-readiness.sh
```

Exit code `0` means required public-release prerequisites are satisfied for the exact current clean source. Exit code `2` means the release remains on HOLD. Xcode, GitHub origin, and Developer ID each require a matching qualification receipt; merely installing/configuring the prerequisite is not sufficient. Optional distribution/branding items are reported separately as warnings.

The following are deliberately fail-closed:

- `.github/workflows/release.yml`: manual-only, tag-bound, `publish=false` by default
- `.github/workflows/verify-signing.yml`: manual-only and verification-only
- `scripts/check-release-contract.py`: executable guardrail for both workflow contracts
- `MCConstants.updateChecksEnabled == false`
- `MCConstants.latestReleaseAPI == nil`
- `MCConstants.homebrewCaskAPI == nil`
- `MCConstants.releasesURL == nil`
- `MCConstants.issuesURL == nil`
- `MCConstants.teamIdentifier == nil`
- no CatCleaner Homebrew cask
- no remote installer
- no CatCleaner-owned `origin` remote yet

The `upstream` Git remote is for fetching Mac Sai history only. Its push URL
is intentionally set to an invalid destination in the local checkout so an
accidental push fails closed.

### Qualification receipts

All authoritative receipts live under `.build/qualification/` and are ignored by Git. They bind an exact clean HEAD/tree to the prerequisite evidence:

```bash
# After full Xcode is installed:
./scripts/xcode-qualification.sh --full

# After a CatCleaner GitHub repo exists, is configured as origin, and this exact
# HEAD has already been pushed to its default branch:
python3 scripts/origin-qualification.py --qualify

# After a CatCleaner Developer ID Application identity exists in Keychain:
python3 scripts/developer-id-qualification.py --qualify
```

The origin qualifier is read-only: it never creates a repository, changes a remote, or pushes. It requires the origin fetch/push URLs to target the same GitHub `CatCleaner` repository, GitHub `ADMIN` permission, and the remote default-branch HEAD to equal local `HEAD`.

The Developer ID qualifier is also read-only. It requires one eligible non-upstream `Developer ID Application` identity, validates certificate fingerprint, Team ID and validity window, and binds them to the exact source. It does not use a local private-key signing probe because non-interactive Keychain ACLs can reject otherwise valid identities; actual Developer ID signing is exercised by the signing/release workflows with an ephemeral CI Keychain.

## Never reuse upstream identity

Do **not** use any signing team, certificate, notary profile, GitHub token,
Homebrew repository, release URL, or credential copied from Mac Sai.

In particular, CatCleaner must never be configured with:

- the upstream Developer Team ID
- an upstream Developer ID certificate
- an upstream notary profile
- the upstream Mac Sai GitHub release API
- the upstream Mac Sai Homebrew cask/tap

The upstream project remains a source-code attribution and fetch remote only.

## Local development build

A full Xcode installation is required for the SwiftUI app targets.

Preflight:

```bash
./scripts/build-preflight.sh --core-only
./scripts/build-preflight.sh --app
./scripts/build-preflight.sh --tests
```

With full Xcode available, run the one-shot qualification first:

```bash
./scripts/xcode-qualification.sh --full
```

The full mode requires a clean Git working tree and binds the current HEAD/tree, exact Xcode version, and built app binary SHA-256 values into:

```text
.build/qualification/xcode-qualification-v1.json
```

For a faster native-architecture development check without producing an authoritative receipt:

```bash
./scripts/xcode-qualification.sh --quick
```

The qualification build produces an ad-hoc-signed development bundle at:

```text
.build/dmg/CatCleaner.app
```

The development bundle is not a public release and is not notarized.

## Requirements before enabling public releases

All of the following must be completed with **CatCleaner-owned** identities:

1. Create the CatCleaner GitHub repository, add it as `origin`, push the exact release source to its default branch, then run `python3 scripts/origin-qualification.py --qualify`.
2. Keep Mac Sai as `upstream` fetch-only.
3. Create or select the CatCleaner Apple Developer signing team.
4. Configure a CatCleaner Developer ID Application certificate, then run `python3 scripts/developer-id-qualification.py --qualify`.
5. Configure CatCleaner notarization credentials.
6. Configure a CatCleaner notarytool Keychain profile.
7. Set `MCConstants.teamIdentifier` to the CatCleaner Team ID only after the
   privileged/XPC trust model is actually enabled and tested.
8. Create CatCleaner-owned release and issue URLs.
9. Enable the self-update feed only after releases are signed and published.
10. If Homebrew distribution is desired, create a CatCleaner-specific cask and
    repository; do not reuse the Mac Sai tap.
11. Replace all temporary/generic branding with CatCleaner-owned visual assets.
12. Run `./scripts/xcode-qualification.sh --full` on the exact clean release source and preserve the matching qualification receipt.
13. Perform a clean-machine install/uninstall smoke test.
14. Verify Gatekeeper, notarization, stapling, Full Disk Access behavior, login
    item registration, and menu helper identity.

Only after this checklist is satisfied should CatCleaner-owned credentials be
configured and the release workflow be manually dispatched from the matching
version tag with `publish=true`. The checked-in workflows remain fail-closed
before those prerequisites exist.

## Future notarized local build

Once CatCleaner has its own signing identity and notary profile:

```bash
export APPLE_DEVELOPER_ID="Developer ID Application: <CatCleaner Owner> (<TEAMID>)"
export NOTARY_PROFILE="<CatCleaner-owned-notary-profile>"

./scripts/build-dmg.sh --notarize
```

The build script will:

1. Build `MacClean` and `MacCleanMenu`.
2. Assemble `CatCleaner.app`.
3. Bundle the menu helper as a LoginItem.
4. Sign with the configured CatCleaner Developer ID.
5. Notarize and staple the app.
6. Build the DMG.
7. Sign, notarize, and staple the DMG.

## Required future CI secrets

The checked-in workflows currently expect these CatCleaner-owned GitHub
Actions secrets:

| Secret | Purpose |
|---|---|
| `CATCLEANER_CERTIFICATE_P12_BASE64` | Base64-encoded CatCleaner Developer ID Application certificate |
| `CATCLEANER_CERTIFICATE_PASSWORD` | Password for that P12 |
| `CATCLEANER_APPLE_ID` | Apple ID used by CatCleaner's notarization credentials |
| `CATCLEANER_APP_PASSWORD` | App-specific password used by `notarytool` |
| `CATCLEANER_TEAM_ID` | CatCleaner Apple Developer Team ID |

The workflow imports the certificate into an ephemeral CI Keychain, derives the
actual Developer ID identity from that certificate, rejects the upstream Team
ID, and creates an ephemeral `notarytool` profile for that run.

Never populate these secrets with credentials belonging to the upstream
project.

## Verification before publishing

At minimum:

```bash
swift build --target MacCleanKit
swift build --product MacClean
swift build --product MacCleanMenu
swift test --enable-code-coverage

codesign --verify --deep --strict .build/dmg/CatCleaner.app
codesign -dv --verbose=4 .build/dmg/CatCleaner.app
spctl --assess --type execute --verbose=4 .build/dmg/CatCleaner.app
```

For notarized builds, also validate stapling for both app and DMG.

## Versioning

`VERSION` and `MCConstants.appVersion` must match:

```bash
bash scripts/check-version-sync.sh
```

Current development version is `0.1.0`.
