#!/bin/bash
set -euo pipefail

# =============================================================================
# Android Translation Layer - AppImage Builder
# =============================================================================
# Creates a portable AppImage of Android Translation Layer.
#
# Usage:
#   ./appimage/build-appimage.sh                    # standalone (build must exist)
#   cmake --build build --target appimage           # via CMake (recommended)
#
# Environment variables (from CMake or manual override):
#   ATL_BUILD_DIR   - path to the CMake build directory (default: build/)
#   ATL_VERSION     - version string (default: git describe or date)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Allow CMake to override build dir, else auto-detect
BUILD_DIR="${ATL_BUILD_DIR:-"$PROJECT_DIR/build"}"
APPDIR="$BUILD_DIR/AppDir"

# ---- Version ----
if [ -n "${ATL_VERSION:-}" ]; then
    VERSION="$ATL_VERSION"
elif command -v git &>/dev/null && git -C "$PROJECT_DIR" rev-parse --git-dir &>/dev/null; then
    VERSION="$(git -C "$PROJECT_DIR" describe --tags --always --dirty 2>/dev/null || true)"
fi
VERSION="${VERSION:-$(date +%Y%m%d)}"
ARCH="${ARCH:-$(uname -m)}"
APPIMAGE_NAME="android-translation-layer-${VERSION}-${ARCH}.AppImage"

echo "=============================================="
echo "  Android Translation Layer AppImage Builder"
echo "=============================================="
echo "  Project:   $PROJECT_DIR"
echo "  Build:     $BUILD_DIR"
echo "  Version:   $VERSION"
echo "  Arch:      $ARCH"
echo "  Output:    $APPIMAGE_NAME"
echo "=============================================="

# ---- Pre-flight checks ----
if [ ! -d "$BUILD_DIR/atl_build" ]; then
    echo "ERROR: Build directory not found at $BUILD_DIR/atl_build"
    echo "Run: cmake -B build && cmake --build build"
    exit 1
fi

if [ ! -f "$BUILD_DIR/atl_build/android-translation-layer" ]; then
    echo "ERROR: Main executable not found at $BUILD_DIR/atl_build/android-translation-layer"
    exit 1
fi

# ---- appimagetool ----
APPIMAGETOOL=""
if command -v appimagetool &>/dev/null; then
    APPIMAGETOOL="appimagetool"
elif [ -x /tmp/appimagetool ]; then
    APPIMAGETOOL="/tmp/appimagetool"
else
    echo "appimagetool not found. Downloading..."
    wget -q "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-${ARCH}.AppImage" -O /tmp/appimagetool
    chmod +x /tmp/appimagetool
    APPIMAGETOOL="/tmp/appimagetool"
fi

# Handle FUSE-less environments (CI, containers, etc.)
if [[ "$APPIMAGETOOL" == *.AppImage ]]; then
    # Test if FUSE works
    if ! "$APPIMAGETOOL" --help &>/dev/null; then
        echo "FUSE not available, using APPIMAGE_EXTRACT_AND_RUN=1"
        export APPIMAGE_EXTRACT_AND_RUN=1
    fi
fi

# ---- Clean and create AppDir ----
echo "Creating AppDir structure..."
rm -rf "$APPDIR"
mkdir -p "$APPDIR"/{bin,lib,share/applications,share/metainfo}
mkdir -p "$APPDIR/share/icons/hicolor/256x256/apps"
mkdir -p "$APPDIR/share/icons/hicolor/128x128/apps"
mkdir -p "$APPDIR/share/icons/hicolor/64x64/apps"
mkdir -p "$APPDIR/share/icons/hicolor/48x48/apps"
mkdir -p "$APPDIR/share/icons/hicolor/32x32/apps"

# ---- Copy main executable ----
cp "$BUILD_DIR/atl_build/android-translation-layer" "$APPDIR/bin/"
echo "  [+] android-translation-layer (binary)"

# ---- Copy project-built libraries ----
echo "Copying libraries..."
copy_count=0

