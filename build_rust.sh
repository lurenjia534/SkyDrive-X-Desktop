#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[build_rust] Building Rust crate (release)..."
cargo build --manifest-path "$ROOT_DIR/rust/Cargo.toml" --release

echo "[build_rust] Regenerating flutter_rust_bridge bindings..."
flutter_rust_bridge_codegen generate

echo "[build_rust] Done."
