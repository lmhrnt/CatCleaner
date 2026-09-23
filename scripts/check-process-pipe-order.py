#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "Sources"
WINDOW = 16


def main() -> int:
    hits: list[tuple[Path, int, str]] = []

    for path in sorted(SOURCE_ROOT.rglob("*.swift")):
        try:
            lines = path.read_text(errors="ignore").splitlines()
        except OSError:
            continue

        for index, line in enumerate(lines):
            if "waitUntilExit()" not in line:
                continue

            window = lines[index : min(len(lines), index + WINDOW)]
            body = "\n".join(window)
            if "readDataToEndOfFile" in body or "availableData" in body:
                hits.append((path.relative_to(ROOT), index + 1, body))

    if not hits:
        print("PROCESS_PIPE_ORDER_PASS production_hits=0")
        return 0

    print(
        "PROCESS_PIPE_ORDER_FAIL: process output is read only after waitUntilExit(); "
        "this can deadlock when a pipe fills.",
        file=sys.stderr,
    )
    for path, line, body in hits:
        print(f"\n{path}:{line}", file=sys.stderr)
        print(body, file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
