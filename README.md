# Clinder

Clinder is a minimal Finder-like macOS popup for fullscreen workflows.

Finder itself cannot float above a native fullscreen Space. Clinder uses an AppKit floating panel with fullscreen auxiliary Space behavior so it can act as a lightweight file browser overlay.

## Current Prototype

- minimal Finder-style sidebar
- list view for the selected folder
- search within the current folder
- back and forward folder navigation
- right-click context menu with Open, Copy Path, Copy, Cut, and Paste
- Enter or double-click to open files/folders
- Command-C, Command-X, and Command-V for file copy, cut, and paste
- Command-[ and Command-] for back and forward
- Escape to close

## Run

```sh
./script/build_and_run.sh
```

To build, copy the app to `/Applications`, and launch the installed app:

```sh
make run
```

For a launch check:

```sh
./script/build_and_run.sh --verify
```
