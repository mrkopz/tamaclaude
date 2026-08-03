# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A desk device that shows live Claude Code session status via a blocky orange Claude mascot.
Hardware: ESP32-2432S028R ("Cheap Yellow Display"), ILI9341 320x240 landscape, BLE only.

`DESIGN.md` (Thai) records the **current** design and the reasons that are not visible from
the code — not a changelog. **Read the relevant section before changing visuals, protocol,
or layout.** Write to it only when a previous decision is *reversed*, or when you hit a
constraint the code cannot state on its own (a measured hardware value, a framework quirk, a
rule that must hold in two places at once). Ordinary fixes need no entry — git history is
the log. When an entry stops being true, rewrite it in place; do not append the correction
below it.

## Data flow

```
Claude Code hooks --> tamaclaude --hook --> Unix socket --> daemon --> BLE GATT --> board
                                                                  \                  ^
                                                                   '-> sealed TCP ---'
                                                                       (only when BLE
                                                                        is 10 s gone)

Open-Meteo --> WeatherService (every 15 min) --> page frame --> the same two paths

Claude Code statusline --> ~/.tamaclaude/statusline.sh --.
                                                          >--> ~/.claude/.statusline-usage-cache
menu bar timer --> tamaclaude --usage-poll --> claude.ai --'                |
                                                        daemon reads --> "u" key --> board
```

The quota panel has **two** sources, not one. The statusline pipe needs no credential but is
event-driven, so it goes quiet exactly when the desk display is left alone; the poll pipe uses
the user's `sessionKey` and keeps the number moving with Claude Code closed. Neither replaces
the other and they are separate switches — see the reversal note in `DESIGN.md`.

The daemon owns all logic. Firmware only knows two fixed enums — `VisualState` and
`PageKind` — and draws them.
Tool-to-animation mapping is host-side and user-overridable at `~/.tamaclaude/tools.json`.

## Commands

### Host (Swift, macOS 14+)

```bash
cd host
swift build                        # debug
swift run tamatest                 # run the whole test suite
swift run tamaclaude --daemon --print --no-ble -v   # daemon without bluetooth, prints snapshots
swift run tamaclaude --send '<json>'                # inject one hand-written hook event
swift run tamaclaude --usage-poll                   # one quota fetch -> cache, then exit
swift run tamaclaude --usage-cache < statusline.json  # the statusline pipe, by hand
swift run tamaclaude --install-statusline           # take over statusLine.command
swift run tamaclaude --remove-statusline            # give the slot back
./Scripts/make-app.sh              # release .app -> host/dist/TamaClaude.app
./Scripts/make-app.sh --install    # install to /Applications and launch
```

