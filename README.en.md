# Mini Clipboard (macOS)

[English](README.en.md) | [中文](README.md)

Lightweight, elegant macOS clipboard manager. Capture history, browse by timeline, pinboards and groups, direct paste, quick paste, instant search, and more — helping you paste content across apps faster.

## Features
- History capture: Automatically collects text, links, images, files, colors, and more
- Timeline browsing: Horizontal list, vertical list, and grid layouts; quick preview and rename
- Pinboards and groups: Create/rename/color pinboards; history and pins are separate
- One-click favorites: Use the star on a card to keep it indefinitely in the built-in Favorites board
- Direct paste: Double-click to quick copy/paste, with plain-text or preserved HTML/RTF formatting
- Search and filters: Keyword + type/source-app filters, instant-as-you-type search
- Settings and shortcuts: History retention period, layout toggle, shortcut mapping, panel position adjustment

## Keys
- Panel: `⇧+⌘+P` (Configurable)
- Direct Paste: Double-click or Enter
- Force Plain Text: `Shift+Enter`
- Force Preserved Formatting: `Option+Enter`
- Quick Preview: Space
- Move: Arrow keys
- Search: Any key
- Multi-select: `Shift` or `Command` + Click

## UI Preview
![List layout](docs/image/list_mode.png)
![Grid layout](docs/image/grid_mode.png)
Watch the demo video: 👇
[![Demo Video](docs/image/cover.png)](https://youtu.be/ID8JOoSwYC8)

## Installation Guide
1. Download the latest `.dmg` from [Releases](https://github.com/PGshen/mini-clipboard/releases).
2. Open the downloaded file and drag `Mini Clipboard.app` into the `Applications` folder.
3. For the first installation, you need to allow apps from known developers.
   - Open "System Settings" → "Privacy & Security" → "Security"
   - Click "Open Anyway" or confirm allowing `Mini Clipboard`.
4. Launch `Mini Clipboard` from the "Applications" folder.
![Installation Settings](docs/image/install_setting.png)

## Requirements
- macOS 12+ (Apple Silicon native)
- Xcode 15+, Swift 5.9+

## Quick Start
### Using Xcode
- Open `MiniClipboard.xcodeproj`, select the `mini-clipboard` Scheme, and run directly.

### Using Makefile
- Build Debug:
  - `make build`
- Generate distributable `.app`:
  - `make app` → outputs to `dist/Mini Clipboard.app`
- Generate unsigned DMG:
  - `make dmg-unsigned` → outputs to `dist/Mini-Clipboard.dmg`
- Full signing and notarization (requires developer certificate/account):
  - Configure `DEVELOPER_ID`, `TEAM_ID`, `APPLE_ID`, `APP_PASSWORD`, or `NOTARY_PROFILE`
  - `make package-signed`
- Clean:
  - `make clean`

### App Icon (Optional)
- Place source image `logo.png` under `public/` to generate iconset and `logo.icns` in one step:
  - `make icon`
- If ImageMagick is installed, rounded-rectangle icons are generated; otherwise square.

## Permissions & Privacy
- Direct paste and sequential paste stack require enabling "Accessibility" permissions. The first run will guide you to open System Settings.
- History retention defaults to 1 day and can be adjusted in settings; expired unpinned history is automatically cleaned, while items added to a Pinboard are retained.

## Default Shortcuts (Configurable in Settings)
- Panel: `⇧+⌘+P`

## Project Structure
- `App/`: App entry, delegate, and panel window control
- `Services/`: Clipboard monitoring, hotkeys, paste, search, privacy rules
- `Storage/`: History index and settings persistence
- `UI/`: Panel root view, history timeline, settings page, and controls
- `Models/`: Data models and enums
- `dist/`: Build artifacts (`.app` and `.dmg`)
- `public/`: App icon assets
- `docs/`: Requirements and technical design docs

## Developer Notes
- Local data directory: `~/Library/Application Support/MiniClipboard/` (index and persistent content).
- Key modules:
  - Clipboard monitor (`Services/ClipboardMonitor.swift`)
  - Direct/stack paste (`Services/PasteService.swift`)
  - Hotkey registration (`Services/HotkeyService.swift`)
  - History indexing and cleanup (`Storage/IndexStore.swift`)
  - Timeline UI (`UI/HistoryTimelineView.swift`)

## License
- Open-source license: Apache License 2.0 (see `LICENSE`).
