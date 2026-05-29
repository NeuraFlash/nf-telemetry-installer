#!/usr/bin/env bash
#
# install-nf-telemetry.sh
#
# One-shot installer that wires the NeuraFlash skill-telemetry MCP into
# Claude Desktop and/or Claude Code on the current machine. Idempotent —
# rerunning upgrades the server and rewrites both configs cleanly.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/neuraflash/nf-telemetry-installer/main/install.sh | bash
#
# Or, with explicit overrides:
#   TELEMETRY_EMAIL=alice@neuraflash.com bash install.sh

set -euo pipefail

# ---- Configuration (mirror updates this on each release) --------------------

VERSION="0.2.2"
SERVER_URL="${SERVER_URL:-https://raw.githubusercontent.com/neuraflash/nf-telemetry-installer/main/server-${VERSION}.mjs}"
SERVER_SHA256="${SERVER_SHA256:-841651b00551fbc055fef53faabcf75f16087f2adeaaf9467f37d336732bfa6a}"
TELEMETRY_ENDPOINT="${TELEMETRY_ENDPOINT:-https://3xz7zvl7ca.execute-api.us-east-1.amazonaws.com/events}"
TELEMETRY_TOKEN="${TELEMETRY_TOKEN:-nx1of5baLkOTmvBTiTiKRnI9zsMSQfqBHv3DdbdjAcD3ox59}"

# ---- Paths ------------------------------------------------------------------

INSTALL_DIR="$HOME/.local/lib/nf-telemetry"
SERVER_PATH="$INSTALL_DIR/server.mjs"

case "$(uname -s)" in
  Darwin)
    DESKTOP_CFG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
    DESKTOP_APP_DIR="$HOME/Library/Application Support/Claude"
    ;;
  Linux)
    DESKTOP_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/Claude/claude_desktop_config.json"
    DESKTOP_APP_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/Claude"
    ;;
  *)
    echo "Unsupported OS: $(uname -s). This script targets macOS and Linux." >&2
    exit 1
    ;;
esac

# ---- Logging ----------------------------------------------------------------

log()  { printf '\033[1;34m[nf-telemetry]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[nf-telemetry]\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31m[nf-telemetry]\033[0m %s\n' "$*" >&2; exit 1; }

# ---- Prereqs ----------------------------------------------------------------

require_node() {
  if ! command -v node >/dev/null 2>&1; then
    fail "node not found. Install Node 18+ first (e.g. 'brew install node') and rerun."
  fi
  local major
  major="$(node -p 'process.versions.node.split(".")[0]')"
  if [ "$major" -lt 18 ]; then
    fail "Node $major found; need >= 18. Upgrade and rerun."
  fi
}

# ---- Email auto-detect ------------------------------------------------------

detect_email() {
  if [ -n "${TELEMETRY_EMAIL:-}" ]; then
    echo "$TELEMETRY_EMAIL"; return
  fi
  if [ -n "${CLAUDE_USER_EMAIL:-}" ]; then
    echo "$CLAUDE_USER_EMAIL"; return
  fi
  local guess
  guess="$(git config --global user.email 2>/dev/null || true)"
  if [ -n "$guess" ] && [[ "$guess" == *"@neuraflash.com" ]]; then
    echo "$guess"; return
  fi
  echo "${USER}@neuraflash.com"
}

# ---- Server download --------------------------------------------------------

install_server() {
  log "Installing server to $SERVER_PATH"
  mkdir -p "$INSTALL_DIR"
  local tmp="$INSTALL_DIR/server.mjs.tmp"
  curl -fsSL "$SERVER_URL" -o "$tmp"

  if [ "$SERVER_SHA256" != "PLACEHOLDER_FILL_IN_AT_PUBLISH_TIME" ]; then
    local got
    got="$(shasum -a 256 "$tmp" | awk '{print $1}')"
    if [ "$got" != "$SERVER_SHA256" ]; then
      rm -f "$tmp"
      fail "sha256 mismatch: expected $SERVER_SHA256, got $got"
    fi
  fi

  mv "$tmp" "$SERVER_PATH"
  chmod 0644 "$SERVER_PATH"
}

# ---- Desktop config ---------------------------------------------------------

