#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUST_DIR="$ROOT"

DESTDIR="${DESTDIR:-$ROOT/../iOS}"
PREFIX="${PREFIX:-/var/jb/usr}"
IOS_MIN="${IOS_MIN:-17.0}"
BUILD_CARGO="${BUILD_CARGO:-1}"
LOG="${LOG:-$ROOT/../build-rust-ios.log}"

CONFIG="$RUST_DIR/bootstrap.ios-arm64.toml"

if [[ ! -d "$RUST_DIR/.git" ]]; then
  echo "Error: This script must be inside the Rust source directory."
  exit 1
fi

for cmd in xcrun cmake ninja python3 git; do
  command -v "$cmd" >/dev/null || { echo "Missing required tool: $cmd"; exit 1; }
done

SDKROOT_IOS="$(xcrun --sdk iphoneos --show-sdk-path)"
CC_IOS="$(xcrun --sdk iphoneos -f clang)"
CXX_IOS="$(xcrun --sdk iphoneos -f clang++)"
AR_IOS="$(xcrun --sdk iphoneos -f ar)"
RANLIB_IOS="$(xcrun --sdk iphoneos -f ranlib)"

mkdir -p "$DESTDIR"
if [[ ! -f "$CONFIG" ]]; then
  echo "Missing config file: $CONFIG"
  exit 1
fi

cd "$RUST_DIR"

unset SDKROOT || true

export DESTDIR
export IPHONEOS_DEPLOYMENT_TARGET="$IOS_MIN"
export CC_aarch64_apple_ios="$CC_IOS"
export CXX_aarch64_apple_ios="$CXX_IOS"
export AR_aarch64_apple_ios="$AR_IOS"
export RANLIB_aarch64_apple_ios="$RANLIB_IOS"
export CARGO_TARGET_AARCH64_APPLE_IOS_LINKER="$CC_IOS"
export CFLAGS_aarch64_apple_ios="-isysroot $SDKROOT_IOS -arch arm64 -miphoneos-version-min=$IOS_MIN -g0"
export CXXFLAGS_aarch64_apple_ios="-isysroot $SDKROOT_IOS -arch arm64 -miphoneos-version-min=$IOS_MIN -g0"
export LDFLAGS_aarch64_apple_ios="-isysroot $SDKROOT_IOS -arch arm64 -miphoneos-version-min=$IOS_MIN"
export RUSTFLAGS="-Cdebuginfo=0 -Cstrip=symbols"

stage1_components=(compiler/rustc)
install_components=(compiler/rustc library/std)
if [[ "$BUILD_CARGO" == "1" ]]; then
  stage1_components+=(src/tools/cargo)
  install_components+=(cargo)
fi

echo "[start] building rust for iOS host (aarch64-apple-ios)" | tee "$LOG"
echo "DESTDIR=$DESTDIR | PREFIX=$PREFIX | BUILD_CARGO=$BUILD_CARGO" | tee -a "$LOG"

echo "[step1] build stage1 host compiler (x86_64-apple-darwin)" | tee -a "$LOG"
stdbuf -oL -eL ./x.py --config "$CONFIG" build --stage 1 \
  --host x86_64-apple-darwin --target x86_64-apple-darwin \
  "${stage1_components[@]}" 2>&1 | tee -a "$LOG"

echo "[step2] install iOS host toolchain (aarch64-apple-ios, stage2)" | tee -a "$LOG"
stdbuf -oL -eL ./x.py --config "$CONFIG" install -i --stage 2 \
  --host aarch64-apple-ios --target aarch64-apple-ios \
  "${install_components[@]}" 2>&1 | tee -a "$LOG"

echo "Done. Staged install root: $DESTDIR$PREFIX"