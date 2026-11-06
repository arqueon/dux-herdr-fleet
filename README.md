# Dux Herdr Fleet (`duxHerdrFleet`)

Multi-machine & workspace agent monitor for [DankMaterialShell](https://danklinux.com) and [herdr](https://herdr.dev) (plus the new **Herdr Desktop App** via `hc` / `herdr-core`).

> **Note:** Fork of [`Mor-dev/herdr-agent-monitor`](https://github.com/Mor-dev/herdr-agent-monitor) (`herdrAgentMonitor`), expanded to monitor all configured SSH machines (`herdr machine list` + `herdr api snapshot`), group agents hierarchically by machine and workspace/space, and include a live toggle for **`hc`** (`herdr-core` / Herdr Desktop App).

![Dux Herdr Fleet popout](assets/screenshot.png)

## Features

- **Multi-Machine & Space Tree**: Automatically discovers your local `herdr` instance and all enabled SSH machines from `herdr machine list`, fetching `herdr [--machine <host>] api snapshot` in parallel via `collect-fleet` and deduplicating canonical machine, workspace, and agent pane entries (excluding auxiliary split shells and avoiding cross-pane tab title bleed on multi-agent split tabs). Local state is polled every 15s (min 10s). Remote SSH machines are polled while the popout is open, on explicit refresh, and in the background every 60s by default (*Background remote refresh* setting; 0 = only while the popout is open), so the bar notices a blocked agent on another machine.
- **Interactive Status Filter Pills & Live Search**: Click the top `blocked`, `working`, `idle`, or `done` summary pills to filter the fleet by status (click again to reset), and use the live multi-token search bar to filter across agent names, titles, pane IDs, workspaces, machines, and working directories (`Enter` focuses the first match).
- **Herdr Desktop App (`hc`) Multi-Machine & Space Support**: Built-in setting and one-click `hc` chip in the popout header to monitor `herdr-core` / `herdr-app` across local and remote `hc` machines (`herdr-app ls`, `~/.local/state/herdr-core/default`, `hc get <addr> --json`, and `hc ls --json`), filtering out companion shells in spaces that already have an active agent.
- **Rich Agent Cards**: Displays agent provider (`claude`, `codex`, `agy`, `hermes`, `pi`, etc.), pane ID, stripped terminal title / task label, working directory, context token usage (`⛁ 68% (325k)`), rate-limit status (`5h 100%`), and live state (`blocked`, `working`, `idle`, `done`).
- **Multi-Row Machine Filter Chips**: Wrapping multi-row filter pills (`All`, `herdr` machines, and `hc · <host>` machines) with live counts and status indicator dots.
- **One-Click Focus + Niri & Notification Integration**:
  - Click an **agent card** to focus its window in Niri and focus the exact workspace/space, tab, and pane on its server (`pane.focus` RPC / `herdr [--machine <label>] agent focus` / `herdr-app do pane.focus --terminal <addr>`). When the pane lives on another machine than the one the herdr window shows, the window is switched to that machine through kitty remote control (see [Cross-machine switching](#cross-machine-switching-kitty)).
  - Click a **space header** to focus that workspace/space and its active pane.
  - Click any **Herdr notification** in Dux Shell to jump directly to the originating machine, workspace, tab, and pane.
  - Middle-click the bar pill to jump directly to the `herdr` window (Niri-only); right-click to refresh immediately.
- **Dependencies**:
  - Required: `herdr`, `python3`, `jq`
  - Cross-machine switching: [`kitty`](https://sw.kovidgoyal.net/kitty/) running the herdr client, with remote control enabled (see below)
  - Optional: `hc` and `herdr-app` (Herdr Desktop App integration), `niri` (compositor window focus)
- **IPC Commands**:
  ```bash
  dms ipc call duxHerdrFleet toggle
  dms ipc call duxHerdrFleet open
  dms ipc call duxHerdrFleet close
  dms ipc call duxHerdrFleet refresh
  dms ipc call duxHerdrFleet status
  ```

## Cross-machine switching (kitty)

herdr has no CLI or socket API that changes which saved machine a herdr window shows
(requested upstream in [herdr discussion #4396](https://github.com/herdrdev/herdr/discussions/4396)).
Until it does, Dux Herdr Fleet switches the window by driving herdr's Go to picker through
**kitty remote control**: keys are sent only to the kitty window that runs the herdr client,
and each step is checked on that window's screen before Enter is pressed. Add to `kitty.conf`
and open a new kitty window:

```conf
allow_remote_control yes
listen_on unix:${XDG_RUNTIME_DIR}/kitty-{kitty_pid}.sock
```

The socket lives in your private runtime directory. The **Cross-machine switching** setting
chooses the method:

- *Kitty remote control* (default): keys go only to the herdr window, checked on its screen.
- *Kitty, else Wayland virtual keyboard* and *Wayland virtual keyboard only* (opt-in): for
  other terminals. These type the picker keys through a `zwp_virtual_keyboard_v1` client into
  the **focused window**, only after Niri confirms the herdr window holds keyboard focus, and
  they stop without Enter or Escape if the picker cannot be confirmed. It is still a
  heuristic, so it is off unless you choose it.
- *Off*: never sends keys.

With *Off*, or when switching cannot be verified, the pane is still focused on its server and
a notification (`dms notify`) tells you which machine to select in herdr. Same-machine focus
does not need kitty.

**Clickable notifications** (setting, on by default): herdr's own notifications are replaced
by a copy posted with `dms notify` as "Dux Herdr Fleet", whose click jumps to the originating
machine, workspace, tab and pane.

## Installation

### From the DMS Plugin Registry

Install **Dux Herdr Fleet** (`duxHerdrFleet`) from **DMS Settings → Plugins**, or via CLI:

```bash
dms plugins install duxHerdrFleet
```

### Manual Installation

```bash
git clone https://github.com/arqueon/dux-herdr-fleet.git ~/.config/DankMaterialShell/plugins/duxHerdrFleet
dms ipc call plugin-scan scan
dms ipc call plugins enable duxHerdrFleet
```

## License

MIT
