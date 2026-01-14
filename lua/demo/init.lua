local highlight = require('demo.highlight')
local state = require('demo.state')
local storage = require('demo.storage')
local bookmark = require('demo.bookmark')
local presenter = require('demo.presenter')

local M = {}

M.config = {
  auto_snapshot = true,  -- Automatically snapshot after each highlight change
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
  highlight.setup_highlight_groups()
end

-- Highlighting API
function M.highlight(hlgroup)
  local index = highlight.from_visual(hlgroup)
  if M.config.auto_snapshot then
    state.snapshot()
  end
  return index
end

function M.highlight_lines(start_line, end_line, hlgroup)
  local index = highlight.add(nil, start_line, end_line, hlgroup)
  if M.config.auto_snapshot then
    state.snapshot()
  end
  return index
end

function M.clear()
  highlight.clear()
  if M.config.auto_snapshot then
    state.snapshot()
  end
end

function M.clear_line(line)
  highlight.clear_line(nil, line)
  if M.config.auto_snapshot then
    state.snapshot()
  end
end

-- State history API
function M.undo()
  return state.undo()
end

function M.redo()
  return state.redo()
end

function M.history_info()
  return state.get_history_info()
end

-- Bookmark API
function M.bookmark(name)
  return bookmark.add(nil, name)
end

function M.delete_bookmark(name)
  return bookmark.delete(nil, name)
end

function M.list_bookmarks()
  local bookmarks = bookmark.list()
  if #bookmarks == 0 then
    vim.notify('demo.nvim: No bookmarks for this file/commit', vim.log.levels.INFO)
    return bookmarks
  end

  local vcs_info = storage.get_vcs_info()
  local lines = {
    string.format('Bookmarks for commit %s (%s):', vcs_info.commit or 'uncommitted', vcs_info.vcs or 'none'),
    '',
  }
  for i, bm in ipairs(bookmarks) do
    table.insert(lines, string.format('  %d. %s (%d highlights)', i, bm.name, #bm.highlights))
  end
  vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
  return bookmarks
end

function M.reload_bookmarks()
  return bookmark.reload()
end

-- Presenter API
function M.start()
  return presenter.start()
end

function M.stop()
  return presenter.stop()
end

function M.next()
  return presenter.next()
end

function M.prev()
  return presenter.prev()
end

function M.goto(name_or_index)
  return presenter.goto_bookmark(nil, name_or_index)
end

function M.presenter_info()
  return presenter.get_info()
end

-- VCS info
function M.vcs_info()
  local info = storage.get_vcs_info()
  local lines = {
    string.format('VCS: %s', info.vcs or 'none'),
    string.format('Root: %s', info.root or 'N/A'),
    string.format('Commit: %s', info.commit or 'N/A'),
    string.format('Uncommitted changes: %s', info.has_uncommitted and 'yes' or 'no'),
  }
  vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
  return info
end

-- Direct module access for advanced use
M.highlight_module = highlight
M.state_module = state
M.storage_module = storage
M.bookmark_module = bookmark
M.presenter_module = presenter

return M
