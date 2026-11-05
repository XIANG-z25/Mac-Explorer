# Mac Explorer Daily

[简体中文](README.md) · [繁體中文](README.zh-TW.md) · English

A native Swift/AppKit file manager for macOS with familiar Windows 11 Explorer workflows.

[Download the 1.7.0 DMG](https://github.com/XIANG-z25/Mac-Explorer/releases/download/v1.7.0/Mac-Explorer-Daily-1.7.0-mac-arm64.dmg) · [Release notes](https://github.com/XIANG-z25/Mac-Explorer/releases/tag/v1.7.0)

## What's new in 1.7.0

- Right-click a tab to duplicate its folder and selection in a tab next to it.
- Command-click an address-bar breadcrumb, or use its context menu, to open that folder in a new tab. Switch back to resume browsing where you left off.
- In Details view, drag from blank space within a row to select several items.
- Groups lay out immediately when changing icon sizes. Hover over an icon to read the full name beside the pointer.

Daily also supports folders-first sorting, grouping by modification date, batch renaming for files and folders, configurable font size and startup location, and optional SMB reconnection at launch. Connected OneDrive and Box folders can be browsed from the sidebar. Their clients manage syncing and offline availability.

## Installation

Requires Apple Silicon and macOS 13 or later. Quit the old version before updating. Open the DMG and drag **Mac Explorer Daily.app** into Applications. The package is ad-hoc signed and has not been notarized by Apple. Update manually from [this repository's Releases](https://github.com/XIANG-z25/Mac-Explorer/releases/latest), where the SHA-256 checksum is also available.

Based on [qixiaoyu27/Mac-Explorer](https://github.com/qixiaoyu27/Mac-Explorer) and distributed under the [GPL-3.0 license](LICENSE). See the [native development guide](native/README.md) for source builds. Use `python3 -I native/scripts/build.py --personal` from the repository root to build the Daily app.
