# cobs

**cobs** (*Claude + Obsidian*) opens an [Obsidian](https://obsidian.md) vault and a
[Claude Code](https://claude.com/claude-code) session side by side with a single command.

## Description

Running `cobs.sh` does three things:

1. Starts Obsidian, if it is not already running.
2. Arranges the two windows on the largest monitor: Obsidian on the left two thirds,
   and the terminal the command was typed in on the right third. Focus is given back
   to the terminal afterwards, since a freshly started Obsidian steals it.
3. Replaces itself with a Claude Code session whose working directory is the vault.

The terminal window is identified by walking up the process tree from the script and
matching the ancestor PIDs against the owner of each window, so it works no matter
which terminal emulator you use. The monitor is picked by area, and its *work area* is
used, so panels and docks are accounted for automatically.

The exact split may be off by a few pixels for terminals that only resize in whole
character cells (GNOME Terminal, for one). The leftover pixels are left at the outer
edge of the screen, not between the windows.

If the window arrangement fails for any reason, a warning is printed and the Claude
Code session starts anyway.

## Dependencies

- **Bash**
- **X11 session** — the arrangement is skipped under Wayland, where libwnck cannot
  manage other applications' windows
- **python3-gi** with the Wnck and GdkX11 typelibs (usually already installed on GNOME):
  ```sh
  sudo apt install python3-gi gir1.2-wnck-3.0
  ```
- **obsidian** and **claude** available in your PATH

## Installation

```sh
./install.sh
```

This symlinks `cobs.sh` into `~/bin`, so a `git pull` in this repository is enough to
update the installed command. Use `BIN_DIR=~/.local/bin ./install.sh` to link it
somewhere else.

## Uninstallation

```sh
./uninstall.sh
```

## Configuration

| Variable | Default | Description |
| --- | --- | --- |
| `COBS_VAULT_DIR` | `~/Dropbox/my_life_in_the_cloud` | Vault directory to open |
| `COBS_NO_LAYOUT` | unset | Set to `1` to skip the window arrangement |
| `COBS_LAYOUT_TIMEOUT` | `20` | Seconds to wait for the Obsidian window |

---

**Author:** Arliones Hoeller Jr.<br>
**License:** MIT
