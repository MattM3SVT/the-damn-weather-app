#!/bin/sh
set -e

# Xcode Cloud post-clone script
# Runs after the repository is cloned, before dependency resolution.

echo "=== ci_post_clone.sh ==="
echo "Build number: $CI_BUILD_NUMBER"
echo "Workflow: $CI_WORKFLOW"
echo "Branch: $CI_BRANCH"

# Resolve the repo root from the script's own location rather than relying
# on $CI_WORKSPACE (which has been observed as empty in some Xcode Cloud
# environments on macOS Tahoe).
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "Repo root: $REPO_ROOT"

# Inject the AirNow API key into AirNowSecrets.swift before the build starts.
# The committed source file has `hardcodedKey: String? = nil` so the key
# never lives in git. It's stored as a secret Xcode Cloud environment variable
# (AIRNOW_API_KEY) and substituted in here.
#
# If the env var isn't set we WARN rather than fail so CI workflows that don't
# need air quality (e.g. a validation-only build) still succeed — the resulting
# binary just silently hides the Air Quality feature.
SECRETS_FILE="$REPO_ROOT/WeatherShared/Sources/WeatherShared/AirNowSecrets.swift"
if [ -n "$AIRNOW_API_KEY" ]; then
    if [ ! -f "$SECRETS_FILE" ]; then
        echo "ERROR: expected $SECRETS_FILE not found"
        exit 1
    fi
    # Using | as sed delimiter so we don't have to escape forward slashes.
    # The value is a UUID (no sed-special chars) so no further escaping needed.
    sed -i '' "s|hardcodedKey: String? = nil|hardcodedKey: String? = \"$AIRNOW_API_KEY\"|" "$SECRETS_FILE"
    # Verify the exact env-var value landed. A grep for any quoted string
    # would false-pass if a key were accidentally committed in the source,
    # masking a sed no-op and shipping the stale committed key.
    if grep -qF "hardcodedKey: String? = \"$AIRNOW_API_KEY\"" "$SECRETS_FILE"; then
        echo "AirNow API key injected into AirNowSecrets.swift"
    else
        echo "ERROR: AirNow API key injection failed (sed pattern did not match)"
        exit 1
    fi
else
    echo "WARNING: AIRNOW_API_KEY not set. Air Quality will be disabled in this build."
fi

# Fail the build on phrase-data schema errors (duplicate texts, unknown
# tags, contradictory day/night flags, malformed [temp] tokens). Heuristic
# day/night hints print as warnings only.
if command -v python3 >/dev/null 2>&1; then
    python3 "$REPO_ROOT/ci_scripts/lint_phrases.py"
else
    echo "WARNING: python3 not found; skipping phrase lint."
fi

echo "Post-clone script completed successfully."
