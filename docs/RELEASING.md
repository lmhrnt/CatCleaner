# Releasing CatCleaner

CatCleaner is an independent downstream product derived from Mac Sai.

**Release publishing is intentionally disabled right now.** The repository may
build local ad-hoc app bundles for development, but it must not reuse the
upstream project's signing identity, notarization credentials, GitHub release
feed, Homebrew tap, or visual branding.

## Current release state

The following are deliberately fail-closed:

- `.github/workflows/release.yml`
- `.github/workflows/verify-signing.yml`
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

With full Xcode available:

```bash
BUILD_ARCHS="--arch $(uname -m)" ./scripts/build-dmg.sh --app-only
```

This produces an ad-hoc-signed development bundle at:

```text
.build/dmg/CatCleaner.app
```

The development bundle is not a public release and is not notarized.

## Requirements before enabling public releases

All of the following must be completed with **CatCleaner-owned** identities:

1. Create the CatCleaner GitHub repository and add it as `origin`.
2. Keep Mac Sai as `upstream` fetch-only.
3. Create or select the CatCleaner Apple Developer signing team.
4. Configure a CatCleaner Developer ID Application certificate.
5. Configure CatCleaner notarization credentials.
6. Configure a CatCleaner notarytool Keychain profile.
7. Set `MCConstants.teamIdentifier` to the CatCleaner Team ID only after the
   privileged/XPC trust model is actually enabled and tested.
8. Create CatCleaner-owned release and issue URLs.
9. Enable the self-update feed only after releases are signed and published.
10. If Homebrew distribution is desired, create a CatCleaner-specific cask and
    repository; do not reuse the Mac Sai tap.
11. Replace all temporary/generic branding with CatCleaner-owned visual assets.
12. Run the full Xcode CI suite and app-bundle identity checks.
13. Perform a clean-machine install/uninstall smoke test.
14. Verify Gatekeeper, notarization, stapling, Full Disk Access behavior, login
    item registration, and menu helper identity.

Only after this checklist is satisfied should the disabled release/signing
workflows be replaced with active publishing workflows.

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

Secret names may follow the existing workflow conventions, but every value must
belong to CatCleaner:

| Secret | Purpose |
|---|---|
| `APPLE_DEVELOPER_ID` | CatCleaner Developer ID Application identity |
| `DEVELOPER_ID_CERT_P12` | Base64-encoded CatCleaner signing certificate |
| `DEVELOPER_ID_CERT_PASSWORD` | Password for that P12 |
| `ASC_KEY_ID` | CatCleaner/App Store Connect API key ID |
| `ASC_ISSUER_ID` | App Store Connect issuer ID |
| `ASC_KEY_P8_BASE64` | Base64-encoded CatCleaner notarization API key |
| `NOTARY_PROFILE` | CatCleaner-owned notarytool profile name |
| optional CatCleaner tap token | Only if a CatCleaner Homebrew tap exists |

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
