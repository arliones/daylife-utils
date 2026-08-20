#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="${BIN_DIR:-${HOME}/bin}"
DST_SCRIPT="${BIN_DIR}/codes.sh"

echo "[uninstall] Removing codes…"

if [[ -L "${DST_SCRIPT}" || -f "${DST_SCRIPT}" ]]; then
  rm -f "${DST_SCRIPT}"
  echo "[uninstall] Removed: ${DST_SCRIPT}"
else
  echo "[uninstall] Warning: ${DST_SCRIPT} does not exist."
fi

echo "[uninstall] Done! The repository copy was kept."
