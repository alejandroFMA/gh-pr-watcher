#!/usr/bin/env bash
#
# Instala gh-pr-watcher como agente de launchd (macOS) que se ejecuta cada N segundos.
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="gh-pr-watcher"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
INTERVAL="${PR_WATCHER_INTERVAL:-1800}"   # segundos (1800 = 30 min)

echo "== Comprobando dependencias =="
for dep in gh jq python3 terminal-notifier; do
  if command -v "$dep" >/dev/null 2>&1; then
    echo "  ok: $dep ($(command -v "$dep"))"
  else
    echo "  FALTA: $dep"
    [[ "$dep" == terminal-notifier ]] && echo "         -> brew install terminal-notifier"
    [[ "$dep" == gh ]] && echo "         -> brew install gh && gh auth login"
    exit 1
  fi
done

echo "== Generando iconos =="
python3 "$REPO_DIR/make-icons.py" "${PR_WATCHER_DIR:-$HOME/.pr-watcher}/icons"

echo "== Instalando agente launchd =="
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$REPO_DIR/pr-watch.sh</string>
  </array>
  <key>StartInterval</key>
  <integer>$INTERVAL</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${PR_WATCHER_DIR:-$HOME/.pr-watcher}/launchd.log</string>
  <key>StandardErrorPath</key>
  <string>${PR_WATCHER_DIR:-$HOME/.pr-watcher}/launchd.err.log</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load -w "$PLIST"
echo "Instalado y cargado. Se ejecuta cada $INTERVAL segundos."
echo "Log: ${PR_WATCHER_DIR:-$HOME/.pr-watcher}/pr-watch.log"
echo ""
echo "La primera ejecución solo fija la línea base (no notifica)."
echo "Puede que macOS te pida permiso de notificaciones para 'terminal-notifier': acéptalo."
echo ""
echo "Para desinstalar:"
echo "  launchctl unload -w $PLIST && rm $PLIST"
