# Mac Explorer Daily

[简体中文](README.md) · [繁體中文](README.zh-TW.md) · English

A native Swift/AppKit file manager for macOS with familiar Windows 11 Explorer workflows.

[Download the 1.7.0 DMG](https://github.com/XIANG-z25/Mac-Explorer/releases/download/v1.7.0/Mac-Explorer-Daily-1.7.0-mac-arm64.dmg) · [Release notes](https://github.com/XIANG-z25/Mac-Explorer/releases/tag/v1.7.0)

## Daily 1.7.8 (build 2) vs. upstream 1.7.1

The `zx/daily-native` branch merges [upstream 1.7.1](https://github.com/qixiaoyu27/Mac-Explorer/commit/68a4677df9f6ba7b54e947577ded3ebd932e9357). Daily uses its own app identifier and retains preferences from previous Daily installations. **Build 1.7.8 from source. The published DMG is 1.7.0.**

- Mounted external drives, including Mounty volumes, appear under **This PC** and can be safely ejected from the sidebar. Read-only mounts are indicated. NTFS write access depends on the installed driver.
- Same-volume moves avoid copying when supported, including regular files on Mounty NTFS, and protect existing destination files. Active copies and moves share one window with per-task progress, speed, and cancellation.
- Duplicate tabs, open breadcrumbs in new tabs, drag-select from blank space in Details rows, regroup immediately when switching icon views, and hover to see full filenames beside the pointer.
- Use search filters without a keyword, and return to the folder listing when the last filter is cleared. The sidebar merges duplicate entries for the same cloud folder. Their clients manage syncing and offline availability.
- Large selections avoid repeated volume checks. The Details pane reuses its text preview to reduce layout allocations when switching files.

From the repository root, run `python3 -I native/scripts/build.py --personal` and copy `native/output/personal/Mac Explorer Daily.app` to Applications. See the [native build guide](native/README.md#构建和打开).

## What's included in the 1.7.0 release

- Right-click a tab to duplicate its folder and selection in a tab next to it.
- Command-click an address-bar breadcrumb, or use its context menu, to open that folder in a new tab. Switch back to resume browsing where you left off.
- In Details view, drag from blank space within a row to select several items.
- Groups lay out immediately when changing icon sizes. Hover over an icon to read the full name beside the pointer.

Daily also supports folders-first sorting, grouping by modification date, batch renaming for files and folders, configurable font size and startup location, and optional SMB reconnection at launch. Connected OneDrive and Box folders can be browsed from the sidebar. Their clients manage syncing and offline availability.

## Installation

Requires Apple Silicon and macOS 13 or later. Quit the old version before updating. Open the DMG and drag **Mac Explorer Daily.app** into Applications. The package is ad-hoc signed and has not been notarized by Apple. Update manually from [this repository's Releases](https://github.com/XIANG-z25/Mac-Explorer/releases/latest), where the SHA-256 checksum is also available.

Based on [qixiaoyu27/Mac-Explorer](https://github.com/qixiaoyu27/Mac-Explorer) and distributed under the [GPL-3.0 license](LICENSE). See the [native development guide](native/README.md) for source builds. Use `python3 -I native/scripts/build.py --personal` from the repository root to build the Daily app.
