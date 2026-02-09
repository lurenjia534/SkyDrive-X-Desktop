# Skydrivex

Skydrivex is a Linux-first third-party OneDrive desktop client that also supports macOS and Windows. The goal is to deliver a native desktop experience while staying fully compatible with the official OneDrive service.

Chinese README: [zh_README.md](zh_README.md)

## Tech Stack and Structure
- Flutter + Riverpod for UI, entry at `lib/main.dart`, feature modules in `lib/features/`.
- Rust handles core sync and OneDrive integration logic, source code in `rust/`.
- Flutter and Rust communicate via `flutter_rust_bridge` 2.11.1, configured in `flutter_rust_bridge.yaml`.
- The build script `./build_rust.sh` compiles the Rust crate and regenerates bridge code.

## Requirements
- Flutter SDK and Dart (aligned with the channel and version in `pubspec.yaml`).
- Rust stable toolchain and `cargo`.
- `flutter_rust_bridge_codegen` 2.11.1 installed (for binding generation).

## Quick Start
1) Fetch dependencies:
   ```bash
   flutter pub get
   ```
2) Build Rust and generate bridge code:
   ```bash
   ./build_rust.sh
   ```
   Re-run this script after changing Rust APIs.
3) Run the app (Linux first):
   ```bash
   flutter run -d linux
   ```
   The macOS and Windows scaffolds must stay buildable, but full support is still in progress.

## Development and Verification
- Flutter linting and tests:
  ```bash
  flutter analyze
  flutter test
  ```
- Rust build:
  ```bash
  cargo build --manifest-path rust/Cargo.toml
  ```

## Contribution Guidelines
- Keep Linux desktop usable and avoid breaking macOS/Windows builds.
- When adding or changing Rust APIs, update the bridge definitions, regenerate bindings, then implement Dart-side logic.
- Ensure bridge code is up to date.