`--usage-poll` reads the key from `~/.tamaclaude/session-key` (mode 600, never argv, never env)
and exits: `0` = wrote the cache · `2` = key rejected · `3` = key file unusable · `1` = anything else.
The menu bar app runs it on a timer; the key is set from its gear menu, not by hand.

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
python3 tools/preview.py            # render every state + whole screens (incl. weather) to out/
python3 tools/preview.py --sheet    # contact sheet only
python3 tools/export_layout.py      # tools/layout.toml -> firmware/main/layout.h
python3 tools/export_thai.py        # tools/thai.toml -> ThaiTable.swift + gen/thai_table.py
python3 tools/export_thai_font.py   # tools/thai.toml + Sarabun -> ct_font_thai_*.c + fonts/*.json
python3 tools/test_thai.py          # thai golden vectors, python side (swift side is in tamatest)
python3 tools/make_icon.py          # logo PNG (≥128px) + mascot (≤64px) -> host/Resources/AppIcon.icns
```

There is no SDL2 simulator. `tools/preview.py` is the visual dev loop: change a rect, render,
look at `out/`. It proves the *design*, not the C renderer.

## Architecture

### One source of truth per concern

- **`tools/layout.toml`** — every layout constant, palette colour, and randomised table
  (star/grass/cloud positions). Python reads it via `tools/gen/config.py`; C gets it through
  the generated `firmware/main/layout.h`. **Never edit `layout.h`** — edit the TOML and rerun
  `export_layout.py`. If preview and board disagree, that is a renderer bug, by construction.
- **`tools/thai.toml`** — every Thai glyph-variant rule and per-size shift. Swift gets
  `ThaiTable.swift`, Python gets `gen/thai_table.py`, the font gets `ct_font_thai_{12,14}.c`,
  all through `export_thai*.py`. **Never edit the generated files.** The cluster walk itself is
  a parallel port (`TamaCore/ThaiShaper.swift` ↔ `gen/thai.py`) held together by
  `tools/thai-golden.json`, which both test sides read. See ADR-0008.
- **`tools/gen/*.py` ↔ `firmware/main/ct_*.c`** — deliberate parallel ports, file for file:
  `props.py`↔`ct_props.c`, `mascot.py`↔`ct_mascot.c`, `rects.py`↔`ct_rects.c`,
  `screen.py`↔`ct_ui.c`, `weather.py`↔`ct_weather_ui.c`, `sky.py` folds into `ct_ui.c`.
  `pages.py` is the odd one out: it feeds `export_layout.py`, which generates `ct_page_kind_t`. A visual change means editing both
  sides; the Python side is where you iterate, the C side is the port.
- **Assets are rect lists**, `{x, y, w, h, color}` in mascot-relative *unit* coordinates —
  no bitmaps, no sprite pipeline. The preview and the board both come from `gen/mascot.py`.
  The **app icon is half an exception** — `.icns` carries per-size art, so ≥128 px is a
  hand-drawn PNG (`docs/images/tamaclaude-logo.png`) and ≤64 px is drawn from the same rect
  list. See the reversal note in `DESIGN.md`.

### Host layout (`host/Sources/`)

| File | Role |
|---|---|
| `TamaCore/Protocol.swift` | `HookEvent`, `VisualState` (+ `priority`), `Snapshot`, MTU squeeze |
| `TamaCore/Pages.swift` | `PageKind` (the firmware contract), `PageFrame`, `PageHub` — what may be sent, and what is worth resending |
| `TamaCore/Weather.swift` | the weather page frame + the Open-Meteo payloads, as pure functions over bytes |
| `TamaCore/WeatherService.swift` | the weather settings and the fetch schedule — fed `tick(now:)`, owns no timer |
| `TamaCore/SessionStore.swift` | all the logic: hook → per-session state → snapshot |
| `TamaCore/ToolMap.swift` | tool name → `VisualState`, overridable via `~/.tamaclaude/tools.json` |
| `TamaCore/Text.swift` | strip to the board font's charset, shape Thai, then truncate |
| `TamaCore/ThaiShaper.swift` | the Thai cluster walk and glyph-variant choice (ADR-0008) |
| `TamaCore/ThaiTable.swift` | generated from `tools/thai.toml` — never edit |
| `TamaCore/SocketServer.swift` / `HookClient.swift` | Unix socket between `--hook` and the daemon |
| `TamaCore/BLETransport.swift` | CoreBluetooth central + auto-reconnect + board events |
| `TamaCore/WiFiProvisioning.swift` | the Wi-Fi commands and reports that ride the config/event characteristics |
| `TamaCore/LanFrame.swift` | the sealed frame on the wire: nonce, counter, greeting — pure, both directions |
| `TamaCore/LanKey.swift` | the 32-byte LAN key: where it lives, how it is fingerprinted |
| `TamaCore/LanTransport.swift` | the second path: find the board, connect, seal, resend |
| `TamaCore/Failover.swift` | when the second path may open (10 s grace) + the composite transport |
| `TamaCore/Usage{Reader,Writer}.swift` | the `.statusline-usage-cache` contract |
| `TamaCore/UsagePoll.swift` | `--usage-poll`: one claude.ai quota fetch, then exit |
| `TamaCore/UsagePoller.swift` | when to poll and what the last poll said — fed `tick(now:)`, owns no timer |
| `TamaCore/SessionStarter.swift` | when the app may open a session of its own — same shape, plus the guards and what locks it |
| `TamaCore/ChildOutput.swift` | what a child process said, drained off its pipe without blocking it |
| `TamaCore/SessionKeyFile.swift` | writes `~/.tamaclaude/session-key` so it is mode 600 from birth |
| `TamaCore/SessionKeyState.swift` | what the settings window says under the key button — saved is not the same as accepted |
| `TamaCore/{Hook,Statusline}Installer.swift` | writes into `~/.claude/settings.json` |
| `TamaCore/Paths.swift` | the `~/.tamaclaude` paths + `Log` (`settings.json` belongs to `HookInstaller`) |
| `TamaCore/Daemon.swift` | wires it together + 1 s tick |
| `TamaCore/MenuBadge.swift` | what the menu bar icon knows: percent + pace position |
| `TamaCore/PanelText.swift` | what the foot of the popover says (board link, session rows, figure age) |
| `TamaCore/QuotaCard.swift` | what a quota card says: colour level, pace tick, reset line |
| `TamaCore/RefreshControl.swift` | the refresh button's discipline: cooldown, and when opening the panel polls |
| `tamaclaude/MenuBarApp.swift` | the menu bar app **is** the daemon (Bluetooth TCC is per-`.app`) |
| `tamaclaude/PreferencesWindowController.swift` | the settings window: General + Wi-Fi (the gear is down to Settings…/Quit) |
| `tamaclaude/PanelViewController.swift` | the popover: header + gear, the cards, the foot |
| `tamaclaude/QuotaCardView.swift` | how a quota card is drawn (bar, pace tick, palette) |
| `tamaclaude/MenuBadgeImage.swift` | how the menu bar icon is drawn (template vs red) |

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
- **The LAN counter only ever goes up.** A repeated nonce in GCM destroys the confidentiality
  of both frames that used it, so `LanSealer` increments before sealing and the board rejects
  anything not strictly greater than what it has already accepted. The board tells the Mac
  where to continue from when it accepts the connection — neither side stores a counter file.
- **The `sessionKey` is a full-account credential.** File only (`~/.tamaclaude/session-key`,
  mode 600), never argv, never env, never logged, re-read every poll. Not the Keychain: the
  adhoc signature changes cdhash on every build, so the item would prompt on every upgrade.
- **`-v` and `-psn_*` are not modes.** LaunchServices appends `-psn_0_12345`; an app that
  rejects unknown args dies on double-click.
- **`PageKind` is a three-way contract**: `Pages.swift`, `firmware/main/ct_pages.h`, and
  `tools/gen/pages.py`. The raw values travel on the wire, so reordering one side silently
  changes what every frame means. `tamatest` reads the real header to check.
- **One frame per page, and each must fit `Wire.maxPayload` alone** (ADR-0003). A frame is a
  mascot `Snapshot` exactly when it has **no** `g` key — that is what keeps old firmware
  working. `{"g":N,"x":1}` retires a page the user turned off; simply not sending it leaves
  yesterday's figures rotating on the board forever (ADR-0002).
- **The screen jumps back to the mascot on an event *id*, not on a state.** `Snapshot.attention`
  (`"a"`) counts sessions *entering* a needs-human state; the board jumps only when that number
  goes up. Deciding from the state itself yanks the screen back every snapshot for as long as a
  permission prompt sits unanswered, and never jumps for the second session that asks while the
  first is still waiting.
- **Page frames carry a data *age*, not a timestamp**, and the board counts on from there.
  A re-read with identical figures is still sent (the age is the difference); an age that is
  merely ticking is not a change.
- **The `VisualState` enum is a contract with the firmware.** Adding or reordering it means
  changing `ct_model.c`/`ct_mascot.c` too. `tamatest` guards this.

### GATT

```
service  7A9B0001-4C1E-4B6D-9E2A-1D5C3F0A0001
state    ...0002   daemon writes the snapshot here (write with response)
config   ...0003   brightness + Wi-Fi commands + the LAN key — write requires an encrypted link
event    ...0004   board -> host: Wi-Fi scan results and link status (`BoardEvent`)
```

## The second path (LAN)

When BLE has been quiet for 10 s the daemon opens a TCP connection to the board on
port 7333 and sends the same snapshot, sealed with AES-256-GCM under a key it pushed
over the config characteristic. The board finds nothing on its own and **never talks to
claude.ai** — the `sessionKey` stays on the Mac. Details and the reasons are in
`DESIGN.md` under "WiFi ▸ ทางเดินที่สอง"; the frame layout must match `ct_lan.c` byte
for byte.

```
[4B len BE][12B nonce][ciphertext][16B tag]     nonce = 4 zero bytes + 8B BE counter
```

## Conventions

- Comments and design docs are in **Thai**; identifiers, commands, and error strings stay in
  English. Existing comments explain *why*, often citing what was tried and rejected — match
  that density rather than describing what the code does.
- Commit subjects are lowercase imperative with a conventional prefix (`feat:`, `fix:`) and
  read as a sentence about the visible effect, e.g. `feat: give the sky half the screen and
  cap cards at two`.
- The board font has no em dash — anything crossing BLE goes through `Text.swift` first.
  Thai does cross, but only shaped: `Text.fit` picks the glyph variants (ADR-0008), and it is
  the only door, so nothing else may hand a raw Thai string to the wire.

## Agent skills

### Issue tracker

Issues live as GitHub issues in `thaitop/tamaclaude`, managed with the `gh` CLI. External PRs
are not a triage surface. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical roles use their default label strings (`needs-triage`, `needs-info`,
`ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