# wolfSSL, libunwind, bionic, ATL libs from build/lib/
if [ -d "$BUILD_DIR/lib" ]; then
    cp -P "$BUILD_DIR"/lib/*.so* "$APPDIR/lib/" 2>/dev/null || true
    copy_count=$((copy_count + $(ls "$APPDIR"/lib/*.so* 2>/dev/null | wc -l)))
fi

# Bionic libs from bionic_build/
if [ -d "$BUILD_DIR/bionic_build" ]; then
    cp -P "$BUILD_DIR"/bionic_build/*.so* "$APPDIR/lib/" 2>/dev/null || true
fi

# ART runtime libraries
if [ -d "$BUILD_DIR/lib/art" ]; then
    mkdir -p "$APPDIR/lib/art"
    cp -P "$BUILD_DIR/lib/art/"*.so* "$APPDIR/lib/art/" 2>/dev/null || true
fi

# Create proper symlinks for versioned .so files
cd "$APPDIR/lib"
for lib in *.so.*; do
    [ -f "$lib" ] || continue
    base="${lib%%.*}"   # libfoo from libfoo.so.1.0.0
    soname="${lib%.*}"  # libfoo.so.1 from libfoo.so.1.0.0
    [ ! -e "$soname" ] && ln -sf "$lib" "$soname" 2>/dev/null || true
    [ ! -e "$base" ]   && ln -sf "$lib" "$base"   2>/dev/null || true
done
cd "$PROJECT_DIR"
echo "  [+] Libraries: $copy_count .so files copied"

# ---- Copy Java resources ----
echo "Copying Java resources..."
if [ -d "$BUILD_DIR/lib/java/dex" ]; then
    mkdir -p "$APPDIR/lib/java/dex"
    cp -r "$BUILD_DIR/lib/java/dex/android_translation_layer" "$APPDIR/lib/java/dex/" 2>/dev/null || true
    cp -r "$BUILD_DIR/lib/java/dex/art" "$APPDIR/lib/java/dex/" 2>/dev/null || true
    cp "$BUILD_DIR"/lib/java/*.jar "$APPDIR/lib/java/dex/" 2>/dev/null || true
    echo "  [+] Java resources copied"
fi

# ---- Copy binary tools ----
if [ -f "$BUILD_DIR/bin/dx" ]; then
    cp "$BUILD_DIR/bin/dx" "$APPDIR/bin/"
    echo "  [+] dx (dex tool)"
fi
if [ -f "$BUILD_DIR/bin/dex2oat" ]; then
    cp "$BUILD_DIR/bin/dex2oat" "$APPDIR/bin/"
    echo "  [+] dex2oat"
fi

# ---- Copy ATL resources ----
# NOTE: framework-res.apk MUST go to lib/java/dex/android_translation_layer/
# because main.c uses dladdr(JNI_CreateJavaVM) to find libart.so, then
# derives the path: {libart_dir}/../java/dex/android_translation_layer/
if [ -f "$BUILD_DIR/atl_build/framework-res.apk" ]; then
    mkdir -p "$APPDIR/lib/java/dex/android_translation_layer"
    cp "$BUILD_DIR/atl_build/framework-res.apk" "$APPDIR/lib/java/dex/android_translation_layer/"
    echo "  [+] framework-res.apk"
fi

if [ -f "$PROJECT_DIR/res/fonts.xml" ]; then
    mkdir -p "$APPDIR/share/atl"
    cp "$PROJECT_DIR/res/fonts.xml" "$APPDIR/share/atl/"
    echo "  [+] fonts.xml"
fi

# ---- Copy icons (pre-rendered PNG) ----
echo "Copying icons..."
for size in 256 128 64 48 32; do
    src="$PROJECT_DIR/res/icons/${size}x${size}/apps/android-translation-layer.png"
    if [ -f "$src" ]; then
        cp "$src" "$APPDIR/share/icons/hicolor/${size}x${size}/apps/"
    fi
done
echo "  [+] Icons copied"

# Fallback: try to convert SVG if pre-rendered icons missing
if [ ! -f "$APPDIR/share/icons/hicolor/256x256/apps/android-translation-layer.png" ]; then
    if [ -f "$PROJECT_DIR/doc/logo.svg" ]; then
        echo "  [!] Pre-rendered icons not found, converting SVG..."
        if command -v rsvg-convert &>/dev/null; then
            rsvg-convert -w 256 -h 256 "$PROJECT_DIR/doc/logo.svg" \
                -o "$APPDIR/share/icons/hicolor/256x256/apps/android-translation-layer.png"
        elif command -v inkscape &>/dev/null; then
            inkscape -w 256 -h 256 "$PROJECT_DIR/doc/logo.svg" \
                -o "$APPDIR/share/icons/hicolor/256x256/apps/android-translation-layer.png"
        elif command -v convert &>/dev/null; then
            convert -background none -resize 256x256 "$PROJECT_DIR/doc/logo.svg" \
                "$APPDIR/share/icons/hicolor/256x256/apps/android-translation-layer.png"
        fi
    fi
fi

# Last-resort fallback — 1×1 transparent pixel
if [ ! -f "$APPDIR/share/icons/hicolor/256x256/apps/android-translation-layer.png" ]; then
    echo "  [!] WARNING: No icon found. Using placeholder."
    echo -n "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==" \
        | base64 -d > "$APPDIR/share/icons/hicolor/256x256/apps/android-translation-layer.png"
fi

# ---- Desktop file ----
cat > "$APPDIR/share/applications/android-translation-layer.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Android Translation Layer
Comment=Run Android applications on Linux
Exec=android-translation-layer %f
Icon=android-translation-layer
Terminal=false
Categories=Utility;Development;
MimeType=application/vnd.android.package-archive;
Keywords=android;apk;mobile;emulator;
StartupNotify=true
EOF
echo "  [+] .desktop file"

# ---- AppStream metadata ----
cat > "$APPDIR/share/metainfo/android-translation-layer.appdata.xml" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>android-translation-layer</id>
  <metadata_license>MIT</metadata_license>
  <project_license>GPL-3.0-or-later</project_license>
  <name>Android Translation Layer</name>
  <summary>Run Android applications on Linux</summary>
  <description>
    <p>
      A translation layer that allows running Android applications directly
      on a Linux system. It provides implementations of Android framework
      APIs using native Linux libraries like GTK4, Wayland, and Vulkan.
    </p>
    <p>
      ATL replaces the Android stack from core libraries through the
      application framework with native Linux equivalents, allowing APK
      files to run without an emulator or container.
    </p>
  </description>
  <url type="homepage">https://gitlab.com/android_translation_layer/android_translation_layer</url>
  <provides>
    <binary>android-translation-layer</binary>
  </provides>
  <content_rating type="oars-1.1"/>
  <releases>
    <release version="${VERSION}" date="$(date +%Y-%m-%d)"/>
  </releases>
</component>
EOF
echo "  [+] AppStream metadata"

# ---- Version file ----
echo -n "$VERSION" > "$APPDIR/share/metainfo/version"

# ---- AppRun ----
cat > "$APPDIR/AppRun" << 'APPRUNEOF'
#!/bin/bash
set -euo pipefail

SELF=$(readlink -f "$0")
APPDIR=${SELF%/*}

export LD_LIBRARY_PATH="$APPDIR/lib:$APPDIR/lib/art:${LD_LIBRARY_PATH:-}"
export XDG_DATA_DIRS="$APPDIR/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export ANDROID_APP_DATA_DIR="${ANDROID_APP_DATA_DIR:-$HOME/.local/share/android_translation_layer}"

# Let the app know it's running from an AppImage
export ATL_APPIMAGE=1
export ATL_APPIMAGE_PATH="$APPDIR"

# Create data directory if needed
mkdir -p "$ANDROID_APP_DATA_DIR"

exec "$APPDIR/bin/android-translation-layer" --sdk-int=28 "$@"
APPRUNEOF
chmod +x "$APPDIR/AppRun"
echo "  [+] AppRun"

# ---- Strip debug symbols (optional, reduces size) ----
if [ -x "$APPDIR/bin/android-translation-layer" ]; then
    # Only strip if not a debug build
    if ! file "$APPDIR/bin/android-translation-layer" | grep -q "not stripped"; then
        echo "  [~] Binary already stripped"
    else
        strip "$APPDIR/bin/android-translation-layer" 2>/dev/null && echo "  [+] Stripped debug symbols" || true
    fi
fi

# ---- Build AppImage ----
echo ""
echo "Building AppImage..."
cd "$BUILD_DIR"

APPIMAGETOOL_ARGS=(
    "--comp" "zstd"
    "--comp-level" "22"
)

# Add update information for GitHub Releases (used by CI)
if [ -n "${GITHUB_REPOSITORY:-}" ]; then
    APPIMAGETOOL_ARGS+=(
        "-u" "gh-releases-zsync|${GITHUB_REPOSITORY}|latest|*.AppImage.zsync"
    )
fi

# shellcheck disable=SC2086
"$APPIMAGETOOL" "${APPIMAGETOOL_ARGS[@]}" "$APPDIR" "$APPIMAGE_NAME"

echo ""
echo "=============================================="
echo "  Build Complete!"
echo "=============================================="
echo "  AppImage: $BUILD_DIR/$APPIMAGE_NAME"
echo "  Size:     $(numfmt --to=iec "$(stat --format=%s "$BUILD_DIR/$APPIMAGE_NAME")" 2>/dev/null || stat --format=%s "$BUILD_DIR/$APPIMAGE_NAME")"
echo ""
echo "  To run:"
echo "    $BUILD_DIR/$APPIMAGE_NAME /path/to/app.apk"
echo ""
echo "  To install system-wide:"
echo "    sudo cp $BUILD_DIR/$APPIMAGE_NAME /usr/local/bin/"
echo "=============================================="
