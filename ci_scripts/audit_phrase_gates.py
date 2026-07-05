#!/usr/bin/env python3
"""MANUAL TOOL (not run in CI — heuristics need human review of results).

Deep phrase-gate audit: condition-language vs tags, temp-language vs
tempRange, 'any'-tag leakage, condition/temp coherence. Negation-aware."""

import json
import re
import sys
from pathlib import Path

ROOT = Path("/Users/matthewcosensci/Documents/dev/The Damn Weather")
RES = ROOT / "WeatherShared/Sources/WeatherShared/Resources"

# Words that suggest the phrase is ABOUT a condition. (regex, family)
CONDITION_WORDS = [
    (r"\brain(?:ing|s|ed|y|storm)?\b", "rain"),
    (r"\bdownpour", "rain"),
    (r"\bdrizzl", "rain"),
    (r"\bshowers?\b", "rain"),
    (r"\bpuddles?\b", "rain"),
    (r"\bumbrella", "rain"),
    (r"\b(?:soaked|drenched|sopping)\b", "rain"),
    (r"\bsnow(?:ing|s|ed|y|fall|flake|man|ball)?\b", "snow"),
    (r"\bblizzard", "snow"),
    (r"\bflurr(?:y|ies)", "snow"),
    (r"\bsleet", "winter-mix"),
    (r"\b(?:thunder|lightning)\b", "storm"),
    (r"\bhail(?:ing|stones)?\b", "storm"),
    (r"\bfog(?:gy|ged)?\b", "fog"),
    (r"\bwind(?:y|s|ier|iest)?\b", "wind"),
    (r"\bgust(?:s|y|ing)?\b", "wind"),
    (r"\bbreez[ey]\b", "wind"),
    (r"\bsunn?(?:y|ier|iest)\b", "sun"),
    (r"\bsunshine\b", "sun"),
    (r"\bsunburn|\bsunscreen|\bsunglasses", "sun"),
    (r"\bblue sk(?:y|ies)\b", "sun"),
    (r"\bcloudless\b", "sun"),
    (r"\bclear sk(?:y|ies)\b", "sun"),
    (r"\b(?:cloudy|overcast)\b", "clouds"),
    (r"\bgray sk(?:y|ies)?\b", "clouds"),
    (r"\bfreezing rain\b", "winter-mix"),
    (r"\bblack ice\b", "winter-mix"),
]

# Which tags legitimately cover each language family.
FAMILY_TAGS = {
    "rain":       {"rain", "heavy-rain", "drizzle", "thunderstorm", "freezing-rain"},
    "snow":       {"snow", "heavy-snow", "freezing-rain"},
    "winter-mix": {"freezing-rain", "snow", "heavy-snow"},
    "storm":      {"thunderstorm"},
    "fog":        {"fog"},
    "wind":       {"wind", "thunderstorm"},
    "sun":        {"clear", "partly-cloudy"},
    "clouds":     {"cloudy", "partly-cloudy", "fog"},
}

HOT_WORDS = r"\b(?:sweat(?:ing|y)?|scorch|blazing|boiling|swelter|heatstroke|melting|roast(?:ing)?|furnace|sauna|hot as)\b|\bAC\b|air condition"
COLD_WORDS = r"\b(?:freez(?:e|ing)|frozen|frostbite|frigid|icicles?|bundle up|parkas?|mittens?|gloves|shiver(?:ing)?|hypothermia|cold as|numb|wind ?chill)\b"

