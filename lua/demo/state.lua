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
    states = states,           -- All states from file
    current_position = 0,      -- Position in filtered_states (0 = blank)
    filtered_states = {},      -- States for current blob only
    current_blob = nil,        -- Blob hash we're filtered to
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

-- Filter states to current file blob hash and store in cache
function M.filter_to_blob(bufnr)
  local cache = M.get_cache(bufnr)
  if not cache then return {} end

  local filepath = get_filepath(bufnr)
  local blob = storage.get_blob_hash(filepath)
  cache.current_blob = blob
  cache.filtered_states = {}
  cache.current_position = 0

  for _, state in ipairs(cache.states) do
    if state.blob == blob then
      table.insert(cache.filtered_states, state)
    end
  end

  return cache.filtered_states
end

-- Alias for backwards compatibility
M.filter_to_commit = M.filter_to_blob

-- Record current highlight state (auto-saves to disk)
function M.record(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filepath = get_filepath(bufnr)
  if filepath == '' then return nil end

  local cache = M.get_cache(bufnr)
  if not cache then
    cache = { states = {}, current_position = 0, filtered_states = {}, current_blob = nil }
    state_cache[get_cache_key(filepath)] = cache
  end

  local highlights = highlight.get_all(bufnr)
  local new_highlights = deep_copy_highlights(highlights)
  local current_blob = storage.get_blob_hash(filepath)

  -- Ensure filtered_states is populated for current blob
  if cache.current_blob ~= current_blob then
    cache.current_blob = current_blob
    cache.filtered_states = {}
    for _, state in ipairs(cache.states) do
      if state.blob == current_blob then
        table.insert(cache.filtered_states, state)
      end
    end
  end

  -- Check if this is the same as the last state for this blob (avoid duplicates)
  local last_for_blob = nil
  for i = #cache.states, 1, -1 do
    if cache.states[i].blob == current_blob then
      last_for_blob = cache.states[i]
      break
    end
  end

  if last_for_blob and highlights_equal(last_for_blob.highlights, new_highlights) then
    -- Update position to this existing state
    for i, fs in ipairs(cache.filtered_states) do
      if fs.index == last_for_blob.index then
        cache.current_position = i
        break
      end
    end
    return last_for_blob.index
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
    blob = current_blob,
    highlights = new_highlights,
  }

  table.insert(cache.states, new_state)

  -- Also add to filtered_states and update position
  table.insert(cache.filtered_states, new_state)
  cache.current_position = #cache.filtered_states

  -- Auto-save to disk
  M.save(bufnr)

  return new_index
end

-- Set bookmark on current state (in filtered view)
function M.set_bookmark(bufnr, name)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cache = M.get_cache(bufnr)
  if not cache or cache.current_position == 0 or #cache.filtered_states == 0 then
    vim.notify('demo.nvim: No current state to bookmark', vim.log.levels.WARN)
    return false
  end

  local filtered_state = cache.filtered_states[cache.current_position]
  if not filtered_state then return false end

  -- Find and update the actual state in cache.states
  for _, state in ipairs(cache.states) do
    if state.index == filtered_state.index then
      state.bookmark = name
      filtered_state.bookmark = name  -- Update filtered copy too
      break
    end
  end

  M.save(bufnr)

  local blob_str = filtered_state.blob and (' @ ' .. filtered_state.blob) or ''
  vim.notify(string.format('demo.nvim: Bookmarked step %d as "%s"%s', filtered_state.index, name, blob_str), vim.log.levels.INFO)
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
      -- Update filtered states too
      for _, fs in ipairs(cache.filtered_states) do
        if fs.index == state.index then
          fs.bookmark = nil
          break
        end
      end
      vim.notify(string.format('demo.nvim: Removed bookmark "%s"', name), vim.log.levels.INFO)
      return true
    end
  end

  vim.notify(string.format('demo.nvim: Bookmark "%s" not found', name), vim.log.levels.WARN)
  return false
end

-- Get all states (unfiltered)
function M.get_all(bufnr)
  local cache = M.get_cache(bufnr)
  return cache and cache.states or {}
end

-- Get filtered states (current blob only)
function M.get_filtered(bufnr)
  local cache = M.get_cache(bufnr)
  return cache and cache.filtered_states or {}
end

-- Get bookmarked states (from filtered set)
function M.get_bookmarks(bufnr)
  local cache = M.get_cache(bufnr)
  if not cache then return {} end

  local bookmarks = {}
  for _, state in ipairs(cache.filtered_states) do
    if state.bookmark then
      table.insert(bookmarks, state)
    end
  end
  return bookmarks
end

