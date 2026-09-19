# ShotStash

Menu-bar screenshot stash for macOS. One hotkey grabs a selection (or the full screen)
straight to the clipboard and into a temporary stash. Nothing is written to the Desktop
until you ask.

## Why

Shift+Cmd+4 always saves a PNG to the Desktop; copying it takes extra clicks.
Ctrl+Shift+Cmd+4 copies but keeps nothing. ShotStash does both: copy now, save later,
to the Desktop or any folder you choose.

## Hotkeys

| Action | Default |
|---|---|
| Capture selection (Space toggles window mode, Esc cancels) | ⌃⌘4 |
| Capture full screen | ⌃⌘3 |

Change them by writing Carbon key codes and modifier bits to UserDefaults, e.g. ⌥⇧⌘4:

    defaults write com.roscodetech.shotstash hotkeySelection -data "$(printf '{"keyCode":21,"modifiers":2816}' | xxd -p | tr -d '\n')"

(modifiers: ⌘ 256, ⇧ 512, ⌥ 2048, ⌃ 4096; add them up). Relaunch afterwards.

## Menu

- Capture Selection / Capture Full Screen
- Save Last to <folder> / Save Last to Folder… (the chosen folder becomes the new default)
- Recent Captures: last 10 with thumbnails; each has Copy, Save, Save to Folder…, Delete
- Default Folder: shows the current one, Change…, Reset to Desktop
- Launch at Login
- Quit

Captures live in `~/Library/Caches/com.roscodetech.shotstash/` and are wiped on quit and launch.
Saved files use Apple's naming: `Screenshot 2026-09-19 at 14.52.03.png`, with ` (2)` etc. on collision.

## Install

    make install      # builds, bundles, signs, copies to /Applications, launches

Requires Xcode command line tools (Swift 5.9+). Other targets: `make test`, `make bundle`, `make run`, `make clean`.

## Permissions

- **Screen & System Audio Recording**: macOS asks on the first capture. Grant it for ShotStash
  in System Settings › Privacy & Security, then relaunch the app.
- **Notifications**: optional. Enables the "Copied to clipboard" banner with a Save button.
- No Accessibility permission is needed.

The bundle is signed with an Apple Development identity when one is on the keychain, so the
Screen Recording grant survives rebuilds. With ad-hoc signing (`SHOTSTASH_SIGN_IDENTITY=-`)
macOS asks again after every `make install`.

## Manual test checklist

1. ⌃⌘4, select a region, paste into Preview (File › New from Clipboard).
2. ⌃⌘4 then Esc: no file appears in the caches folder.
3. ⌃⌘3: full screen on the clipboard.
4. Save Last to Desktop twice: `Screenshot … .png` and `Screenshot … (2).png`.
5. Save Last to Folder… → pick Downloads → menu titles switch to Downloads.
6. Recent Captures shows thumbnails newest first; Delete and Clear All work.
7. Notification banner appears; its Save button writes the file.
8. Quit: caches folder is empty.

## Development

    swift test        # ShotStashCore unit tests
    swift run ShotStash   # unbundled; notifications are skipped
