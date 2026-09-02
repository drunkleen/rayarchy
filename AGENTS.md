# Rayarchy contributor guide

Rayarchy reproduces the user-visible Linux workflows of v2rayN inside the
Omarchy shell. `/mnt/storage/projects/v2rayN` is the behavioral reference;
its Avalonia/.NET implementation is not copied.

QML is presentation only. Rust owns parsing, persistence, subscriptions,
network tests, core processes, routing, DNS, and privileged operations.
Never report connected until the selected mode and outbound health check pass.
Keep secrets out of logs, generated artifacts, and Git.

Every feature must include an RPC surface, Rust tests, QML error handling, and
documentation updates. Required checks are `cargo fmt --check`, strict
Clippy, `cargo test --workspace`, QML formatting, and `omarchy plugin validate .`.

The root `manifest.json` must remain directly cloneable by `omarchy plugin add`.
Plugin installation never runs privileged hooks; backend setup is explicit.
