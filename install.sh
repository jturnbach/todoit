#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

APP_BUNDLE="build/TodoIt.app"
DEST_APP="/Applications/TodoIt.app"
CLI_SRC="build/bin/todoit"
MCP_SRC="build/bin/todoit-mcp"

# Pick the first writable directory in PATH, otherwise fall back to
# ~/.local/bin and warn the user to add it. Honors TODOIT_CLI_DEST override.
pick_cli_dest() {
    if [[ -n "${TODOIT_CLI_DEST:-}" ]]; then
        echo "${TODOIT_CLI_DEST}"
        return
    fi
    for d in /opt/homebrew/bin /usr/local/bin "${HOME}/.local/bin" "${HOME}/bin"; do
        if [[ -d "$d" && -w "$d" ]]; then
            echo "$d/todoit"
            return
        fi
    done
    mkdir -p "${HOME}/.local/bin"
    echo "${HOME}/.local/bin/todoit"
}
DEST_CLI="$(pick_cli_dest)"
DEST_MCP_DIR="$(dirname "${DEST_CLI}")"
DEST_MCP="${DEST_MCP_DIR}/todoit-mcp"

echo ""
echo "→ Installing ${APP_BUNDLE} → ${DEST_APP}"
# Quit any running instance so we can replace it cleanly
osascript -e 'tell application "TodoIt" to quit' >/dev/null 2>&1 || true
sleep 0.5

if [[ -d "$DEST_APP" ]]; then
    rm -rf "$DEST_APP"
fi
cp -R "$APP_BUNDLE" "$DEST_APP"

DEST_CLI_DIR="$(dirname "$DEST_CLI")"
mkdir -p "$DEST_CLI_DIR" 2>/dev/null || true

install_bin() {
    local src="$1" dst="$2" label="$3"
    local dir
    dir="$(dirname "$dst")"
    if [[ -w "$dir" ]]; then
        echo "→ Installing ${label} → ${dst}"
        cp "$src" "$dst"
        chmod +x "$dst"
    else
        echo "→ Installing ${label} → ${dst} (requires sudo)"
        sudo cp "$src" "$dst"
        sudo chmod +x "$dst"
    fi
}

install_bin "$CLI_SRC" "$DEST_CLI" "CLI"
install_bin "$MCP_SRC" "$DEST_MCP" "MCP server"

echo ""
echo "✓ Installed."
echo "  • Open the menubar app:      open -a TodoIt"
echo "  • Add a task from the shell: todoit add \"Buy milk\""
echo "  • List today:                todoit list"
echo ""
echo "To let Claude Desktop add tasks, add this to"
echo "  ~/Library/Application Support/Claude/claude_desktop_config.json"
echo "(inside the top-level \"mcpServers\" object):"
echo ""
echo "    \"todoit\": { \"command\": \"${DEST_MCP}\" }"
echo ""
echo "Then quit and re-launch Claude Desktop."
