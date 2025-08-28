# Screen Layout Select

**Screen Layout Select** is a simple tool to automatically adjust your monitor layout according to the network your computer is connected to. It's ideal for those who switch between different environments (home, work, lab) and need distinct screen configurations in each location.

## Description

When starting a GNOME session, the script detects the network IP and runs the corresponding monitor layout, using user-customized scripts (e.g., `~/.screenlayout/home.sh`). This allows you to quickly switch between multiple monitor setups without manual intervention.

## Dependencies

- **Bash** (default shell on Linux systems)
- **xrandr** (for monitor layout management)
- Custom layout scripts in `~/.screenlayout/` (e.g., `home.sh`, `work.sh`)

## Installation

1. Make sure you have `xrandr` installed:
   ```sh
   sudo apt install x11-xserver-utils
   ```
2. Create your layout scripts in `~/.screenlayout/` (e.g., `home.sh`, `work.sh`).

   > 💡 **Tip:** You can use the graphical utility `arandr` to visually configure your monitor layout and save the generated script in `~/.screenlayout/`. Install it with:
   > ```sh
   > sudo apt install arandr
   > ```
   > Then, open `arandr`, adjust the desired layout, and save the script via the **Layout > Save As...** menu.

3. Run the installation script:
   ```sh
   ./install.sh
   ```
4. The script will be copied to `~/.local/bin/` and set to start automatically with your GNOME session.

## Uninstallation

To remove Screen Layout Select and its autostart entry, run:
```sh
./uninstall.sh
```

## Customization

Edit the `screen-layout-select.sh` file to adjust the IPs and layout scripts according to your networks and needs.

---

**Author:** Arliones Hoeller Jr.<br>
**License:** MIT