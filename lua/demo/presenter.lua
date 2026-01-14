local highlight = require('demo.highlight')
local bookmark = require('demo.bookmark')

local M = {}

-- Presenter state per buffer
local presenter_state = {}

local function get_state(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not presenter_state[bufnr] then
    presenter_state[bufnr] = {
      active = false,
      current_index = 0,  -- 0 means "no bookmark applied" (blank state)
    }
  end
  return presenter_state[bufnr]
end

function M.is_active(bufnr)
  return get_state(bufnr).active
end

function M.start(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local state = get_state(bufnr)

  -- Load bookmarks
  local bookmarks = bookmark.load(bufnr)
  if #bookmarks == 0 then
    vim.notify('demo.nvim: No bookmarks found for this file/commit', vim.log.levels.WARN)
    return false
  end

  state.active = true
  state.current_index = 0  -- Start at blank state

  -- Clear any existing highlights to start fresh
  highlight.clear(bufnr)

  vim.notify(string.format('demo.nvim: Presenter started (%d bookmarks). Use :DemoNext to begin.', #bookmarks), vim.log.levels.INFO)
  return true
end

function M.stop(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local state = get_state(bufnr)

  if not state.active then
    vim.notify('demo.nvim: Presenter is not active', vim.log.levels.WARN)
    return false
  end

  state.active = false
  state.current_index = 0
  highlight.clear(bufnr)

  vim.notify('demo.nvim: Presenter stopped', vim.log.levels.INFO)
  return true
end

function M.next(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local state = get_state(bufnr)

  if not state.active then
    vim.notify('demo.nvim: Presenter is not active. Run :DemoStart first.', vim.log.levels.WARN)
    return false
  end

  local bookmarks = bookmark.list(bufnr)
  local total = #bookmarks

  if state.current_index >= total then
    vim.notify('demo.nvim: Already at last bookmark', vim.log.levels.INFO)
    return false
  end

  state.current_index = state.current_index + 1
  local bm = bookmarks[state.current_index]
  highlight.set_all(bufnr, bm.highlights)

  vim.notify(string.format('demo.nvim: [%d/%d] %s', state.current_index, total, bm.name), vim.log.levels.INFO)
  return true
end

function M.prev(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local state = get_state(bufnr)

  if not state.active then
    vim.notify('demo.nvim: Presenter is not active. Run :DemoStart first.', vim.log.levels.WARN)
    return false
  end

  local bookmarks = bookmark.list(bufnr)
  local total = #bookmarks

  if state.current_index <= 0 then
    vim.notify('demo.nvim: Already at beginning (blank state)', vim.log.levels.INFO)
    return false
  end

  state.current_index = state.current_index - 1

  if state.current_index == 0 then
    highlight.clear(bufnr)
    vim.notify(string.format('demo.nvim: [0/%d] (blank state)', total), vim.log.levels.INFO)
  else
    local bm = bookmarks[state.current_index]
    highlight.set_all(bufnr, bm.highlights)
    vim.notify(string.format('demo.nvim: [%d/%d] %s', state.current_index, total, bm.name), vim.log.levels.INFO)
  end

  return true
end

function M.goto_bookmark(bufnr, name_or_index)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local state = get_state(bufnr)

  if not state.active then
    vim.notify('demo.nvim: Presenter is not active. Run :DemoStart first.', vim.log.levels.WARN)
    return false
  end

  local bookmarks = bookmark.list(bufnr)
  local total = #bookmarks
  local target_index

  if type(name_or_index) == 'number' then
    if name_or_index < 0 or name_or_index > total then
      vim.notify(string.format('demo.nvim: Invalid bookmark index %d', name_or_index), vim.log.levels.WARN)
      return false
    end
    target_index = name_or_index
  else
    -- Find by name
    for i, bm in ipairs(bookmarks) do
      if bm.name == name_or_index then
        target_index = i
        break
      end
    end
    if not target_index then
      vim.notify(string.format('demo.nvim: Bookmark "%s" not found', name_or_index), vim.log.levels.WARN)
      return false
    end
  end

  state.current_index = target_index

  if target_index == 0 then
    highlight.clear(bufnr)
    vim.notify(string.format('demo.nvim: [0/%d] (blank state)', total), vim.log.levels.INFO)
  else
    local bm = bookmarks[target_index]
    highlight.set_all(bufnr, bm.highlights)
    vim.notify(string.format('demo.nvim: [%d/%d] %s', target_index, total, bm.name), vim.log.levels.INFO)
  end

  return true
end

function M.get_info(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local state = get_state(bufnr)
  local bookmarks = bookmark.list(bufnr)

  return {
    active = state.active,
    current_index = state.current_index,
    total = #bookmarks,
    current_name = state.current_index > 0 and bookmarks[state.current_index] and bookmarks[state.current_index].name or nil,
  }
end

return M
