# Rayarchy specification

Rayarchy is the Linux/Omarchy backend implementation of workflows exposed by
v2rayN. The source reference is `/mnt/storage/projects/v2rayN`.

The product keeps v2rayN concepts—profiles, subscriptions, groups, tests, core
selection, routing, DNS, system proxy, TUN, logs, and backup/restore—and maps
them to a Rust daemon, JSON-RPC API, and command-line client. Rust is
authoritative for all network and persistent state.

The package is cloned with `omarchy plugin add` and the backend is installed
separately by `setup.sh`; package installation never executes privileged code.

## Definition of done

Every supported workflow has an RPC implementation, automated Rust tests, CLI
error handling, documented failure behavior, and a verified daemon/CLI
acceptance run. No connected state may be reported without a successful
outbound health check and mode activation.

The current core slice starts installed Xray or sing-box with a generated local
mixed listener and verifies an outbound request before activation.
