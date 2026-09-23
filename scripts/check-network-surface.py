#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]

NETWORK_RE = re.compile(r"\b(?:URLSession|URLRequest|NSURLConnection|NWConnection)\b")
ALLOWED_NETWORK_FILES = {
    Path("Sources/MacCleanKit/UpdateChecker.swift"),
    Path("Sources/MacClean/Modules/Updater/UpdaterModule.swift"),
}

FORBIDDEN_TELEMETRY_PATTERNS = {
    "SentrySDK": re.compile(r"\bSentrySDK\b"),
    "FirebaseAnalytics": re.compile(r"\bFirebaseAnalytics\b|\bAnalytics\.logEvent\b"),
    "Mixpanel": re.compile(r"\bMixpanel\b"),
    "Amplitude": re.compile(r"\bAmplitude\b"),
    "PostHog": re.compile(r"\bPostHog\b"),
    "Segment": re.compile(r"\bAnalytics-Swift\b|segment\.io", re.I),
    "Datadog": re.compile(r"\bDatadog\b|datadoghq\.com", re.I),
}

SCAN_SUFFIXES = {".swift", ".json", ".yml", ".yaml", ".toml"}
SCAN_FILES = [ROOT / "Package.swift"]


def text_files():
    for base in [ROOT / "Sources", ROOT / ".github"]:
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if path.is_file() and path.suffix in SCAN_SUFFIXES:
                yield path
    for path in SCAN_FILES:
        if path.is_file():
            yield path


def rel(path: Path) -> Path:
    return path.relative_to(ROOT)


def main() -> int:
    network_files: set[Path] = set()
    telemetry_hits: list[tuple[str, Path]] = []

    for path in text_files():
        try:
            content = path.read_text(errors="ignore")
        except OSError:
            continue

        relative = rel(path)
        if path.suffix == ".swift" and NETWORK_RE.search(content):
            network_files.add(relative)

        for name, pattern in FORBIDDEN_TELEMETRY_PATTERNS.items():
            if pattern.search(content):
                telemetry_hits.append((name, relative))

    unexpected = sorted(network_files - ALLOWED_NETWORK_FILES)
    missing_expected = sorted(ALLOWED_NETWORK_FILES - network_files)

    constants = ROOT / "Sources/MacCleanKit/Constants.swift"
    constants_text = constants.read_text(errors="ignore")
    self_update_fail_closed = (
        "public static let updateChecksEnabled = false" in constants_text
        and "public static let latestReleaseAPI: URL? = nil" in constants_text
        and "public static let homebrewCaskAPI: URL? = nil" in constants_text
    )

    ok = True

    if unexpected:
        ok = False
        print("ERROR: unexpected network-capable source files:", file=sys.stderr)
        for path in unexpected:
            print(f"  {path}", file=sys.stderr)

    if missing_expected:
        ok = False
        print("ERROR: network policy allowlist drift; expected file no longer matches network API scan:", file=sys.stderr)
        for path in missing_expected:
            print(f"  {path}", file=sys.stderr)

    if telemetry_hits:
        ok = False
        print("ERROR: telemetry/analytics token(s) detected:", file=sys.stderr)
        for name, path in telemetry_hits:
            print(f"  {name}: {path}", file=sys.stderr)

    if not self_update_fail_closed:
        ok = False
        print(
            "ERROR: CatCleaner self-update path is no longer fail-closed; "
            "update privacy/release policy before enabling it.",
            file=sys.stderr,
        )

    if not ok:
        return 1

    print("CATCLEANER_NETWORK_SURFACE_PASS")
    print("network_capable_files=2")
    for path in sorted(network_files):
        print(f"  {path}")
    print("telemetry_sdks=0")
    print("self_update=FAIL_CLOSED")
    print("third_party_app_updater=USER_INITIATED_HTTPS_ONLY")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
