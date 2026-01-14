# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

demo.nvim is a Neovim plugin for giving code presentations. It highlights lines/selections with different colors, records every state change, and allows stepping through states like a slideshow. Bookmarks mark important states for quick navigation.

## Architecture

```
lua/demo/
  init.lua       -- Main API, setup(), delegates to modules
  highlight.lua  -- Extmark-based line/character highlighting
  state.lua      -- State recording, bookmarks, persistence
  storage.lua    -- File I/O, jj/git repo detection
  presenter.lua  -- Slideshow navigation (steps and bookmarks)
plugin/demo.lua  -- User commands and keymaps
```

**Data flow**: highlight.lua manages extmarks -> state.lua records every change to disk -> presenter.lua navigates through recorded states

**Storage format**: `.demo/{filepath}.demo` - all states in one file:
```
# demo.nvim states for lua/demo/init.lua
# Format: [index:bookmark @ commit] or [index @ commit]

[1 @ a1b2c3d]
5-10 DemoHighlight1

[2 @ a1b2c3d]
5-10 DemoHighlight1
15:3-15:20 DemoHighlight2

[3:intro @ a1b2c3d]
5-10 DemoHighlight1
15:3-15:20 DemoHighlight2
20-25 DemoHighlight3
```

- Every highlight change creates a new numbered state
- Bookmarks are labels on states (`:intro` suffix)
- All states across all commits in one file for easy editing

## Key Commands

**Highlighting:**
- `:DemoHighlight [hlgroup]` - Highlight visual selection (v=chars, V=lines)
- `:DemoHighlightLines {range} [hlgroup]` - Highlight line range
- `:DemoClear` - Clear all highlights
- `:DemoBookmark {name}` - Label current state with a bookmark name

**Presenter (navigation):**
- `:DemoStart` / `:DemoStop` / `:DemoToggle` - Control presenter mode
- `:DemoNext` / `:DemoPrev` - Jump between bookmarks
- `:DemoNextStep` / `:DemoPrevStep` - Step through every state
- `:DemoGoto {name|number}` - Jump to bookmark or step number
- `:DemoList` - Show all states and bookmarks

## Keymaps

| Key | Mode | Action |
|-----|------|--------|
| `<leader>dh` | Visual | Highlight selection |
| `<leader>db` | Normal | Bookmark (prompts for name) |
| `<leader>dn` | Normal | Next bookmark |
| `<leader>dp` | Normal | Previous bookmark |
| `<leader>ds` | Normal | Toggle presenter |
| `<leader>dc` | Normal | Clear highlights |
| `<leader>dl` | Normal | List states |
| `<leader>dN` | Normal | Next step (any state) |
| `<leader>dP` | Normal | Previous step (any state) |

## Development

Load plugin locally:
```vim
:set runtimepath+=~/proj/demo.nvim
:lua require('demo').setup()
```

Run tests (when added):
```bash
nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"
```

## VCS: jj preferred

Uses jj for repo root detection, falls back to git:
- `jj root` for repo root (falls back to `git rev-parse --show-toplevel`)
- `git rev-parse HEAD` for commit SHA (stable, unlike jj's `@` which changes on every edit)
