# nf-telemetry-installer

Public installer for the NeuraFlash skill-telemetry MCP. The source lives in a
private repo; this repo holds only the bootstrap script and the bundled server
needed to install it onto a developer's machine.

## Install (Mac / Linux)

```sh
curl -fsSL https://raw.githubusercontent.com/neuraflash/nf-telemetry-installer/main/install.sh | bash
```

Wires telemetry into Claude Desktop and Claude Code if either is detected.
Idempotent — rerun to upgrade.

## Uninstall

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/neuraflash/nf-telemetry-installer/main/uninstall.sh)
```

## Files

- `install.sh` — bootstrap script (do not hand-edit; it's generated from the source repo on each release).
- `uninstall.sh` — clean removal.
- `server-<version>.mjs` — pinned bundled MCP server, sha256-verified by `install.sh`.

## Releasing a new version

This repo is updated automatically by the `publish-installer.yml` workflow in
the private source repo (`neuraflash/mcp-telemetry-emitter`) whenever a new
`v*` tag is pushed there.

To cut a manual release: copy `install-nf-telemetry.sh`, `uninstall-nf-telemetry.sh`,
and `dist/dxt/server/index.mjs` from the source repo into this one as
`install.sh`, `uninstall.sh`, and `server-<version>.mjs` respectively, then
update the `VERSION` and `SERVER_SHA256` constants in `install.sh`.
