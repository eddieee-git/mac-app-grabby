# Changelog

Details for each version are in [docs/releases](docs/releases) and on [GitHub Releases](https://github.com/eddieee-git/mac-app-grabby/releases). 한국어: [CHANGELOG.md](CHANGELOG.md)

## Next version

- While the capture or settings window is open, the Grabby menus (File, Edit, Window) show at the top left and Grabby appears in the Dock; closing all windows returns it to the menu bar only

## 0.3.4 (2026-11-19)

- Tab right-click menu (close tab, close other tabs, close all), ⌥-click × to close all
- Automatic installs on by default; **Check for Updates…** installs right away without asking

## 0.3.3 (2026-11-15)

- Automatic update checks are now on by default (stays off if you turned it off); automatic installs are a separate switch (off by default)
- Updates use the updater shared by all five apps: **Check Now** in Settings, and the releases page is used when GitHub's rate limit is hit
- Stronger update checks: installs only after the signature, SHA-256, bundle ID, version, and code signature are verified
- Settings → About links to GitHub, the changelog, problem reports, and other apps
- Menu bar menu order: Settings… → Updates → Getting Started → Quit

## 0.3.2 (2026-11-13)

- Full-screen capture copies right away and adds to tabs without the editor (switch back in Settings, or capture all displays as one image)
- **Undo** in the toast removes a capture that was kept in tabs after closing with Esc
- Delete old captures automatically (1/7/30/90 days, off by default); library size in Settings → About
- Turn on update alerts in Getting Started; a prompt appears right away if an update reset Screen Recording permission
- In-app updates check an Ed25519 signature (`.sig`); the app is signed with the hardened runtime
- The clipboard image for large captures is prepared in the background, so capturing feels lighter

## 0.3.1 (2026-11-12)

- One-click updates: **Install Version…** in the menu downloads, verifies and swaps in the new version
- Closing with Esc or ✕ after selecting an area keeps it in tabs without copying (can be turned off)

## 0.3.0 (2026-11-10)

- QR code reading (⇧⌘6, ⌘R): copies the value and opens web links in your browser
- Default shortcuts moved to ⇧⌘, with a one-click switch to ⌃⌘
- Window capture (⇧⌘4) captures only that window, without overlapping windows
- Large timer countdown with cancel, two-row toolbar, palette colors you can add and reorder
- Restore pinned captures, update alerts (off by default), deletion log (`events.log`)

## 0.2.0 (2026-11-08)

- First release: area, last area, full screen, whiteboard and timer capture, with editing right where you selected
- Copy, save, pin to screen, copy text (OCR), beautify and copy
- Tab window where captures pile up (edit again, search text and notes, ★ keep)
