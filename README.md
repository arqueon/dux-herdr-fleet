# Dux Herdr Fleet (`duxHerdrFleet`)

Multi-machine & workspace agent monitor for [DankMaterialShell](https://danklinux.com) and [herdr](https://herdr.dev) (plus the new **Herdr Desktop App** via `hc` / `herdr-core`).

Inspired by and expanded from [`Mor-dev/herdr-agent-monitor`](https://github.com/Mor-dev/herdr-agent-monitor).

## Features

- **Multi-Machine & Space Tree**: Automatically discovers your local `herdr` instance and all enabled SSH machines from `herdr machine list`, fetching `herdr [--machine <host>] api snapshot` in parallel via `collect-fleet`.
- **Herdr Desktop App (`hc`) Toggle**: Built-in setting and one-click `hc` chip in the popout header to toggle monitoring of `herdr-core` (`hc ls --json`) terminals from the graphical Herdr app.
- **Rich Agent Cards**: Displays agent provider (`claude`, `codex`, `agy`, `hermes`, etc.), pane ID, stripped terminal title / custom pane label, working directory, context token usage (`⛁ 68% (325k)`), rate-limit status (`5h 100%`), and live state (`blocked`, `working`, `idle`, `done`).
- **Machine Filter Chips**: Filter the popout tree by machine (`Todas`, `local`, `casa-cachyos`, `sinope`, `hermes`, `hc`) with status indicator dots.
- **One-Click Focus + Niri Integration**:
  - Click an **agent card** to focus its pane (`herdr [--machine <host>] agent focus <pane_id>` or `herdr-app do agent.focus --terminal <addr>`) and focus the `herdr` terminal window in Niri.
  - Click a **space header** to focus that workspace (`herdr [--machine <host>] workspace focus <ws_id>`).
  - Middle-click the bar pill to jump directly to the `herdr` window; right-click to refresh immediately.
- **IPC Commands**:
  ```bash
  dms ipc call duxHerdrFleet toggle
  dms ipc call duxHerdrFleet open
  dms ipc call duxHerdrFleet close
  dms ipc call duxHerdrFleet refresh
  dms ipc call duxHerdrFleet status
  ```

## Installation

```bash
ln -s ~/Projects/dms/dux-herdr-fleet ~/.config/DankMaterialShell/plugins/duxHerdrFleet
dms ipc call plugin-scan scan
dms ipc call plugins enable duxHerdrFleet
```

## License

MIT
