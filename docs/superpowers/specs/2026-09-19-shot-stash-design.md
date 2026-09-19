# ShotStash — design spec

Date: 2026-09-19
Status: approved (chat), pre-implementation

## Problem

On macOS, Shift+Cmd+4 always writes a PNG to the Desktop. Getting the image
onto the clipboard afterwards takes extra steps (open the thumbnail, right
click, Copy Image). Holding Control (Ctrl+Shift+Cmd+4) copies to the clipboard
but then the capture is gone the moment the clipboard changes; there is no way
to decide *later* that you want it as a file, or where that file should go.

## Goal

A hotkey that grabs a selection (or the full screen), puts the image on the
clipboard immediately, and keeps a temporary copy that can be saved on demand
to the Desktop (default) or to any chosen folder. Nothing is written to the
Desktop unless asked.

## Non-goals

- Editing, annotation, OCR, scrolling capture, video recording.
- Cloud upload or sharing.
- Persisting captures across restarts.
- A settings window. Preferences live in `UserDefaults` and in the menu.

## Product decisions (from brainstorming)

| Decision | Choice |
|---|---|
| Vehicle | Native Swift menu-bar app (AppKit), no third-party dependency |
| Post-capture behaviour | Silent: clipboard + stash + notification. Save later from the menu bar |
| History | Last 10 captures, kept as temp files, cleared on quit and on launch |
| Default hotkeys | ⌃⌘4 capture selection, ⌃⌘3 capture full screen (changed from ⌥⇧⌘ on 2026-09-19: four keys felt excessive) |
| Default save folder | `~/Desktop`, changeable via folder picker, remembered |
| Notification | "Copied to clipboard — W×H" with a "Save to Desktop" action button |
| Repo | `Utility/shot-stash`, own git repo, branches `dev`/`dev-stable`/`prod`/`prod-stable` |

## Architecture

Swift Package (`swift-tools-version: 5.9`, macOS 14+ deployment target), one
executable target `ShotStash` and one library target `ShotStashCore` so logic
is unit-testable without launching an app. No Xcode project; `swift build`
produces the binary and `scripts/bundle.sh` wraps it into `ShotStash.app`.

```
shot-stash/
├── Package.swift
├── Makefile                      # build / bundle / install / test / clean
├── scripts/bundle.sh             # binary -> .app bundle, Info.plist, codesign
├── Resources/Info.plist          # LSUIElement=true, bundle id com.roscodetech.shotstash
├── Sources/
│   ├── ShotStashCore/            # pure logic, no AppKit UI
│   │   ├── Capture.swift         # struct Capture { id, fileURL, createdAt, pixelSize }
│   │   ├── CaptureStore.swift    # in-memory ring of ≤10 captures backed by temp files
│   │   ├── SaveNamer.swift       # "Screenshot YYYY-MM-DD at HH.mm.ss.png" + collision suffix
│   │   ├── Settings.swift        # UserDefaults-backed: defaultFolder, hotkeys, launchAtLogin
│   │   └── Hotkey.swift          # struct Hotkey { keyCode, modifiers } + display string
│   └── ShotStash/                # AppKit app
│       ├── main.swift            # NSApplication bootstrap, AppDelegate
│       ├── AppDelegate.swift     # wires services, clears stash on launch/quit
│       ├── HotkeyManager.swift   # Carbon RegisterEventHotKey, no Accessibility perm needed
│       ├── CaptureService.swift  # runs /usr/sbin/screencapture into a temp PNG
│       ├── ClipboardService.swift# NSPasteboard write PNG + TIFF
│       ├── Saver.swift           # copy temp file to destination via SaveNamer
│       ├── NotificationService.swift # UNUserNotificationCenter + "Save to Desktop" action
│       └── MenuBarController.swift   # NSStatusItem + NSMenu, rebuilt on store change
├── Tests/ShotStashCoreTests/
│   ├── CaptureStoreTests.swift
│   ├── SaveNamerTests.swift
│   └── SettingsTests.swift
└── README.md
```

### Data flow

1. Hotkey fires → `CaptureService.capture(mode:)` spawns
   `screencapture -i -x -t png <tmp>` (selection; Space toggles window mode,
   Esc cancels) or `screencapture -x -t png <tmp>` (full screen).
   `-x` suppresses the shutter sound; the system still flashes.
2. On exit, if `<tmp>` exists → read pixel size → `CaptureStore.add(...)`,
   which evicts (and deletes the file of) the oldest beyond 10.
   If `<tmp>` does not exist the user cancelled; nothing happens.
3. `ClipboardService.copy(capture)` writes PNG data and a TIFF representation
   so Finder, browsers, terminals and Claude Code all accept a paste.
4. `NotificationService.notify(capture)` posts "Copied to clipboard — W×H"
   with a "Save to Desktop" action. Silent if authorization is denied.
5. `MenuBarController.rebuild()` refreshes the menu from the store.

Saving: `Saver.save(capture, to: folder)` → `SaveNamer.name(for: date, in:
folder)` → `FileManager.copyItem`. The temp file stays in the stash after a
save so the same capture can be saved to a second location.

