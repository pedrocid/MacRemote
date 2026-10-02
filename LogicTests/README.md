# LogicTests

This standalone SwiftPM package exercises shared logic because the Tuist project has no test targets.

Run `./run-tests.sh` from this directory. The package's `Sources` may contain production Swift files only as relative symlinks to the app source tree; do not copy or reimplement production code here. `./check-symlinks.sh` enforces this rule.

LIMITATIONS: the harness compiles only Foundation/Network/CryptoKit/Security logic for macOS. It does NOT verify the iOS build, LocalAuthentication UI, AppIntent metadata or AppShortcuts phrases, Tuist resource inclusion, or real CGEvent/CGSession behavior.
