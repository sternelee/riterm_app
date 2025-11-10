# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RiTerm is a P2P terminal session sharing tool that consists of:
- A Flutter mobile application (lib/) 
- A Rust-based CLI host server (cli/)
- A shared Rust library with Flutter bindings (rust/)
- Shared Rust components used by both CLI and mobile app (shared/)

The project uses Flutter Rust Bridge to enable communication between the Flutter frontend and Rust backend components.

## Architecture

### Core Components

**Flutter App (lib/)**
- Main mobile application UI
- Uses Flutter Rust Bridge to communicate with Rust components
- Generated bindings in `lib/src/rust/` provide Dart APIs for Rust functionality

**CLI Host Server (cli/)**
- Terminal host server that creates P2P connections
- Manages terminal sessions and forwards data
- Entry point: `cli/src/main.rs`
- Uses clap for command-line argument parsing

**Rust Library (rust/)**
- Contains Flutter Rust Bridge bindings (`rust/src/frb_generated.rs`)
- API modules in `rust/src/api/` provide functionality exposed to Flutter
- Builds as both cdylib and staticlib for different platforms

**Shared Library (shared/)**
- Common Rust components used by both CLI and mobile app
- Core protocols and networking logic
- Terminal protocol, QUIC server implementation, message protocols

### Key Technologies
- **Flutter**: Mobile app framework
- **Flutter Rust Bridge**: FFI bindings between Dart and Rust
- **Iroh**: P2P networking and QUIC protocol implementation
- **Tokio**: Async runtime
- **Clap**: CLI argument parsing
- **Tracing**: Structured logging

## Development Commands

### Build Commands (Critical Order)
```bash
# Main build command from README - ALWAYS run in this order
cargo check -p rust_lib_riterm && flutter_rust_bridge_codegen generate

# Flutter commands
flutter pub get                    # Install Flutter dependencies
flutter run                       # Run Flutter app (development)
flutter run -d macos              # Run on macOS specifically
flutter build apk                  # Build Android APK
flutter build ios                  # Build iOS app
flutter build macos                # Build macOS app
flutter analyze                    # Analyze Dart code
flutter test                       # Run Flutter tests

# Rust workspace commands
cargo build                       # Build all workspace members
cargo build --release             # Build release version
cargo test                        # Run all Rust tests
cargo check                       # Check code without building
cargo fmt                         # Format Rust code
cargo clippy                      # Run Rust linter

# CLI specific commands
cargo run --bin cli -- host       # Start CLI host server
cargo run --bin cli -- host --relay <url> --max-connections 100  # With custom options

# Platform-specific troubleshooting
flutter clean && flutter pub get && cd macos && pod install  # Fix iOS/macOS build issues
```

### Development Workflow

**Required Build Order:**
1. Check Rust library: `cargo check -p rust_lib_riterm`
2. Generate Flutter bindings: `flutter_rust_bridge_codegen generate -r crate::api -d lib/src/rust`
3. Run Flutter app: `flutter run`

**Important Notes:**
- Flutter Rust Bridge code generation depends on the Rust library compiling successfully
- The generated bindings file (`rust/src/frb_generated.rs`) is auto-injected into `rust/src/lib.rs`
- Internal state management is separated into `rust/src/internal_state.rs` to avoid exposing implementation details to Flutter

**Platform-Specific Issues:**
- **macOS/iOS**: SystemConfiguration, CoreFoundation, and Security frameworks must be linked (configured in podspecs)
- **Tracing**: Use `try_init()` instead of `init()` to avoid panic when logger already set
- **CocoaPods**: Run `pod install` after framework changes, clean with `flutter clean && pod install` if issues persist

**Testing:**
- Run Rust tests: `cargo test`
- Run Flutter tests: `flutter test`
- Integration tests in `integration_test/`

## Code Structure

### Architecture Pattern: Separation of Public API and Internal State

**Critical Design Principle:**
- Public API (`rust/src/api/`) contains only types and functions exposed to Flutter
- Internal state (`rust/src/internal_state.rs`) contains implementation details hidden from Flutter Rust Bridge
- This prevents Flutter Rust Bridge from generating bindings for internal-only types

### Flutter Rust Bridge Configuration
- Configuration in `flutter_rust_bridge.yaml`
- Public Rust API definitions in `rust/src/api/iroh_client.rs`
- Internal state management in `rust/src/internal_state.rs` (not exposed to Flutter)
- Generated Dart bindings in `lib/src/rust/`

### Module Structure

**Rust Library (`rust/src/`):**
- `lib.rs`: Module declarations, includes auto-generated `frb_generated`
- `api/iroh_client.rs`: Public API exposed to Flutter (functions with `#[frb]` annotations)
- `internal_state.rs`: Internal state management (AppState, StreamEventListener) - HIDDEN from Flutter
- `frb_generated.rs`: Auto-generated Flutter bindings (do not edit manually)

**Workspace Structure:**
- `cli/`: CLI host server binary with terminal management
- `shared/`: Common networking and protocol implementations  
- `rust/`: Flutter Rust Bridge library with public API
- `rust_builder/`: Local Flutter package referencing the Rust library

### Key Files and Their Roles

**Core API Files:**
- `rust/src/api/iroh_client.rs`: Main Flutter API functions like `connect_to_peer`, `create_terminal`, etc.
- `rust/src/internal_state.rs`: Internal AppState and event handling (private)
- `cli/src/main.rs`: CLI server entry point with command parsing

**Networking & Protocol:**
- `shared/src/quic_server.rs`: P2P QUIC networking implementation
- `shared/src/terminal_protocol.rs`: Terminal session management
- `shared/src/message_protocol.rs`: Message serialization and routing

**Generated Bindings:**
- `rust/src/frb_generated.rs`: Auto-generated Flutter Rust Bridge code
- `lib/src/rust/`: Generated Dart bindings for the Flutter app

**Platform Configuration Files:**
- `rust_builder/ios/rust_lib_riterm.podspec`: iOS CocoaPods configuration with system frameworks
- `rust_builder/macos/rust_lib_riterm.podspec`: macOS CocoaPods configuration with system frameworks

## Important Development Notes

### Flutter Rust Bridge Gotchas

**Type Exposure Issues:**
- Flutter Rust Bridge automatically scans all public types in the API module
- Internal types like `AppState` and `StreamEventListener` must be kept separate
- Never put `#[frb]` annotations or expose internal state types in the public API

**Generated File Management:**
- `rust/src/frb_generated.rs` is auto-generated and should not be manually edited
- The file is auto-injected into `rust/src/lib.rs` by the code generator
- If compilation fails, delete `rust/src/frb_generated.rs` and regenerate

**Module Dependencies:**
- `internal_state.rs` can import from the API module but not vice versa for public types
- Keep circular dependencies in mind when separating public API from internal state

### Critical Platform Requirements

**macOS/iOS Development:**
- System frameworks must be properly linked via podspec files
- Required frameworks: SystemConfiguration, CoreFoundation, Security
- Always run `pod install` after modifying podspec files
- Use CocoaPods cleaning when encountering linking issues

**Logging and Tracing:**
- Always use `try_init()` for tracing subscriber to avoid panic on multiple initialization
- The app may restart multiple times during development, causing logger conflicts

## Build Targets

The project supports multiple build targets:
- Android APK/IPA (via Flutter)
- iOS (via Flutter) 
- Web (via Flutter)
- Native CLI binaries (via Cargo)

Profile configurations in root `Cargo.toml`:
- `release`: Standard release with LTO optimization
- `production`: Release profile with panic=abort for smaller binaries