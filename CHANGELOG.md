# Changelog

All notable changes to this project are documented here. This project loosely
follows [Keep a Changelog](https://keepachangelog.com/) and semantic-ish
versioning by addon `## Version`.

## [9.0]
### Added
- **LibDataBroker + LibDBIcon** minimap button — now interops with Titan Panel,
  Bazooka, ChocolateBar and other broker displays.
- Click-to-sort column headers (Mob / Type / Kills) with direction arrows.
- Vendor-value column and session total value in the per-mob drops panel.
- `db.version` + migration stub for safe future schema changes.
### Changed
- Loot value is now read from the loot window (`GetItemInfo`) instead of parsing
  chat — fixes gold/loot tracking on non-English clients.
- KPH and gold/hr now use the same sliding window as XP/hr and rep/hr (consistent
  "per hour" semantics).
- `RefreshAll` is throttled (coalesced via a short timer) for less GC churn while
  grinding.

## [8.0]
### Added
- Reputation tracking for the watched faction: rep/hr, time-to-next, kills-to-next.
- Session history: saved sessions viewable via `/kt history`.
- Per-mob average XP, used to refine mobs-to-level.

## [7.0]
### Added
- `.luacheckrc` config and an in-game wowUnit test suite.
- Moved the project into a proper repository layout.

## [6.0]
### Fixed
- Per-mob loot drops now record reliably (robust loot-source attribution).
### Changed
- Modernized the UI (opaque dark theme, dividers, zebra rows, search placeholder).

## [5.0]
### Added
- Per-mob loot drops with drop %, deaths counter, rare/elite/boss flagging.

## [4.0]
### Added
- Configurable pace window, rested-XP display, level-up summary.
### Changed
- Time-to-level now uses an accurate sliding-window rate.

## [3.0]
### Added
- XP/hr + time-to-level + mobs-to-go, gold/hr + loot value, search box, minimap button.

## [2.0]
### Added
- Tooltip kill counts, session stats + kills-per-hour, live HUD.

## [1.0]
### Added
- Initial release: tracks mobs killed by name and creature type with a grand total.
