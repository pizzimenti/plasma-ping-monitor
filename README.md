# Ping Monitor (plasmoid)

A small KDE Plasma plasmoid that pings two hosts (1.1.1.1 and 8.8.8.8) and displays a 30s RTT chart.

Development
- Edit sources in `~/Code/org.kde.plasma.pingmonitor` (this is the development copy).
- Fast preview without installing:
  - `plasmoidviewer ~/Code/org.kde.plasma.pingmonitor` — open the plasmoid in a window and view QML errors.
  - `plasmawindowed ~/Code/org.kde.plasma.pingmonitor` — run windowed for quick interactive testing.

Install / Use on your desktop
1. (Optional) Remove any currently installed copy:
   ```bash
   plasmapkg2 --remove org.kde.plasma.pingmonitor || true
   ```
2. Install the development copy so Plasma will load it from your home:
   ```bash
   plasmapkg2 --install ~/Code/org.kde.plasma.pingmonitor
   ```
3. Add it to your desktop: Right-click → Enter Edit Mode → Add Widgets → search for "Ping Monitor" and drag it to the desktop.

Live development options
- Symlink method (Plasma will read files from your repo path):
  ```bash
  mv ~/.local/share/plasma/plasmoids/org.kde.plasma.pingmonitor ~/.local/share/plasma/plasmoids/org.kde.plasma.pingmonitor.orig
  ln -s ~/Code/org.kde.plasma.pingmonitor ~/.local/share/plasma/plasmoids/org.kde.plasma.pingmonitor
  kquitapp5 plasmashell && kstart5 plasmashell
  ```
  Restart `plasmashell` after major QML changes to ensure the shell reloads updated QML.

Uninstall
- Remove the installed plasmoid:
  ```bash
  plasmapkg2 --remove org.kde.plasma.pingmonitor
  ```

Troubleshooting
- If `plasmoidviewer` shows QML errors, paste them into the issue/PR or report them here.
- If the widget doesn't appear in the Add Widgets list after installing, restart plasmashell or log out/in.

Contributing
- This repo is tracked with git; please open issues or PRs if you want to collaborate.

License
- MIT (see `LICENSE`)
