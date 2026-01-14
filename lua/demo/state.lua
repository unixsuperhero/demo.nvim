local highlight = require('demo.highlight')
local storage = require('demo.storage')

local M = {}

-- In-memory state cache per file (by relative path)
local state_cache = {}

local function get_filepath(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return vim.api.nvim_buf_get_name(bufnr)
end

local function get_cache_key(filepath)
  return storage.get_relative_path(filepath)
end

local function deep_copy_highlights(highlights)
  local copy = {}
  for _, hl in ipairs(highlights) do
    table.insert(copy, {
      start_line = hl.start_line,
      start_col = hl.start_col,
      end_line = hl.end_line,
      end_col = hl.end_col,
      hlgroup = hl.hlgroup,
    })
  end
  return copy
end

local function highlights_equal(a, b)
  if #a ~= #b then return false end
  for i, hl in ipairs(a) do
    local other = b[i]
    if hl.start_line ~= other.start_line or
       hl.start_col ~= other.start_col or
       hl.end_line ~= other.end_line or
       hl.end_col ~= other.end_col or
       hl.hlgroup ~= other.hlgroup then
      return false
    end
  end
  return true
end

function M.load(bufnr)
  local filepath = get_filepath(bufnr)
  if filepath == '' then return nil end

  local key = get_cache_key(filepath)
  local states = storage.read_states(filepath)

  state_cache[key] = {
    states = states,
    current_index = #states,  -- Start at the last state
  }

  return state_cache[key]
end

function M.save(bufnr)
  local filepath = get_filepath(bufnr)
  if filepath == '' then return nil end

  local key = get_cache_key(filepath)
  local cache = state_cache[key]
  if not cache then return nil end

  return storage.write_states(filepath, cache.states)
end

function M.get_cache(bufnr)
  local filepath = get_filepath(bufnr)
  if filepath == '' then return nil end

  local key = get_cache_key(filepath)
  if not state_cache[key] then
    M.load(bufnr)
  end
  return state_cache[key]
end

-- Record current highlight state (auto-saves to disk)
function M.record(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filepath = get_filepath(bufnr)
  if filepath == '' then return nil end

  local cache = M.get_cache(bufnr)
  if not cache then
    cache = { states = {}, current_index = 0 }
    state_cache[get_cache_key(filepath)] = cache
  end

  local highlights = highlight.get_all(bufnr)
  local new_highlights = deep_copy_highlights(highlights)

  -- Check if this is the same as the current state (avoid duplicates)
  if cache.current_index > 0 then
    local current = cache.states[cache.current_index]
    if current and highlights_equal(current.highlights, new_highlights) then
      return cache.current_index
    end
  end

  -- Get next index
  local max_index = 0
  for _, s in ipairs(cache.states) do
    if s.index > max_index then max_index = s.index end
  end
  local new_index = max_index + 1

  -- Add new state
  local new_state = {
    index = new_index,
    bookmark = nil,
    commit = storage.get_commit(),
    highlights = new_highlights,
  }

  table.insert(cache.states, new_state)
  cache.current_index = #cache.states

  -- Auto-save to disk
  M.save(bufnr)

  return new_index
end

-- Set bookmark on current state
function M.set_bookmark(bufnr, name)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cache = M.get_cache(bufnr)
  if not cache or cache.current_index == 0 then
    vim.notify('demo.nvim: No current state to bookmark', vim.log.levels.WARN)
    return false
  end

  local state = cache.states[cache.current_index]
  if not state then return false end

  state.bookmark = name
  M.save(bufnr)

  local commit_str = state.commit and (' @ ' .. state.commit) or ''
  vim.notify(string.format('demo.nvim: Bookmarked step %d as "%s"%s', state.index, name, commit_str), vim.log.levels.INFO)
  return true
end

-- Remove bookmark from a state
function M.remove_bookmark(bufnr, name)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cache = M.get_cache(bufnr)
  if not cache then return false end

  for _, state in ipairs(cache.states) do
    if state.bookmark == name then
      state.bookmark = nil
      M.save(bufnr)
      vim.notify(string.format('demo.nvim: Removed bookmark "%s"', name), vim.log.levels.INFO)
      return true
    end
  end

  vim.notify(string.format('demo.nvim: Bookmark "%s" not found', name), vim.log.levels.WARN)
  return false
end

-- Get all states
function M.get_all(bufnr)
  local cache = M.get_cache(bufnr)
  return cache and cache.states or {}
end

-- Get bookmarked states only
function M.get_bookmarks(bufnr)
  local cache = M.get_cache(bufnr)
  if not cache then return {} end

  local bookmarks = {}
  for _, state in ipairs(cache.states) do
    if state.bookmark then
      table.insert(bookmarks, state)
    end
  end
  return bookmarks
end

-- Navigate to a specific state index (1-based position in states array)
function M.goto_position(bufnr, position)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cache = M.get_cache(bufnr)
  if not cache then return false end

  if position < 0 or position > #cache.states then
    return false
  end

  cache.current_index = position

  if position == 0 then
    highlight.clear(bufnr)
  else
    local state = cache.states[position]
    highlight.set_all(bufnr, state.highlights)
  end

  return true
end

-- Get current position info
function M.get_position(bufnr)
  local cache = M.get_cache(bufnr)
  if not cache then
    return { position = 0, total = 0, state = nil }
  end

  return {
    position = cache.current_index,
    total = #cache.states,
    state = cache.current_index > 0 and cache.states[cache.current_index] or nil,
  }
end

-- Find position of next/prev bookmark from current position
function M.find_bookmark_position(bufnr, direction)
  local cache = M.get_cache(bufnr)
  if not cache then return nil end

  local current = cache.current_index

  if direction > 0 then
    -- Forward
    for i = current + 1, #cache.states do
      if cache.states[i].bookmark then
        return i
      end
    end
  else
    -- Backward
    for i = current - 1, 1, -1 do
      if cache.states[i].bookmark then
        return i
      end
    end
  end

  return nil
end

function M.reload(bufnr)
  local filepath = get_filepath(bufnr)
  if filepath == '' then return nil end

  local key = get_cache_key(filepath)
  state_cache[key] = nil
  return M.load(bufnr)
end

function M.clear_all(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filepath = get_filepath(bufnr)
  if filepath == '' then return end

  local key = get_cache_key(filepath)
  state_cache[key] = { states = {}, current_index = 0 }
  highlight.clear(bufnr)
  M.save(bufnr)
end

return M
