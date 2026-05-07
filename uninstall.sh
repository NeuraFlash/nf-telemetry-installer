#!/usr/bin/env bash
#
# uninstall-nf-telemetry.sh
#
# Removes the NeuraFlash skill-telemetry MCP from Claude Desktop, Claude Code,
# and the local filesystem.

set -euo pipefail

INSTALL_DIR="$HOME/.local/lib/nf-telemetry"

case "$(uname -s)" in
  Darwin) DESKTOP_CFG="$HOME/Library/Application Support/Claude/claude_desktop_config.json" ;;
  Linux)  DESKTOP_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/Claude/claude_desktop_config.json" ;;
  *)      echo "Unsupported OS"; exit 1 ;;
esac

log() { printf '\033[1;34m[nf-telemetry]\033[0m %s\n' "$*"; }

if [ -f "$DESKTOP_CFG" ]; then
  log "Removing entry from $DESKTOP_CFG"
  TMP="$(mktemp)"
  CFG_PATH="$DESKTOP_CFG" OUT_PATH="$TMP" node -e '
    const fs = require("fs");
    const cfg = JSON.parse(fs.readFileSync(process.env.CFG_PATH, "utf8") || "{}");
    if (cfg.mcpServers) {
      for (const k of ["nf-telemetry", "skill-telemetry", "telemetry"]) delete cfg.mcpServers[k];
    }
    fs.writeFileSync(process.env.OUT_PATH, JSON.stringify(cfg, null, 2) + "\n");
  '
  mv "$TMP" "$DESKTOP_CFG"
fi

if command -v claude >/dev/null 2>&1; then
  log "Removing entry from Claude Code"
  claude mcp remove nf-telemetry --scope user >/dev/null 2>&1 || true
fi

if [ -d "$INSTALL_DIR" ]; then
  log "Removing $INSTALL_DIR"
  rm -rf "$INSTALL_DIR"
fi

log "Done. Restart Claude Desktop if it was running."
