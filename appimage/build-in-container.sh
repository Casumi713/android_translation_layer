#!/bin/bash
# =============================================================================
# Android Translation Layer - Container-based AppImage Builder
# =============================================================================
# Uses Podman to build ATL and its AppImage inside an Ubuntu 24.04 container,
# avoiding host distribution/compiler/Java compatibility issues.
#
# Prerequisites: podman
#
# Usage:
#   ./appimage/build-in-container.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=============================================="
echo "  ATL AppImage Builder (containerized)"
echo "=============================================="
echo "  Source: $PROJECT_DIR"
echo "=============================================="

# Build the container image with all build dependencies
CONTAINER_TAG="atl-builder:latest"

if ! podman image exists "$CONTAINER_TAG"; then
    echo "Building container image (this may take a few minutes)..."
    cat > "/tmp/Containerfile.atl" << 'CONTAINEREOF'
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Install all build dependencies needed for ATL
RUN apt-get update -qq && apt-get install -y -qq \
    autoconf \
    build-essential \
    cmake \
    libavcodec-dev \
    libasound2-dev \
    libbsd-dev \
    libcap-dev \
    libdrm-dev \
    libelf-dev \
    libfontconfig-dev \
    libglib2.0-dev \
    libgtk-4-dev \
    libgudev-1.0-dev \
    libopenxr-dev \
    libportal-dev \
    libsqlite3-dev \
    libswscale-dev \
    libtool \
    libunwind-dev \
    libvulkan-dev \
    libwayland-dev \
    libwebkitgtk-6.0-dev \
    meson \
    ninja-build \
    openjdk-21-jdk-headless \
    pkg-config \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Clone the old AOSP build system needed by art_standalone
RUN git config --global advice.detachedHead false
CONTAINEREOF

    podman build -t "$CONTAINER_TAG" -f "/tmp/Containerfile.atl"
    rm "/tmp/Containerfile.atl"
fi

# Build the project inside the container
echo ""
echo "Building ATL inside Ubuntu 24.04 container..."
echo ""

podman run --rm -i \
    --name atl-builder \
    -v "$PROJECT_DIR:/src:Z" \
    -w /src \
    "$CONTAINER_TAG" \
    bash << 'BUILDEOF'
set -euo pipefail
echo "=== Step 1: Get AOSP build system for art_standalone ==="
cd /src/thirdparty/art_standalone
if [ ! -d "build" ] || [ ! -f "build/core/main.mk" ]; then
    rm -rf build
    git clone --depth 1 https://github.com/aosp-mirror/platform_build.git build
fi

echo "=== Step 2: CMake configure ==="
cd /src
cmake -B build -DCMAKE_BUILD_TYPE=Release

echo "=== Step 3: Build all ==="
cmake --build build -j$(nproc)

echo "=== Step 4: Build AppImage ==="
cmake --build build --target appimage

echo "=== Step 5: Verify ==="
if [ -f /src/appimage/verify-appimage.sh ]; then
    bash /src/appimage/verify-appimage.sh /src/build/android-translation-layer-*.AppImage || true
fi
BUILDEOF

echo ""
echo "=============================================="
echo "  Build Complete!"
echo "=============================================="
ls -lh "$PROJECT_DIR"/build/android-translation-layer-*.AppImage 2>/dev/null || echo "Check build/ for output"
echo "=============================================="
