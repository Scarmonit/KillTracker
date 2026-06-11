# Kill Tracker

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![WoW Classic](https://img.shields.io/badge/WoW-Classic%20Era%20%7C%20Anniversary%20%7C%20MoP%20Classic-blue)
![Lua](https://img.shields.io/badge/Lua-5.1-000080.svg)

A lightweight **World of Warcraft Classic** addon that tracks every mob you kill — by name, creature type, and grand total — and turns it into real grinding analytics: kills/XP/gold **per hour**, **time-to-level**, per-mob **loot drops**, **reputation** progress, a live HUD, and a minimap button.

No external dependencies to install — the required libraries are bundled.

---

## Features

- **Kill tracking** — counts every mob you, your pet, or your minions land the killing blow on, grouped by **name** and **creature type**, with a lifetime grand total. Per-character.
- **Tooltip kill count** — hover any mob to see how many you've killed.
- **Accurate rates (sliding window)** — XP/hr, gold/hr, kills/hr and rep/hr are computed over a recent window (default 10 min), so travel/looting/AFK don't skew them. Self-corrects for rested XP.
- **Time-to-level** — live ETA, **per-mob XP average** so the estimate matches the mob you're actually farming.
- **Mobs to Next Level** — estimates how many more mobs you need to level, based on the XP of the mob you're currently killing, and updates in real time as you switch to higher/lower-XP mobs. Shown in the **HUD**, the main window, and the **title-bar hover tooltip**; toggle it in the options.
- **Gold & loot value** — tracks coin gained plus the vendor value of looted items (locale-independent), shown as gold/hr.
- **Per-mob loot drops** — click any mob to see its drop table with **drop %**, quantity, and **vendor value** per item.
- **Reputation tracking** — for your watched faction: rep/hr, **time-to-next standing**, and **kills-to-next**.
- **Rare / Elite / Boss flagging** — special kills are color-coded and counted separately.
- **Deaths counter** — lifetime and per-session.
- **Searchable, sortable list** — filter by name; click column headers to sort.
- **Live HUD** — a compact on-screen readout for grinding sessions; **movable, resizable, and lockable** (state saved).
- **Options panel** — in the Interface/AddOns settings or via `/kt options`: HUD visibility/lock/scale/reset-position, Mobs-to-Next-Level toggle, minimap button, level-up announcements, and pace window.
- **Session history** — each session (kills/XP/gold/time/deaths) is saved so you can compare farming spots.
- **Minimap button / Data Broker** — built on LibDBIcon + LibDataBroker, so it also shows up in Titan Panel, Bazooka, ChocolateBar, etc.

Works on **Classic Era (1.15.x)**, **Anniversary / TBC Classic (2.5.x)**, and **MoP Classic (5.5.x)** — one build, all flavors.

## Screenshots

> _Add a screenshot of the `/kt` window and HUD here (e.g. `docs/window.png`)._

## Installation

### Manual
1. Download the latest release (or click **Code → Download ZIP**).
2. Extract it. Rename the folder to **`KillTracker`** if needed (it must not be `KillTracker-main`).
3. Copy the `KillTracker` folder into your AddOns directory:
   ```
   World of Warcraft\_classic_era_\Interface\AddOns\KillTracker
   ```
   (use `_anniversary_` or `_classic_` for those flavors).
4. The folder must contain `KillTracker.toc`, `KillTracker.lua`, and the `Libs` folder.
5. Restart WoW (or `/reload`) and enable **Kill Tracker** at the character screen's AddOns list.

### Git
```sh
git clone https://github.com/Scarmonit/KillTracker.git
```
…then move/symlink the cloned folder into your AddOns directory as above.

## Usage

| Command | What it does |
|---------|--------------|
| `/kt` | Toggle the main window |
| `/kt hud` | Toggle the live session HUD |
| `/kt lock` | Lock/unlock the HUD (move + resize) |
| `/kt options` | Open the options panel |
| `/kt minimap` | Show/hide the minimap button |
| `/kt history` | Open saved session history |
| `/kt window N` | Set the pace window for XP/hr & ETA (minutes) |
| `/kt show` | Print the top 10 + rates to chat |
| `/kt session` | Save & reset the current session |
| `/kt reset` | Wipe all data (with confirmation) |

Tips:
- Click a mob in the window to open its **drops** panel.
- Turn on enemy nameplates (`V`) for the best creature-type and rare/elite coverage.
- Drop percentages only accrue from kills made **after** you install the addon.

## Development

This project is linted with [luacheck](https://github.com/lunarmodules/luacheck) and has an in-game unit-test suite for [wowUnit](https://github.com/Mirroar/wowUnit).

```sh
# static analysis (uses .luacheckrc)
luacheck KillTracker.lua KillTracker_Tests.lua
```

In-game tests (install wowUnit first):
```
/wu KillTracker_Tests
```
The "Recording" tests snapshot and restore your saved data, so running them is non-destructive.

## Project structure

```
KillTracker/
├── KillTracker.toc          # addon manifest (multi-flavor interface lines)
├── Core.lua                 # namespace, utils, widgets, event + refresh systems
├── Data.lua                 # saved variables, session state, recording, handlers
├── Stats.lua                # rolling-window rates, projections, sorting
├── UI.lua                   # main window + tooltip
├── Drops.lua                # per-mob loot panel
├── History.lua              # session-history panel
├── HUD.lua                  # movable/resizable/lockable live HUD
├── Options.lua              # Interface options panel
├── Minimap.lua              # LibDataBroker + LibDBIcon broker
├── Commands.lua             # slash command dispatcher
├── KillTracker_Tests.lua    # wowUnit test suite
├── .luacheckrc              # luacheck config (WoW API declared)
├── Libs/                    # embedded libraries (LibStub, CallbackHandler,
│                            #   LibDataBroker-1.1, LibDBIcon-1.0)
├── .github/workflows/       # CI: luacheck on push/PR
├── LICENSE · CHANGELOG.md · README.md
```

## Contributing

Issues and pull requests are welcome. Please keep `luacheck` clean (`0 warnings / 0 errors`) and add/adjust tests in `KillTracker_Tests.lua` for new logic.

## License

[MIT](LICENSE) © Scarmonit. Bundled libraries retain their own licenses (see `LICENSE` and the files under `Libs/`).
