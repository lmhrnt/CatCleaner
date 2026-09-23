#!/bin/bash
# Completely remove CatCleaner and its support files.
#

set -euo pipefail

APP_NAME="CatCleaner.app"
INSTALL_DIR="/Applications"

cyan() { printf "\033[36m%s\033[0m\n" "$1"; }
green() { printf "\033[32m%s\033[0m\n" "$1"; }
red() { printf "\033[31m%s\033[0m\n" "$1"; }

# Guard: HOME must be set so the explicit paths below never expand to "/...".
if [ -z "${HOME:-}" ]; then
  red "HOME is not set; aborting to avoid removing unintended paths."
  exit 1
fi

# Exact, explicit paths only (no globs, no wildcards) so this can never delete
# more than CatCleaner's own files.
SUPPORT_PATHS=(
  "$HOME/Library/Application Support/CatCleaner"
  "$HOME/Library/Caches/com.catcleaner.app"
  "$HOME/Library/HTTPStorages/com.catcleaner.app"
  "$HOME/Library/Logs/CatCleaner"
  "$HOME/Library/Preferences/com.catcleaner.app.plist"
  "$HOME/Library/Preferences/com.catcleaner.shared.plist"
  "$HOME/Library/Saved Application State/com.catcleaner.app.savedState"
)

cyan "Quitting CatCleaner if it is running..."
osascript -e 'tell application "CatCleaner" to quit' >/dev/null 2>&1 || true
# The menu-bar helper is a separate process.
pkill -f "MacCleanMenu" >/dev/null 2>&1 || true

cyan "Removing $INSTALL_DIR/$APP_NAME..."
rm -rf "$INSTALL_DIR/$APP_NAME"

cyan "Removing support files..."
for path in "${SUPPORT_PATHS[@]}"; do
  if [ -e "$path" ]; then
    rm -rf "$path"
    echo "  removed $path"
  fi
done

# Clear any cached preferences held by cfprefsd so they don't get rewritten.
defaults delete com.catcleaner.app >/dev/null 2>&1 || true
defaults delete com.catcleaner.shared >/dev/null 2>&1 || true

green ""
green "✓ CatCleaner has been uninstalled."
echo ""
echo "If CatCleaner still appears under System Settings → General → Login Items,"
echo "remove the leftover entry there; macOS clears it once the app is gone."
