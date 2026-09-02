# Rayarchy

v2rayN-inspired proxy management for the Omarchy shell. It uses the local
`/mnt/storage/projects/v2rayN` source tree as its behavior reference while
providing an Omarchy-native QML interface and Rust backend.

Install the shell plugin:

```sh
omarchy plugin add https://github.com/drunkleen/rayarchy --enable
```

Install and start the unprivileged backend from the cloned plugin checkout
(this compiles the Rust backend locally; no sudo is required):

```sh
~/.config/omarchy/plugins/com.drunkleen.rayarchy/setup.sh
```

The plugin itself is unprivileged. TUN/transparent routing and kill-switch
support are intentionally refused until their narrowly-scoped helper is
installed and enabled by a future release.

Then run the backend setup from the installed checkout. Development status and
the complete parity checklist are in `TODO.md` and `instructions.md`.
