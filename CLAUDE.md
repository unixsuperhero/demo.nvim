# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

demo.nvim is a Neovim plugin for giving code presentations. It highlights lines/selections with different colors and allows stepping through bookmarked states like a slideshow.

## Architecture

```
lua/demo/
  init.lua       -- Main API, setup(), delegates to modules
  highlight.lua  -- Extmark-based line highlighting
  state.lua      -- In-memory undo/redo history
  storage.lua    -- File I/O, jj/git commit detection
  bookmark.lua   -- Named state snapshots
  presenter.lua  -- Slideshow navigation
plugin/demo.lua  -- User commands
```

**Data flow**: highlight.lua manages extmarks -> state.lua snapshots changes -> bookmark.lua saves to disk via storage.lua -> presenter.lua navigates bookmarks

**Storage format**: `.demo/{commit_hash}/{filepath}.txt` - simple text, one bookmark per line:
```
name|start:col-end:col:hlgroup|start:col-end:col:hlgroup|...
```

## Key Commands

- `:DemoHighlight [hlgroup]` - Highlight visual selection
- `:DemoHighlightLines {range} [hlgroup]` - Highlight line range
- `:DemoBookmark {name}` - Save current state
- `:DemoStart` / `:DemoStop` - Enter/exit presenter mode
- `:DemoNext` / `:DemoPrev` - Navigate slides
- `:DemoList` - Show bookmarks
- `:DemoReload` - Reload after manual bookmark file edit

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

Uses jj for commit detection, falls back to git:
- `jj log --no-graph -r @ -T 'commit_id'` for commit hash
- `jj root` for repo root
- Bookmarks are stored per-commit so presentations stay consistent
