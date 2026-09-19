# ShotStash

Menu-bar screenshot stash and clipboard history for macOS. One hotkey grabs a selection
(or the full screen) straight to the clipboard and into a temporary stash. Another shows
the last 10 things you copied, images and text alike, so you can see what you're about to
paste. Nothing is written to the Desktop until you ask.

## Why

Shift+Cmd+4 always saves a PNG to the Desktop; copying it takes extra clicks.
Ctrl+Shift+Cmd+4 copies but keeps nothing. ShotStash does both: copy now, save later,
to the Desktop or any folder you choose.

## Hotkeys

| Action | Default |
|---|---|
| Capture selection (Space toggles window mode, Esc cancels) | ⌃⌘4 |
| Capture full screen | ⌃⌘3 |
| Show clipboard history panel | ⌃⌘V |

## Clipboard history

Everything you copy, in any app, lands in the history: images are stashed as PNG files, text
is kept in memory. ⌃⌘V opens a floating panel at the mouse pointer listing the last 10 items
with thumbnails. ↑/↓ or hover to move, ⏎ or click to pick, Esc to close. Picking puts the item
back on the clipboard; then press ⌘V in your app as normal. Image rows also have an eye button
(open in Preview), a save button (save to the default folder) and a Save As… button (choose
folder and filename). Space opens in Preview, ⌘S saves to the default folder, ⇧⌘S is Save As…,
⌫ deletes. Right-click any row for the
same actions. Each save is confirmed with a notification naming the file. Duplicates of the newest item, empty text,
and anything a password manager marks confidential are skipped.

Change them by writing Carbon key codes and modifier bits to UserDefaults, e.g. ⌥⇧⌘4:

    defaults write com.roscodetech.shotstash hotkeySelection -data "$(printf '{"keyCode":21,"modifiers":2816}' | xxd -p | tr -d '\n')"

(modifiers: ⌘ 256, ⇧ 512, ⌥ 2048, ⌃ 4096; add them up). Relaunch afterwards.

## Menu

- Capture Selection / Capture Full Screen / Show Clipboard History
- Save Last Image to <folder> / Save Last Image As… / Save Last Image to Folder… (a chosen folder becomes the new default)
- Recent Clipboard: last 10 items with thumbnails; each has Copy, Delete, and for images Save / Save As… / Save to Folder…
- Default Folder: shows the current one, Change…, Reset to Desktop
- Launch at Login
- Keyboard Shortcuts… (also the ⓘ button in the panel header): a cheat sheet of every shortcut
- Quit

Items live in `~/Library/Caches/com.roscodetech.shotstash/` and are wiped on quit and launch.
Saved files use Apple's naming: `Screenshot 2026-09-19 at 14.52.03.png`, with ` (2)` etc. on collision.

## Install

    make install      # builds, bundles, signs, copies to /Applications, launches

Requires Xcode command line tools (Swift 5.9+). Other targets: `make test`, `make bundle`, `make run`, `make clean`.

From a terminal:

    /Applications/ShotStash.app/Contents/MacOS/ShotStash --launch-at-login on    # or off / status

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
8. Copy text in another app, then ⌃⌘V: the panel lists it; ⏎ closes the panel and ⌘V pastes it.
9. Copy an image in a browser: it appears in the panel with a thumbnail; a screenshot appears once, not twice.
10. Quit: caches folder is empty.

## Development

    swift test        # ShotStashCore unit tests
    swift run ShotStash   # unbundled; notifications are skipped
