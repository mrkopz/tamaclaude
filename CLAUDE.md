# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A desk device that shows live Claude Code session status via a blocky orange Claude mascot.
Hardware: ESP32-2432S028R ("Cheap Yellow Display"), ILI9341 320x240 landscape, BLE only.

`DESIGN.md` (Thai) is the authoritative design record — every non-obvious decision and the
reason behind it lives there. **Read the relevant section of `DESIGN.md` before changing
visuals, protocol, or layout**, and add an entry there when a decision changes.

## Data flow

```
Claude Code hooks --> tamaclaude --hook --> Unix socket --> daemon --> BLE GATT --> board
Claude Code statusline --> ~/.tamaclaude/statusline.sh --> ~/.claude/.statusline-usage-cache
                                                              |
                                                       daemon reads --> "u" key --> board
```

The daemon owns all logic. Firmware only knows a fixed `VisualState` enum and draws it.
Tool-to-animation mapping is host-side and user-overridable at `~/.tamaclaude/tools.json`.

## Commands

### Host (Swift, macOS 14+)

```bash
cd host
swift build                        # debug
swift run tamatest                 # run the whole test suite
swift run tamaclaude --daemon --print --no-ble -v   # daemon without bluetooth, prints snapshots
swift run tamaclaude --send '<json>'                # inject one hand-written hook event
./Scripts/make-app.sh              # release .app -> host/dist/tamaclaude.app
./Scripts/make-app.sh --install    # install to /Applications and launch
```

There is **no `testTarget`** and no per-test filter — `swift run tamatest` runs everything
(`Sources/tamatest/Tests.swift`, grouped by `suite("...")`). A machine with only Command Line
Tools would build a `testTarget` and exit 0 without running it, which is worse than no tests.
To narrow the run, temporarily comment out `suite(...)` calls in `runAllTests()`.

Bluetooth only works from the `.app` launched via LaunchServices (`open`) — a bare binary run
from a shell gets `SIGABRT` from TCC, not a polite denial. Every rebuild changes the adhoc
cdhash, so macOS re-asks for Bluetooth permission.

### Firmware (ESP-IDF v5.5)

```bash
cd firmware
idf.py -p /dev/cu.usbserial-XX flash monitor
```

`firmware/probe/` is a separate throwaway IDF project that interrogates the real panel
(MADCTL, colour order, inversion). Its findings are recorded in `DESIGN.md`; the firmware
uses those constants, not a chip model number.

### Graphics / preview (Python + Pillow)

```bash
python3 tools/preview.py            # render every state + whole screens to out/ (PNG + GIF)
python3 tools/preview.py --sheet    # contact sheet only
python3 tools/export_layout.py      # tools/layout.toml -> firmware/main/layout.h
python3 tools/make_icon.py          # mascot -> host/Resources/AppIcon.icns
```

There is no SDL2 simulator. `tools/preview.py` is the visual dev loop: change a rect, render,
look at `out/`. It proves the *design*, not the C renderer.

## Architecture

### One source of truth per concern

- **`tools/layout.toml`** — every layout constant, palette colour, and randomised table
  (star/grass/cloud positions). Python reads it via `tools/gen/config.py`; C gets it through
  the generated `firmware/main/layout.h`. **Never edit `layout.h`** — edit the TOML and rerun
  `export_layout.py`. If preview and board disagree, that is a renderer bug, by construction.
- **`tools/gen/*.py` ↔ `firmware/main/ct_*.c`** — deliberate parallel ports, file for file:
  `props.py`↔`ct_props.c`, `mascot.py`↔`ct_mascot.c`, `rects.py`↔`ct_rects.c`,
  `screen.py`↔`ct_ui.c`, `sky.py` folds into `ct_ui.c`. A visual change means editing both
  sides; the Python side is where you iterate, the C side is the port.
- **Assets are rect lists**, `{x, y, w, h, color}` in mascot-relative *unit* coordinates —
  no bitmaps, no sprite pipeline. The mascot icon, the preview, and the board all come from
  `gen/mascot.py`.

### Host layout (`host/Sources/`)

| File | Role |
|---|---|
| `TamaCore/Protocol.swift` | `HookEvent`, `VisualState` (+ `priority`), `Snapshot`, MTU squeeze |
| `TamaCore/SessionStore.swift` | all the logic: hook → per-session state → snapshot |
| `TamaCore/ToolMap.swift` | tool name → `VisualState`, overridable via `~/.tamaclaude/tools.json` |
| `TamaCore/Text.swift` | strip to the board font's charset, then truncate |
| `TamaCore/SocketServer.swift` / `HookClient.swift` | Unix socket between `--hook` and the daemon |
| `TamaCore/BLETransport.swift` | CoreBluetooth central + auto-reconnect |
| `TamaCore/Usage{Reader,Writer}.swift` | the `.statusline-usage-cache` contract |
| `TamaCore/UsagePoll.swift` | `--usage-poll`: one claude.ai quota fetch, then exit |
| `TamaCore/{Hook,Statusline}Installer.swift` | writes into `~/.claude/settings.json` |
| `TamaCore/Daemon.swift` | wires it together + 1 s tick |
| `tamaclaude/MenuBarApp.swift` | the menu bar app **is** the daemon (Bluetooth TCC is per-`.app`) |

### Invariants worth knowing before you touch things

- **The daemon must fit one MTU (500 bytes).** `Snapshot.encoded` shrinks `n` (cards) — body,
  then title, then drop cards — and never touches `s` (sessions). Cards dropped for any reason
  (2-card cap or MTU) are counted into the separate `m` key.
- **Encode with `sortedKeys` always.** Otherwise the "did it change?" comparison is always
  true and the board gets written every second.
- **Every pose stays ≥ 5 s (`Timings.minPose`).** Poses skipped during that hold are dropped,
  never queued — a queue makes the mascot narrate an ever-later past.
- **`--hook` must always exit 0**, daemon running or not. A broken hook breaks the user's
  session, which is far worse than a frozen screen.
- **Unknown ≠ zero** in the usage panel: `-1` means unknown, `0` is a real value. Within one
  window (same `resets_at`) the percentage only increases, so a lower value is stale — never
  overwrite a newer one. Foreign keys in the shared cache file (`PROFILE_NAME`, `COST_*`)
  must survive.
- **`-v` and `-psn_*` are not modes.** LaunchServices appends `-psn_0_12345`; an app that
  rejects unknown args dies on double-click.
- **The `VisualState` enum is a contract with the firmware.** Adding or reordering it means
  changing `ct_model.c`/`ct_mascot.c` too. `tamatest` guards this.

### GATT

```
service  7A9B0001-4C1E-4B6D-9E2A-1D5C3F0A0001
state    ...0002   daemon writes the snapshot here (write with response)
config   ...0003   brightness etc.
event    ...0004   board -> host, reserved for v2
```

## Conventions

- Comments and design docs are in **Thai**; identifiers, commands, and error strings stay in
  English. Existing comments explain *why*, often citing what was tried and rejected — match
  that density rather than describing what the code does.
- Commit subjects are lowercase imperative with a conventional prefix (`feat:`, `fix:`) and
  read as a sentence about the visible effect, e.g. `feat: give the sky half the screen and
  cap cards at two`.
- The board font has no em dash and no Thai glyphs — anything crossing BLE goes through
  `Text.swift` first.

## Agent skills

### Issue tracker

Issues live as GitHub issues in `thaitop/tamaclaude`, managed with the `gh` CLI. External PRs
are not a triage surface. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical roles use their default label strings (`needs-triage`, `needs-info`,
`ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
