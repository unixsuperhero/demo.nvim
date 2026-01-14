local highlight = require('demo.highlight')
local storage = require('demo.storage')

local M = {}

-- In-memory cache of bookmarks per file
local bookmark_cache = {}

local function get_filepath(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return vim.api.nvim_buf_get_name(bufnr)
end

local function get_cache_key(filepath)
  local commit = storage.get_commit_id() or 'uncommitted'
  local rel_path = storage.get_relative_path(filepath)
  return commit .. ':' .. rel_path
end

function M.load(bufnr)
  local filepath = get_filepath(bufnr)
  if filepath == '' then return {} end

  local key = get_cache_key(filepath)
  local bookmarks = storage.read_bookmarks(filepath)
  bookmark_cache[key] = bookmarks
  return bookmarks
end

function M.save(bufnr)
  local filepath = get_filepath(bufnr)
  if filepath == '' then return nil end

  local key = get_cache_key(filepath)
  local bookmarks = bookmark_cache[key] or {}
  return storage.write_bookmarks(filepath, bookmarks)
end

function M.add(bufnr, name)
  local filepath = get_filepath(bufnr)
  if filepath == '' then
    vim.notify('demo.nvim: Cannot bookmark unsaved buffer', vim.log.levels.ERROR)
    return false
  end

  local key = get_cache_key(filepath)
  if not bookmark_cache[key] then
    M.load(bufnr)
  end

  -- Get current highlights
  local highlights = highlight.get_all(bufnr)
  local state = {}
  for _, hl in ipairs(highlights) do
    table.insert(state, {
      start_line = hl.start_line,
      end_line = hl.end_line,
      hlgroup = hl.hlgroup,
    })
  end

  -- Check if bookmark with this name exists
  local bookmarks = bookmark_cache[key] or {}
  local found = false
  for i, bm in ipairs(bookmarks) do
    if bm.name == name then
      bookmarks[i].highlights = state
      found = true
      break
    end
  end

  if not found then
    table.insert(bookmarks, {
      name = name,
      highlights = state,
    })
  end

  bookmark_cache[key] = bookmarks
  M.save(bufnr)

  local action = found and 'Updated' or 'Created'
  vim.notify(string.format('demo.nvim: %s bookmark "%s"', action, name), vim.log.levels.INFO)
  return true
end

function M.delete(bufnr, name)
  local filepath = get_filepath(bufnr)
  if filepath == '' then return false end

  local key = get_cache_key(filepath)
  if not bookmark_cache[key] then
    M.load(bufnr)
  end

  local bookmarks = bookmark_cache[key] or {}
  for i, bm in ipairs(bookmarks) do
    if bm.name == name then
      table.remove(bookmarks, i)
      bookmark_cache[key] = bookmarks
      M.save(bufnr)
      vim.notify(string.format('demo.nvim: Deleted bookmark "%s"', name), vim.log.levels.INFO)
      return true
    end
  end

  vim.notify(string.format('demo.nvim: Bookmark "%s" not found', name), vim.log.levels.WARN)
  return false
end

function M.get(bufnr, name)
  local filepath = get_filepath(bufnr)
  if filepath == '' then return nil end

  local key = get_cache_key(filepath)
  if not bookmark_cache[key] then
    M.load(bufnr)
  end

  local bookmarks = bookmark_cache[key] or {}
  for _, bm in ipairs(bookmarks) do
    if bm.name == name then
      return bm
    end
  end
  return nil
end

function M.get_at_index(bufnr, index)
  local filepath = get_filepath(bufnr)
  if filepath == '' then return nil end

  local key = get_cache_key(filepath)
  if not bookmark_cache[key] then
    M.load(bufnr)
  end

  local bookmarks = bookmark_cache[key] or {}
  return bookmarks[index]
end

function M.list(bufnr)
  local filepath = get_filepath(bufnr)
  if filepath == '' then return {} end

  local key = get_cache_key(filepath)
  if not bookmark_cache[key] then
    M.load(bufnr)
  end

  return bookmark_cache[key] or {}
end

function M.count(bufnr)
  return #M.list(bufnr)
end

function M.apply(bufnr, name_or_index)
  local bookmark
  if type(name_or_index) == 'number' then
    bookmark = M.get_at_index(bufnr, name_or_index)
  else
    bookmark = M.get(bufnr, name_or_index)
  end

  if not bookmark then
    vim.notify(string.format('demo.nvim: Bookmark "%s" not found', tostring(name_or_index)), vim.log.levels.WARN)
    return false
  end

  highlight.set_all(bufnr, bookmark.highlights)
  return true
end

function M.reload(bufnr)
  local filepath = get_filepath(bufnr)
  if filepath == '' then return {} end

  local key = get_cache_key(filepath)
  bookmark_cache[key] = nil
  return M.load(bufnr)
end

return M
