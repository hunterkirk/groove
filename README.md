# Groove

A distraction-free terminal-based word processor inspired by WordGrinder. Built with Crystal and ncurses.

## Features

- **Word-centric editing** - Designed for writing prose, not code
- **Soft word wrap** - Text wraps at 80 columns on word boundaries
- **Centered text** - Text displayed in the middle of the screen
- **Menu-driven interface** - Press ESC to access menus
- **Auto-save** - Automatically saves every 60 seconds
- **Word/character count** - Status bar shows document statistics

## Controls

### Navigation

| Key | Action |
|-----|--------|
| Arrow Keys | Move cursor |
| Ctrl+A | Move to beginning of line |
| Ctrl+E | Move to end of line |

### Editing

| Key | Action |
|-----|--------|
| Type | Insert text |
| Enter | New line |
| Backspace | Delete character |
| Delete | Delete character at cursor |

### Menu

| Key | Action |
|-----|--------|
| ESC | Open menu |
| Up/Down | Navigate menu |
| Enter | Select menu item |

### Quick Actions

| Key | Action |
|-----|--------|
| Ctrl+S | Quick save |

## Menu Options

- **Open** - Open an existing file
- **Save** - Save current file
- **Save As** - Save with new filename
- **Quit** - Exit editor (prompts if unsaved changes)

## Installation

### From Release

Download the latest release for your platform from the [releases page](https://github.com/hunterkirk/groove/releases).

### Build from Source

Requires [Crystal](https://crystal-lang.org/) and ncurses.

```bash
git clone https://github.com/hunterkirk/groove.git
cd groove
shards install
crystal build --release src/groove.cr -o groove
```

## Usage

```bash
# Open a file
./groove myfile.txt

# Create a new file
./groove
```

## Status Bar

The bottom of the screen shows:
- Filename (with `*` if modified)
- Word count
- Character count

## Building Releases

```bash
# Create a version tag to trigger GitHub Actions builds
git tag v1.0.0
git push origin v1.0.0
```

This will automatically build and release binaries for:
- Linux (x64)
- macOS (arm64)
- macOS (x64)
- Windows (x64)

## License

MIT
