#!/usr/bin/env bash
set -euo pipefail

# Destination directory for the symlink (must be in your PATH)
BIN_DIR="${BIN_DIR:-${HOME}/bin}"

# File paths inside the repository (where this script is located)
REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
SRC_SCRIPT="${REPO_DIR}/codes.sh"
DST_SCRIPT="${BIN_DIR}/codes.sh"

echo "[install] Installing codes…"

# Basic checks
[[ -f "${SRC_SCRIPT}" ]] || { echo "[install] ERROR: '${SRC_SCRIPT}' not found."; exit 1; }

# Create destination directory
mkdir -p "${BIN_DIR}"

# The script is symlinked, not copied, so that `git pull` in this repository is
# enough to update the installed command.
chmod 0755 "${SRC_SCRIPT}"
ln -sfn "${SRC_SCRIPT}" "${DST_SCRIPT}"

echo "[install] Linked: ${DST_SCRIPT} -> ${SRC_SCRIPT}"

# Warn if the destination is not reachable from PATH
case ":${PATH}:" in
  *":${BIN_DIR}:"*) ;;
  *) echo "[install] WARNING: '${BIN_DIR}' is not in your PATH." ;;
esac

# Report missing runtime dependencies, without failing the installation
missing=()
command -v code >/dev/null || missing+=("code (VS Code)")
command -v claude >/dev/null || missing+=("claude")
python3 -c 'import gi; gi.require_version("Wnck", "3.0"); gi.require_version("GdkX11", "3.0")' 2>/dev/null \
  || missing+=("python3-gi with gir1.2-wnck-3.0 (window arrangement)")
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "[install] WARNING: missing dependencies: ${missing[*]}"
fi

echo "[install] Done! Run 'codes.sh' from the terminal you want on the right third,"
echo "[install] in the directory you want VS Code to open."
