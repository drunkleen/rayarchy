# Rayarchy contributor guide

Rayarchy reproduces Linux proxy-management workflows from v2rayN as a Rust
backend and CLI for Omarchy. `/mnt/storage/projects/v2rayN` is the behavioral
reference; its Avalonia/.NET implementation is not copied.

Rust owns the CLI, RPC, parsing, persistence, subscriptions, network tests,
core processes, routing, DNS, and privileged operations. Never report
connected until the selected mode and outbound health check pass. Keep secrets
out of logs, generated artifacts, and Git.

Every feature must include an RPC surface, Rust tests, CLI error handling, and
documentation updates. Required checks are `cargo fmt --check`, strict Clippy,
`cargo test --workspace`, and `omarchy plugin validate .`.

The root `manifest.json` must remain directly cloneable by `omarchy plugin add`.
Package installation never runs privileged hooks; backend setup is explicit.