-- Navigate to a specific position in filtered states (0 = blank)
function M.goto_position(bufnr, position)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cache = M.get_cache(bufnr)
  if not cache then return false end

  if position < 0 or position > #cache.filtered_states then
    return false
  end

  cache.current_position = position

  if position == 0 then
    highlight.clear(bufnr)
  else
    local state = cache.filtered_states[position]
    highlight.set_all(bufnr, state.highlights)
  end

  return true
end

-- Get current position info (in filtered view)
function M.get_position(bufnr)
  local cache = M.get_cache(bufnr)
  if not cache then
    return { position = 0, total = 0, state = nil, blob = nil }
  end

  local current_state = nil
  if cache.current_position > 0 and cache.current_position <= #cache.filtered_states then
    current_state = cache.filtered_states[cache.current_position]
  end

  return {
    position = cache.current_position,
    total = #cache.filtered_states,
    state = current_state,
    blob = cache.current_blob,
  }
end

-- Find position of next/prev bookmark from current position (in filtered view)
function M.find_bookmark_position(bufnr, direction)
  local cache = M.get_cache(bufnr)
  if not cache then return nil end

  local current = cache.current_position

  if direction > 0 then
    -- Forward
    for i = current + 1, #cache.filtered_states do
      if cache.filtered_states[i].bookmark then
        return i
      end
    end
  else
    -- Backward
    for i = current - 1, 1, -1 do
      if cache.filtered_states[i].bookmark then
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

-- Named sets functionality

-- Save current states to a named set
function M.save_set(bufnr, set_name)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filepath = get_filepath(bufnr)
  if filepath == '' then return nil end

  local cache = M.get_cache(bufnr)
  if not cache then return nil end

  local set_path = storage.save_set(filepath, set_name, cache.states)
  vim.notify(string.format('demo.nvim: Saved set "%s" (%d states)', set_name, #cache.states), vim.log.levels.INFO)
  return set_path
end

-- Load states from a named set
function M.load_set(bufnr, set_name)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filepath = get_filepath(bufnr)
  if filepath == '' then return nil end

  local states = storage.load_set(filepath, set_name)
  if not states then
    vim.notify(string.format('demo.nvim: Set "%s" not found', set_name), vim.log.levels.WARN)
    return nil
  end

  local key = get_cache_key(filepath)
  state_cache[key] = {
    states = states,
    current_position = 0,
    filtered_states = {},
    current_blob = nil,
  }

  -- Filter to current blob and apply
  M.filter_to_blob(bufnr)
  highlight.clear(bufnr)

  vim.notify(string.format('demo.nvim: Loaded set "%s" (%d states)', set_name, #states), vim.log.levels.INFO)
  return state_cache[key]
end

-- List available sets for current file
function M.list_sets(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filepath = get_filepath(bufnr)
  if filepath == '' then return {} end

  return storage.list_sets(filepath)
end

-- Delete a named set
function M.delete_set(bufnr, set_name)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filepath = get_filepath(bufnr)
  if filepath == '' then return false end

  local result = storage.delete_set(filepath, set_name)
  if result then
    vim.notify(string.format('demo.nvim: Deleted set "%s"', set_name), vim.log.levels.INFO)
  else
    vim.notify(string.format('demo.nvim: Set "%s" not found', set_name), vim.log.levels.WARN)
  end
  return result
end

function M.clear_all(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filepath = get_filepath(bufnr)
  if filepath == '' then return end

  local key = get_cache_key(filepath)
  state_cache[key] = { states = {}, current_position = 0, filtered_states = {}, current_blob = nil }
  highlight.clear(bufnr)
  M.save(bufnr)
end

-- Reset: delete all states for current blob (start over)
function M.reset(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filepath = get_filepath(bufnr)
  if filepath == '' then return false end

  local cache = M.get_cache(bufnr)
  if not cache then return false end

  local current_blob = storage.get_blob_hash(filepath)

  -- Filter out states matching current blob
  local new_states = {}
  for _, state in ipairs(cache.states) do
    if state.blob ~= current_blob then
      table.insert(new_states, state)
    end
  end

  -- Re-index remaining states sequentially
  for i, state in ipairs(new_states) do
    state.index = i
  end

  -- Update cache
  cache.states = new_states
  cache.filtered_states = {}
  cache.current_position = 0
  cache.current_blob = current_blob

  -- Clear visual highlights and save
  highlight.clear(bufnr)
  M.save(bufnr)

  local deleted_count = #cache.states - #new_states + #cache.filtered_states
  vim.notify(string.format('demo.nvim: Reset - deleted all states for blob %s', current_blob or 'none'), vim.log.levels.INFO)
  return true
end

return M
