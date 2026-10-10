#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app="${1:-$project_dir/.build/Open Focus Island.app}"
info="$app/Contents/Info.plist"
executable="$app/Contents/MacOS/OpenFocusIsland"
icon="$app/Contents/Resources/AppIcon.icns"
errors=0

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    errors=$((errors + 1))
}

expect_plist() {
    local key="$1" expected="$2" actual
    if ! actual="$(/usr/libexec/PlistBuddy -c "Print :$key" "$info" 2>/dev/null)"; then
        fail "Info.plist is missing $key"
    elif [[ "$actual" != "$expected" ]]; then
        fail "$key is '$actual', expected '$expected'"
    fi
}

if [[ ! -d "$app/Contents" ]]; then
    fail "bundle contents are missing: $app/Contents"
else
    [[ -x "$executable" ]] || fail "bundle executable is missing or not executable"
    [[ -f "$info" ]] || fail "Info.plist is missing"
fi

if [[ -f "$info" ]]; then
    expect_plist CFBundleIdentifier org.openfocusisland.app
    expect_plist CFBundlePackageType APPL
    expect_plist CFBundleIconFile AppIcon
    expect_plist CFBundleShortVersionString 0.1.0
    expect_plist CFBundleVersion 1
    expect_plist LSUIElement true
fi

if [[ ! -s "$icon" ]]; then
    fail "bundle icon is missing or empty: $icon"
elif iconset_dir="$(mktemp -d)"; then
    if ! iconutil --convert iconset "$icon" --output "$iconset_dir/AppIcon.iconset" >/dev/null 2>&1; then
        fail "bundle icon is not a valid ICNS file"
    fi
    rm -rf "$iconset_dir"
fi

if [[ -d "$app/Contents" ]]; then
    if ! codesign --verify --strict --deep "$app" >/dev/null 2>&1; then
        fail "bundle signature verification failed"
    fi
    signature_info="$(codesign -dv --verbose=1 "$app" 2>&1 || true)"
    [[ "$signature_info" == *"Signature=adhoc"* ]] || fail "bundle is not signed with a local ad-hoc signature"
fi

# Audit the bundle's own sounds (manifest, hashes, policy, full decode); no fallback to Assets/Sounds.
if ! swift "$project_dir/scripts/check-sounds.swift" "$app/Contents/Resources/Sounds"; then
    fail "bundle sound audit failed: $app/Contents/Resources/Sounds"
fi

if (( errors > 0 )); then
    printf 'Bundle check failed with %d issue(s).\n' "$errors" >&2
    exit 1
fi

printf 'Bundle check passed: %s\n' "$app"
