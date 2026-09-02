# Rayarchy specification

Rayarchy is the Linux/Omarchy implementation of the workflows exposed by
v2rayN. The source reference is `/mnt/storage/projects/v2rayN`.

The product keeps v2rayN concepts—profiles, subscriptions, groups, tests,
core selection, routing, DNS, system proxy, TUN, logs, backup/restore—but
maps them to a single Omarchy Quickshell panel. Rust is authoritative for all
network and persistent state. QML only renders data and sends RPC requests.

The plugin is installed with `omarchy plugin add` and the backend is installed
separately by `setup.sh`; plugin installation never executes privileged code.

## Definition of done

Every v2rayN Linux workflow listed in `TODO.md` has an RPC implementation,
automated tests, user-facing QML controls, documented failure behavior, and a
verified Omarchy-shell acceptance run. No connected state may be reported
without a successful outbound health check and mode activation.
