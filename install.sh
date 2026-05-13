#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

APP_BUNDLE="build/TodoIt.app"
DEST_APP="/Applications/TodoIt.app"
CLI_SRC="build/bin/todoit"

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

if [[ -w "$DEST_CLI_DIR" ]]; then
    echo "→ Installing CLI → ${DEST_CLI}"
    cp "$CLI_SRC" "$DEST_CLI"
    chmod +x "$DEST_CLI"
else
    echo "→ Installing CLI → ${DEST_CLI} (requires sudo)"
    sudo cp "$CLI_SRC" "$DEST_CLI"
    sudo chmod +x "$DEST_CLI"
fi

echo ""
echo "✓ Installed."
echo "  • Open the menubar app: open -a TodoIt"
echo "  • Add a task from the shell: todoit add \"Buy milk\""
echo "  • List today: todoit list"
