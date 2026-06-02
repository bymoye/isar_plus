#!/bin/bash
set -e

export IPHONEOS_DEPLOYMENT_TARGET=11.0
export MACOSX_DEPLOYMENT_TARGET=10.13

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

echo "Generating Darwin force-link symbols..."
bash "$SCRIPT_DIR/generate_force_link_symbols.sh"

# Add all required targets
echo "Adding Darwin targets..."
rustup target add \
    aarch64-apple-ios \
    aarch64-apple-ios-sim \
    x86_64-apple-ios \
    aarch64-apple-darwin \
    x86_64-apple-darwin

# iOS device
echo "Building for aarch64-apple-ios..."
cargo build -p isar-plus --target aarch64-apple-ios --features sqlcipher --release

# iOS simulator — create universal binary
echo "Building for aarch64-apple-ios-sim..."
cargo build -p isar-plus --target aarch64-apple-ios-sim --features sqlcipher --release

echo "Building for x86_64-apple-ios..."
cargo build -p isar-plus --target x86_64-apple-ios --features sqlcipher --release

echo "Creating universal iOS simulator binary..."
mkdir -p build/ios-simulator
lipo target/aarch64-apple-ios-sim/release/libisar_plus.a \
     target/x86_64-apple-ios/release/libisar_plus.a \
     -output build/ios-simulator/libisar_plus.a -create

# macOS — create universal static binary
echo "Building for aarch64-apple-darwin..."
cargo build -p isar-plus --target aarch64-apple-darwin --features sqlcipher --release

echo "Building for x86_64-apple-darwin..."
cargo build -p isar-plus --target x86_64-apple-darwin --features sqlcipher --release

echo "Creating universal macOS binary..."
mkdir -p build/macos
lipo target/aarch64-apple-darwin/release/libisar_plus.a \
     target/x86_64-apple-darwin/release/libisar_plus.a \
     -output build/macos/libisar_plus.a -create

# Assemble unified XCFramework
echo "Assembling isar_plus_core.xcframework..."
xcodebuild -create-xcframework \
    -library target/aarch64-apple-ios/release/libisar_plus.a \
    -library build/ios-simulator/libisar_plus.a \
    -library build/macos/libisar_plus.a \
    -output isar_plus_core.xcframework

echo "Creating archive..."
zip -r isar_plus_core.xcframework.zip isar_plus_core.xcframework

echo "Computing checksum..."
shasum -a 256 isar_plus_core.xcframework.zip | awk '{print $1}' > isar_plus_core.xcframework.zip.sha256
echo "Checksum: $(cat isar_plus_core.xcframework.zip.sha256)"
