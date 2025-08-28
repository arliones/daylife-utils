#!/usr/bin/env bash
set -euo pipefail

# Destination directories
BIN_DIR="${HOME}/.local/bin"
AUTOSTART_DIR="${HOME}/.config/autostart"

# File paths inside the repository (where this script is located)
REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
SRC_SCRIPT="${REPO_DIR}/screen-layout-select.sh"
SRC_DESKTOP="${REPO_DIR}/screen-layout.desktop"

# Installation paths
DST_SCRIPT="${BIN_DIR}/screen-layout-select.sh"
DST_DESKTOP="${AUTOSTART_DIR}/screen-layout.desktop"

echo "[install] Installing Screen Layout Selector…"

# Basic checks
[[ -f "${SRC_SCRIPT}" ]] || { echo "[install] ERROR: '${SRC_SCRIPT}' not found."; exit 1; }
[[ -f "${SRC_DESKTOP}" ]] || { echo "[install] ERROR: '${SRC_DESKTOP}' not found."; exit 1; }

# Create destination directories
mkdir -p "${BIN_DIR}" "${AUTOSTART_DIR}"

# Install main script
install -m 0755 "${SRC_SCRIPT}" "${DST_SCRIPT}"

# Copy .desktop file
install -m 0644 "${SRC_DESKTOP}" "${DST_DESKTOP}"

# Ensure the .desktop file points to the installed path and has a small delay
# Replace the Exec= line with one that uses the real script path
# Note: uses portable sed for Linux (GNU sed)
ESCAPED_PATH="$(printf '%s\n' "${DST_SCRIPT}" | sed 's/[&/\]/\\&/g')"
sed -i \
  -e "s|^Exec=.*$|Exec=/bin/bash -lc \"sleep 3 && ${ESCAPED_PATH}\"|g" \
  -e "s|^X-GNOME-Autostart-enabled=.*$|X-GNOME-Autostart-enabled=true|g" \
  "${DST_DESKTOP}"

# If the keys do not exist, ensure they are included
grep -q '^Exec=' "${DST_DESKTOP}" || echo "Exec=/bin/bash -lc \"sleep 3 && ${DST_SCRIPT}\"" >> "${DST_DESKTOP}"
grep -q '^X-GNOME-Autostart-enabled=' "${DST_DESKTOP}" || echo "X-GNOME-Autostart-enabled=true" >> "${DST_DESKTOP}"
grep -q '^OnlyShowIn=' "${DST_DESKTOP}" || echo "OnlyShowIn=GNOME;Unity;" >> "${DST_DESKTOP}"

echo "[install] Installed files:"
echo "  - ${DST_SCRIPT}"
echo "  - ${DST_DESKTOP}"
echo "[install] Done! The script will run at GNOME session login."