### Temp storage

`~/Library/Caches/com.roscodetech.shotstash/<uuid>.png`. On launch, any files
in that folder are deleted (leftovers from a crash). On
`applicationWillTerminate` the store is cleared and files removed.

### Menu

```
Capture Selection            ⌃⌘4
Capture Full Screen          ⌃⌘3
─────────────────────────────
Save Last to Desktop                (title shows folder name, e.g. "Save Last to Screenshots")
Save Last to Folder…
Recent Captures            ▸  [thumb] 14:52:03 — 1024×768  ▸ Copy / Save to <default> / Save to Folder… / Delete
                               …
                               ─────
                               Clear All
─────────────────────────────
Default Folder: Desktop    ▸  Change… / Reset to Desktop
Launch at Login            ✓
─────────────────────────────
Quit ShotStash                ⌘Q
```

"Save Last …" items are disabled when the stash is empty. Thumbnails are
NSImages resized to 64 px height.

### Settings (UserDefaults, suite = bundle id)

| Key | Type | Default |
|---|---|---|
| `defaultFolder` | String (path) | `~/Desktop` |
| `hotkeySelection` | `{keyCode:Int, modifiers:UInt}` | keyCode 21 (`4`), ⌃⌘ |
| `hotkeyFullScreen` | same | keyCode 20 (`3`), ⌃⌘ |
| `launchAtLogin` | Bool | false (uses `SMAppService.mainApp`) |

If `defaultFolder` no longer exists at save time, fall back to `~/Desktop`
and reset the setting.

### Permissions

- **Screen Recording**: required for `screencapture` launched by the app. macOS
  prompts on first capture. The app must be signed with a stable identity so the
  grant survives rebuilds. `bundle.sh` signs with
  `Apple Development: ROSCOE KERBY (GWL7DRF898)` when present, falling back to
  ad-hoc (`-`) with a README note that ad-hoc re-prompts after each rebuild.
- **Notifications**: requested on launch; denial is tolerated.
- No Accessibility permission (Carbon hotkeys do not need it).

### Error handling

- `screencapture` non-zero exit with no file → treated as cancel, no alert.
- Non-zero exit *with* a file → keep the file (it happens on some displays).
- Copy failure (destination not writable) → `NSAlert` with the error and the
  destination path.
- Hotkey registration failure (conflict) → log + menu still works; hotkey
  item title gets "(unavailable)".

### Build, sign, install

```
make build     # swift build -c release
make bundle    # build + scripts/bundle.sh -> build/ShotStash.app
make install   # bundle + copy to /Applications (replaces existing), open it
make test      # swift test (ShotStashCore)
make clean
```

## Testing

- **Unit (automated)**: `CaptureStore` eviction order and file deletion,
  `SaveNamer` format and `(2)`, `(3)` collision suffixes, `Settings`
  defaults and round-trip, `Hotkey` display string.
- **Manual (checklist in README)**: hotkey fires, Esc cancels leaves no
  file, paste works in Preview/Claude Code, Save Last to Desktop produces
  correctly named file, folder picker remembers choice, notification
  action saves, quit clears cache folder.

---

# Addendum 2026-09-19: clipboard history

Approved in chat. The stash generalizes from "recent screenshots" to "recent clipboard items".

## Decisions

| Decision | Choice |
|---|---|
| Item kinds | image (PNG file in the cache folder + pixel size) and text |
| Depth | 10, newest first; session only (wiped on quit and launch) |
| Pick action | put the item on the clipboard and close; user presses ⌘V (no Accessibility permission) |
| Panel hotkey | ⌃⌘V, configurable like the others (`hotkeyHistory` in UserDefaults) |
| Skipped content | empty/whitespace-only text; pasteboards flagged `org.nspasteboard.ConcealedType` or `org.nspasteboard.TransientType`; exact duplicate of the newest item; writes made by ShotStash itself |

## Changes

- `Capture`/`CaptureStore` → `ClipItem`/`ClipStore`. `ClipItem.content` is `.image(fileURL:width:height:)` or `.text(String)`. Store gains `addImage`, `addText` (returns nil on duplicate and deletes nothing), `latestImage`, `moveToTop`.
- New `ClipboardWatcher` (app layer): polls `NSPasteboard.general.changeCount` every 0.5 s on the main run loop; ignores the change count `ClipboardService` last wrote.
- New `HistoryPanel` (app layer): non-activating floating `NSPanel` at the mouse location, 360 pt wide, one row per item (64 pt thumbnail or two lines of text, plus HH:mm:ss). ↑/↓ move, ⏎ or click selects, Esc or losing key status closes. Selecting calls `ClipboardService.copy(item)` and `store.moveToTop(item)`.
- Menu: "Show Clipboard History ⌃⌘V" under the capture items; "Save Last Image to <folder>" / "Save Last Image to Folder…" (enabled when any image exists); "Recent Clipboard" submenu lists all items, save actions only on images.
- Screenshot flow unchanged; the notification is still only for captures.