# Atomic update of claude_desktop_config.json using node (always present here).
configure_desktop() {
  if [ ! -d "$DESKTOP_APP_DIR" ]; then
    log "Claude Desktop not detected (no $DESKTOP_APP_DIR). Skipping Desktop wiring."
    return 0
  fi

  log "Wiring Claude Desktop ($DESKTOP_CFG)"
  mkdir -p "$DESKTOP_APP_DIR"
  [ -f "$DESKTOP_CFG" ] || echo '{}' > "$DESKTOP_CFG"

  TMP="$(mktemp)"
  EMAIL="$1" SERVER_PATH="$SERVER_PATH" \
  TELEMETRY_ENDPOINT="$TELEMETRY_ENDPOINT" TELEMETRY_TOKEN="$TELEMETRY_TOKEN" \
  CFG_PATH="$DESKTOP_CFG" OUT_PATH="$TMP" \
  node -e '
    const fs = require("fs");
    const path = process.env.CFG_PATH;
    const out  = process.env.OUT_PATH;
    const cfg = JSON.parse(fs.readFileSync(path, "utf8") || "{}");
    cfg.mcpServers = cfg.mcpServers || {};

    // Remove legacy entries to avoid duplicate events.
    for (const stale of ["skill-telemetry", "telemetry"]) {
      if (cfg.mcpServers[stale]) {
        console.error(`[nf-telemetry] removing legacy mcpServer entry: ${stale}`);
        delete cfg.mcpServers[stale];
      }
    }

    cfg.mcpServers["nf-telemetry"] = {
      command: "node",
      args:    [process.env.SERVER_PATH],
      env: {
        TELEMETRY_ENDPOINT: process.env.TELEMETRY_ENDPOINT,
        TELEMETRY_TOKEN:    process.env.TELEMETRY_TOKEN,
        CLAUDE_USER_EMAIL:  process.env.EMAIL,
        CLAUDE_SURFACE:     "claude_desktop",
        REQUEST_TIMEOUT_MS: "5000",
        HASH_SUMMARIES:     "false"
      }
    };

    fs.writeFileSync(out, JSON.stringify(cfg, null, 2) + "\n");
  '

  mv "$TMP" "$DESKTOP_CFG"
  log "Desktop wired. Restart Claude Desktop for changes to take effect."
}

# ---- Code config ------------------------------------------------------------

configure_code() {
  if ! command -v claude >/dev/null 2>&1; then
    log "Claude Code (claude CLI) not detected. Skipping Code wiring."
    return 0
  fi

  log "Wiring Claude Code via 'claude mcp'"
  # Idempotent: drop any prior entry with the same name in user scope.
  claude mcp remove nf-telemetry --scope user >/dev/null 2>&1 || true

  claude mcp add nf-telemetry node "$SERVER_PATH" \
    --scope user \
    --env TELEMETRY_ENDPOINT="$TELEMETRY_ENDPOINT" \
    --env TELEMETRY_TOKEN="$TELEMETRY_TOKEN" \
    --env CLAUDE_USER_EMAIL="$1" \
    --env CLAUDE_SURFACE="claude_code" \
    --env REQUEST_TIMEOUT_MS="5000" \
    --env HASH_SUMMARIES="false"
  log "Code wired."
}

# ---- Verify ingest ----------------------------------------------------------

verify_ingest() {
  log "Sending an install-check event to confirm ingest is reachable..."
  local now started ended
  now="$(date -u +%Y-%m-%dT%H:%M:%S)"
  started="${now}.000Z"
  ended="${now}.001Z"
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$TELEMETRY_ENDPOINT" \
    -H "authorization: Bearer $TELEMETRY_TOKEN" \
    -H 'content-type: application/json' \
    --data-binary @- <<JSON
{"events":[{
  "invocation_id":"install-check-$(date +%s)",
  "skill_name":"install-check",
  "status":"success",
  "user_id":"$1",
  "surface":"installer",
  "input_summary":null,
  "output_summary":null,
  "error_message":null,
  "started_at":"$started",
  "ended_at":"$ended",
  "duration_ms":1,
  "schema_version":1
}]}
JSON
)"
  if [ "$code" = "200" ]; then
    log "Ingest reachable (HTTP 200)."
  else
    warn "Ingest returned HTTP $code — events from this machine may not land. Check your network or contact platform@neuraflash.com."
  fi
}

# ---- Main -------------------------------------------------------------------

main() {
  require_node
  local email
  email="$(detect_email)"
  log "Installing for user: $email"

  install_server
  configure_desktop "$email"
  configure_code    "$email"
  verify_ingest     "$email"

  cat <<EOF

[nf-telemetry] done.

  • Server:   $SERVER_PATH
  • User:     $email
  • Endpoint: $TELEMETRY_ENDPOINT

Next steps:
  • Restart Claude Desktop if it was running.
  • Open a new Claude Code session to pick up the new MCP entry.
  • Run any skill — its skill_start/skill_end will land in Athena within seconds.

To remove: bash <(curl -fsSL https://raw.githubusercontent.com/neuraflash/nf-telemetry-installer/main/uninstall.sh)
EOF
}

main "$@"
