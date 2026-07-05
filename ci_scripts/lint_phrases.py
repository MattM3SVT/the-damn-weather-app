#!/usr/bin/env python3
"""Lint phrases-clean.json / phrases-explicit.json.

Run manually or from CI (ci_post_clone.sh). Two classes of findings:

  ERRORS (exit 1) — schema problems the app would mis-handle:
    * missing/invalid keys, unknown condition tags, bad tempRange,
      dayOnly+nightOnly conflicts, unknown timeBuckets, duplicate texts,
      malformed [temp] tokens, phrases with day-language tagged nightOnly
      (and vice versa).

  WARNINGS (exit 0) — heuristic hints worth a human look:
    * day-implying language without dayOnly, night-implying language
      without nightOnly. These are often fine (a daytime phrase can say
      "tonight"), so they never fail the build.
"""

import json
import re
import sys
from collections import Counter
from pathlib import Path

VALID_CONDITIONS = {
    "clear", "partly-cloudy", "cloudy", "fog", "drizzle", "rain",
    "heavy-rain", "freezing-rain", "snow", "heavy-snow", "thunderstorm",
    "wind", "any",
}
VALID_TIME_BUCKETS = {"morning", "afternoon", "evening", "lateNight"}

DAY_HINTS = [
    r"\bsunn?y\b", r"\bsunshine\b", r"\bsunburn", r"\bsunscreen",
    r"\bsunglasses", r"\bUV\b", r"\bblue sky", r"\bdaylight\b",
    r"\bthis morning\b", r"\bgood morning\b", r"\bsun is out\b",
    r"\bsun's out\b", r"\bmidday\b", r"\bnoon\b", r"\btan lines?\b",
    r"\bvitamin d\b",
]
NIGHT_HINTS = [
    r"\bmoonlight", r"\bstargazing", r"\bbedtime\b", r"\bpajamas\b",
    r"\bmidnight\b", r"\bnightcap\b", r"\bafter dark\b", r"\bdark out\b",
    r"\bgo to sleep\b", r"\bgo to bed\b", r"\binsomnia\b", r"\bnight sky\b",
]


def lint(path: Path) -> tuple[int, int]:
    errors, warnings = [], []
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as e:
        print(f"ERROR [{path.name}]: cannot parse: {e}")
        return 1, 0

    texts = Counter(p.get("text", "") for p in data)
    for text, count in texts.items():
        if count > 1:
            errors.append(f"duplicate text x{count}: {text[:70]}")

    for p in data:
        text = p.get("text")
        label = (text or "<missing text>")[:70]

        if not isinstance(text, str) or not text.strip():
            errors.append("phrase with missing/empty text")
            continue
        if not isinstance(p.get("conditions"), list) or not p["conditions"]:
            errors.append(f"missing conditions: {label}")
            continue
        for c in p["conditions"]:
            if c not in VALID_CONDITIONS:
                errors.append(f"unknown condition '{c}': {label}")
        tr = p.get("tempRange")
        if tr is not None and (
            not isinstance(tr, list) or len(tr) != 2
            or not all(isinstance(x, (int, float)) for x in tr) or tr[0] > tr[1]
        ):
            errors.append(f"bad tempRange {tr}: {label}")
        if p.get("priority") not in (1, 2):
            errors.append(f"priority must be 1 or 2: {label}")
        if p.get("dayOnly") and p.get("nightOnly"):
            errors.append(f"dayOnly AND nightOnly (never matches): {label}")
        for b in p.get("timeBuckets") or []:
            if b not in VALID_TIME_BUCKETS:
                errors.append(f"unknown timeBucket '{b}': {label}")
        for d in p.get("dates") or []:
            m = re.fullmatch(r"(\d{2})-(\d{2})", str(d))
            if not m or not (1 <= int(m.group(1)) <= 12) or not (1 <= int(m.group(2)) <= 31):
                errors.append(f"bad date '{d}' (want MM-dd): {label}")
        # "[temp" without the closing bracket renders literally in the UI.
        if "[temp" in text and "[temp]" not in text:
            errors.append(f"malformed [temp] token: {label}")

        lower = text.lower()
        day_hit = next((h for h in DAY_HINTS if re.search(h, lower)), None)
        night_hit = next((h for h in NIGHT_HINTS if re.search(h, lower)), None)
        if day_hit and p.get("nightOnly"):
            errors.append(f"nightOnly but day-language ({day_hit}): {label}")
        elif day_hit and not p.get("dayOnly"):
            warnings.append(f"day-language ({day_hit}) but not dayOnly: {label}")
        if night_hit and p.get("dayOnly"):
            errors.append(f"dayOnly but night-language ({night_hit}): {label}")
        elif night_hit and not p.get("nightOnly"):
            warnings.append(f"night-language ({night_hit}) but not nightOnly: {label}")

    for e in errors:
        print(f"ERROR [{path.name}]: {e}")
    for w in warnings:
        print(f"warning [{path.name}]: {w}")
    print(f"{path.name}: {len(data)} phrases, {len(errors)} errors, {len(warnings)} warnings")
    return len(errors), len(warnings)


def main() -> int:
    resources = Path(__file__).resolve().parent.parent / (
        "WeatherShared/Sources/WeatherShared/Resources"
    )
    total_errors = 0
    for name in ("phrases-clean.json", "phrases-explicit.json"):
        e, _ = lint(resources / name)
        total_errors += e
    return 1 if total_errors else 0


if __name__ == "__main__":
    sys.exit(main())