# Negation/absence markers within a window before the matched word, plus a
# few whole-phrase constructions.
NEGATION_BEFORE = re.compile(
    r"(?:\bnot?\b|\bno\b|\bwithout\b|\bzero\b|\bstopped\b|\bquit\b|\bdone\b|\bisn't\b|\bwasn't\b|\bain't\b|"
    r"\binstead of\b|\brather than\b|\bmissing\b|\bwhere(?:'s| is| did)\b|\bforgot\b|\bgave up\b|\bcancell?ed\b|"
    r"\bno sign of\b|\bwaiting for\b|\bwish(?:ing)? (?:it|for)\b|\bpretend(?:ing)?\b|\bhiding\b|\bbehind\b|"
    r"\btook (?:the day|a day)\b|\bno-show\b|\bskipped\b|\bcalled in\b|\bghost(?:ed|ing)?\b|\bbailed\b|"
    r"\babsent\b|\blost\b|\bbroke up\b|\bleft\b|\bgone\b|\bwent\b|\bblock(?:ed|ing)\b|\bswallow(?:ed)?\b|"
    r"\bate\b|\bstole\b|\bkidnapped\b|\bdevoured\b|\berased\b|\bdeleted\b|\bhid\b|\bmisses?\b|\bremember\b|"
    r"\bused to\b|\bsomewhere\b|\bif\b|\buntil\b|\bbefore\b|\bafter the\b|\bpost-\b|\btomorrow\b|\blater\b|"
    r"\bsoon\b|\bthreatening\b|\babout to\b|\btrying to\b|\bwants? to\b|\bconsidering\b|\bdebating\b)",
    re.IGNORECASE,
)

def negated(text_lower: str, match: re.Match) -> bool:
    window = text_lower[max(0, match.start() - 45):match.start()]
    if NEGATION_BEFORE.search(window):
        return True
    after = text_lower[match.end():match.end() + 30]
    if re.search(r"^\S*\s+(?:stopped|quit|is (?:gone|over|done)|gave up|left|ended|'s (?:gone|over|done))", after):
        return True
    return False

def audit(path: Path):
    data = json.loads(path.read_text())
    findings = {"any_leak": [], "cond_mismatch": [], "hot": [], "cold": [], "snow_temp": [], "hardnum": []}

    for i, p in enumerate(data):
        text = p["text"]
        low = text.lower()
        tags = set(p["conditions"])
        tr = p.get("tempRange")

        # 1 + 2: condition language vs tags
        for pattern, family in CONDITION_WORDS:
            for m in re.finditer(pattern, low):
                if negated(low, m):
                    continue
                ok_tags = FAMILY_TAGS[family]
                if "any" in tags:
                    findings["any_leak"].append((i, family, m.group(0), p))
                elif not (tags & ok_tags):
                    findings["cond_mismatch"].append((i, family, m.group(0), p))
                break  # one finding per family per phrase

        # 3: hot language should be bounded to warm temps
        m = re.search(HOT_WORDS, low)
        if m and not negated(low, m):
            if tr is None or tr[0] < 60:
                if not tags & {"snow", "heavy-snow", "freezing-rain"}:  # eyeball separately
                    findings["hot"].append((i, m.group(0), p))
                else:
                    findings["cond_mismatch"].append((i, "hot-in-winter", m.group(0), p))

        # 4: cold language should be bounded to cold temps (unless tagged wintry)
        m = re.search(COLD_WORDS, low)
        if m and not negated(low, m):
            wintry = bool(tags & {"snow", "heavy-snow", "freezing-rain"})
            if not wintry and (tr is None or tr[1] > 55):
                findings["cold"].append((i, m.group(0), p))

        # 5: wintry tags with warm temp ranges
        if tags & {"snow", "heavy-snow", "freezing-rain"} and tr and tr[0] >= 45:
            findings["snow_temp"].append((i, "wintry-tag-warm-range", p))

        # 6: hardcoded temperature numbers that contradict the range
        for m in re.finditer(r"\b(\d{1,3}) degrees\b", low):
            n = int(m.group(1))
            if "[temp]" in low[:m.start()]:
                continue
            if tr and not (tr[0] - 5 <= n <= tr[1] + 5):
                findings["hardnum"].append((i, n, p))
            elif tr is None and (n <= 45 or n >= 80):
                findings["hardnum"].append((i, n, p))

    return findings

for name in ["phrases-clean.json", "phrases-explicit.json"]:
    f = audit(RES / name)
    print(f"\n######## {name} ########")
    for cat, items in f.items():
        print(f"\n=== {cat}: {len(items)} ===")
        for item in items:
            p = item[-1]
            meta = f"tags={p['conditions']} range={p.get('tempRange')} day={p['dayOnly']} night={p['nightOnly']}"
            detail = " ".join(str(x) for x in item[:-1])
            print(f"  [{detail}] {meta}\n      {p['text'][:110]}")
