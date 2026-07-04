#!/bin/bash
# =============================================================================
# Android Translation Layer — AppImage Verification Script
# =============================================================================
# Usage:
#   ./appimage/verify-appimage.sh build/android-translation-layer-*.AppImage
#
# Checks:
#   - File is a valid AppImage
#   - AppDir structure completeness
#   - Desktop file validity
#   - AppStream metadata validity
#   - Critical library presence
#   - Binary linkage sanity
# =============================================================================

set -euo pipefail

APPIMAGE="${1:-}"
if [ -z "$APPIMAGE" ] || [ ! -f "$APPIMAGE" ]; then
    echo "Usage: $0 <path-to-appimage>"
    echo "Example: $0 build/android-translation-layer-*.AppImage"
    exit 1
fi

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

PASS=0
FAIL=0
WARN=0

pass()   { PASS=$((PASS+1)); echo "  ✓ $1"; }
fail()   { FAIL=$((FAIL+1)); echo "  ✗ $1"; }
warn()   { WARN=$((WARN+1)); echo "  ⚠ $1"; }

echo ""
echo "=============================================="
echo "  AppImage Verification"
echo "=============================================="
echo "  File:      $APPIMAGE"
echo "  Size:      $(stat --format=%s "$APPIMAGE" | numfmt --to=iec 2>/dev/null || stat --format=%s "$APPIMAGE")"
echo "=============================================="

# ---- Check file type ----
echo ""
echo "--- Format Check ---"
if file "$APPIMAGE" | grep -qi "appimage\|squashfs\|filesystem"; then
    pass "AppImage format recognized"
else
    fail "Not an AppImage file: $(file "$APPIMAGE")"
fi

# ---- Extract for inspection ----
echo ""
echo "--- Extraction ---"
APPIMAGE_EXTRACT_AND_RUN=1 "$APPIMAGE" --appimage-extract >/dev/null 2>&1 || true

# Try to find the extracted directory
EXTRACT_DIR=""
for candidate in "$TEMP_DIR/squashfs-root" "./squashfs-root"; do
    if [ -d "$candidate" ]; then
        EXTRACT_DIR="$candidate"
        break
    fi
done

# If extraction to cwd happened, relocate it
if [ -d "$(dirname "$APPIMAGE")/squashfs-root" ]; then
    EXTRACT_DIR="$(dirname "$APPIMAGE")/squashfs-root"
fi

if [ -n "$EXTRACT_DIR" ] && [ -d "$EXTRACT_DIR" ]; then
    pass "AppImage extracted successfully"
    # move to temp for safety
    mv "$EXTRACT_DIR" "$TEMP_DIR/squashfs-root" 2>/dev/null || true
    EXTRACT_DIR="$TEMP_DIR/squashfs-root"
else
    fail "Could not extract AppImage"
    echo "  Debug: TEMP_DIR=$TEMP_DIR, ls: $(ls -la "$TEMP_DIR" 2>/dev/null || echo 'empty')"
    echo ""
    echo "=== Results: $PASS passed, $WARN warnings, $FAIL failed ==="
    echo "=============================================="
    exit 1
fi

# ---- Structure checks ----
echo ""
echo "--- AppDir Structure ---"

[ -f "$EXTRACT_DIR/AppRun" ]           && pass "AppRun exists"      || fail "AppRun missing"
[ -f "$EXTRACT_DIR/bin/android-translation-layer" ] && pass "Binary exists" || fail "Binary missing"

# Desktop file
DESKTOP="$EXTRACT_DIR/share/applications/android-translation-layer.desktop"
if [ -f "$DESKTOP" ]; then
    pass "Desktop file exists"
    if command -v desktop-file-validate &>/dev/null; then
        desktop-file-validate "$DESKTOP" && pass "Desktop file valid (desktop-file-validate)" \
            || warn "Desktop file has warnings (see above)"
    fi
else
    fail "Desktop file missing"
fi

# Icons (at least 256x256)
ICON="$EXTRACT_DIR/share/icons/hicolor/256x256/apps/android-translation-layer.png"
[ -f "$ICON" ] && pass "256x256 icon exists (size: $(stat --format=%s "$ICON") bytes)" \
    || fail "256x256 icon missing"

# AppStream metadata
APPDATA="$EXTRACT_DIR/share/metainfo/android-translation-layer.appdata.xml"
if [ -f "$APPDATA" ]; then
    pass "AppStream metadata exists"
    if command -v appstreamcli &>/dev/null; then
        appstreamcli validate "$APPDATA" &>/dev/null && pass "AppStream metadata valid" \
            || warn "AppStream metadata has issues (run appstreamcli validate manually)"
    fi
else
    fail "AppStream metadata missing"
fi

# Version file
[ -f "$EXTRACT_DIR/share/metainfo/version" ] && pass "Version file exists: $(cat "$EXTRACT_DIR/share/metainfo/version")" \
    || warn "Version file missing"

# ---- Library checks ----
echo ""
echo "--- Runtime Libraries ---"

[ -f "$EXTRACT_DIR/lib/art/libart.so" ] && pass "libart.so present" || fail "libart.so missing"
[ -f "$EXTRACT_DIR/lib/libc_bio.so" ]   && pass "libc_bio.so present" || fail "libc_bio.so missing"
[ -f "$EXTRACT_DIR/lib/libdl_bio.so" ]  && pass "libdl_bio.so present" || fail "libdl_bio.so missing"

# Check Java resources
[ -d "$EXTRACT_DIR/lib/java/dex/android_translation_layer" ] && pass "ATL Java dex directory present" \
    || fail "ATL Java dex directory missing"

[ -f "$EXTRACT_DIR/lib/java/dex/android_translation_layer/framework-res.apk" ] && pass "framework-res.apk present" \
    || fail "framework-res.apk missing (runtime will fail)"

[ -f "$EXTRACT_DIR/lib/java/dex/android_translation_layer/api-impl.jar" ] && pass "api-impl.jar present" \
    || fail "api-impl.jar missing"

# ---- Binary linkage ----
echo ""
echo "--- Binary Linkage ---"

LDD_OUTPUT=$(ldd "$EXTRACT_DIR/bin/android-translation-layer" 2>&1 || true)

# Check for "not found" libraries
NOT_FOUND=$(echo "$LDD_OUTPUT" | grep "not found" || true)
if [ -z "$NOT_FOUND" ]; then
    pass "All linked libraries resolved"
else
    echo "$NOT_FOUND" | while IFS= read -r line; do
        warn "Unresolved library: $line"
    done
fi

# Check for stale linker cache references
LINUX_VDSO=$(echo "$LDD_OUTPUT" | grep "linux-vdso" || true)
if echo "$LDD_OUTPUT" | grep -qi "stale\|error\|not found"; then
    warn "Potential linkage issues detected"
fi

# ---- AppImage runtime integration ----
echo ""
echo "--- AppImage Integration ---"

# Check that the binary can at least print help/version
"$EXTRACT_DIR/bin/android-translation-layer" --help 2>&1 | head -5 || true

echo ""
echo "=============================================="
echo "  Verification Complete"
echo "=============================================="
echo "  Passed: $PASS"
echo "  Warnings: $WARN"
echo "  Failed: $FAIL"
echo "=============================================="

if [ "$FAIL" -gt 0 ]; then
    echo "  ❌ Some checks failed — review above."
    exit 1
elif [ "$WARN" -gt 0 ]; then
    echo "  ⚠ All critical checks passed with warnings."
    exit 0
else
    echo "  ✅ All checks passed!"
    exit 0
fi
