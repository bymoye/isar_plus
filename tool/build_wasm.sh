#!/bin/bash
set -euo pipefail

rustup target add wasm32-unknown-unknown

cargo build \
       --target wasm32-unknown-unknown \
       --no-default-features \
       --features sqlite \
       -p isar-plus \
       --release

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WASM_TARGET="${ROOT_DIR}/target/wasm32-unknown-unknown/release/isar_plus.wasm"

wasm-bindgen \
       "${WASM_TARGET}" \
       --out-dir "${ROOT_DIR}" \
       --out-name isar_plus \
       --target no-modules \
       --no-typescript

# The wasm-bindgen output will be isar_plus_bg.wasm, rename to isar_plus.wasm
mv "${ROOT_DIR}/isar_plus_bg.wasm" "${ROOT_DIR}/isar_plus.wasm"

sed -i.bak '1s/let wasm_bindgen/window.wasm_bindgen/' "${ROOT_DIR}/isar_plus.js"
rm -f "${ROOT_DIR}/isar_plus.js.bak"

# Optimize the WASM file with required feature flags
if command -v wasm-opt &> /dev/null; then
    wasm-opt -O3 \
        --enable-bulk-memory \
        --enable-nontrapping-float-to-int \
        "${ROOT_DIR}/isar_plus.wasm" \
    -o "${ROOT_DIR}/isar_plus.wasm"
fi