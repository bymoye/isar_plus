#!/bin/bash
set -e

if [ "$1" = "x64" ]; then
  rustup target add x86_64-unknown-linux-gnu
  cargo build -p isar-plus --target x86_64-unknown-linux-gnu --features sqlcipher-vendored --release
  cp "target/x86_64-unknown-linux-gnu/release/libisar_plus.so" "libisar_plus_linux_x64.so"
else
  rustup target add aarch64-unknown-linux-gnu
  cargo build -p isar-plus --target aarch64-unknown-linux-gnu --features sqlcipher-vendored --release
  cp "target/aarch64-unknown-linux-gnu/release/libisar_plus.so" "libisar_plus_linux_arm64.so"
fi