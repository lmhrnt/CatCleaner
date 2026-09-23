# CatCleaner Privacy & Network Policy

CatCleaner is designed to perform storage analysis and cleanup locally on the Mac.

## Local-only operations

The following features inspect local filesystem/process/system state only and do not upload file contents:

- Smart Scan and System Junk
- Uninstaller and Removed App Leftovers
- Large/Old Files
- Exact Duplicates
- Similar Photos (Apple Vision feature prints are computed locally)
- Space Lens
- Developer Cleanup
- Startup Items / Optimization
- Maintenance tasks
- Privacy / Malware / Wi-Fi inspection
- Shredder
- Menu-bar system monitoring

CatCleaner does not contain analytics, advertising, telemetry, crash-reporting, or behavioral-tracking SDKs.

## Network-capable features

The source tree intentionally permits network APIs in only two files:

1. `Sources/MacCleanKit/UpdateChecker.swift`
   - CatCleaner self-update checks.
   - Currently fail-closed because CatCleaner does not yet own a signed release feed.
   - `MCConstants.updateChecksEnabled` must remain `false` until a CatCleaner-owned release channel exists.

2. `Sources/MacClean/Modules/Updater/UpdaterModule.swift`
   - Third-party application update checking.
   - Runs only after the user opens App Updater and explicitly presses **Check for Updates**.
   - Reads each installed app's own Sparkle `SUFeedURL`.
   - Only HTTPS feeds are accepted.
   - CatCleaner does not proxy these requests through a CatCleaner server and does not upload user files.

## CI enforcement

Run:

```bash
python3 scripts/check-network-surface.py
```

The check fails if:

- a new source file introduces `URLSession`, `URLRequest`, `NSURLConnection`, or `NWConnection`;
- a known telemetry/analytics SDK token appears in source or Package.swift;
- CatCleaner self-update checks are enabled without deliberately changing this policy.

Adding any new network-capable source file requires an explicit policy update and review.
