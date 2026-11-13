# Changelog

Details for each version are in [docs/releases](docs/releases) and on [GitHub Releases](https://github.com/eddieee-git/mac-app-grabby/releases). 한국어: [CHANGELOG.md](CHANGELOG.md)

## 0.3.2 (unreleased)

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
