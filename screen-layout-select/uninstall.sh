#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="${HOME}/.local/bin"
AUTOSTART_DIR="${HOME}/.config/autostart"
DST_SCRIPT="${BIN_DIR}/screen-layout-select.sh"
DST_DESKTOP="${AUTOSTART_DIR}/screen-layout.desktop"

echo "[uninstall] Removing Screen Layout Selector…"

# Safely remove if exists
if [[ -f "${DST_DESKTOP}" ]]; then
  rm -f "${DST_DESKTOP}"
  echo "[uninstall] Removed: ${DST_DESKTOP}"
else
  echo "[uninstall] Warning: ${DST_DESKTOP} does not exist."
fi

if [[ -f "${DST_SCRIPT}" ]]; then
  rm -f "${DST_SCRIPT}"
  echo "[uninstall] Removed: ${DST_SCRIPT}"
else
  echo "[uninstall] Warning: ${DST_SCRIPT} does not exist."
fi

echo
