local highlight = require('demo.highlight')
local state = require('demo.state')
local storage = require('demo.storage')
local presenter = require('demo.presenter')
local edit = require('demo.edit')

local M = {}

M.config = {
  auto_record = true,  -- Automatically record state after each highlight change
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
  highlight.setup_highlight_groups()
end

-- Highlighting API
function M.highlight(hlgroup)
  local index = highlight.from_visual(hlgroup)
  if M.config.auto_record then
    state.record()
  end
  return index
end

function M.highlight_lines(start_line, end_line, hlgroup)
  local index = highlight.add_lines(nil, start_line, end_line, hlgroup)
  if M.config.auto_record then
    state.record()
  end
  return index
end

function M.clear()
  highlight.clear()
  if M.config.auto_record then
    state.record()
  end
end

function M.clear_line(line)
  highlight.clear_line(nil, line)
  if M.config.auto_record then
    state.record()
  end
end

-- Bookmark API (labels on states)
function M.bookmark(name)
  return state.set_bookmark(nil, name)
end

function M.delete_bookmark(name)
  return state.remove_bookmark(nil, name)
end

function M.reset()
  return state.reset()
end

function M.edit()
  return edit.open()
end

function M.list()
  local all_states = state.get_all()
  local filtered = state.get_filtered()
  local pos = state.get_position()

  local filepath = vim.api.nvim_buf_get_name(0)
  local rel_path = storage.get_relative_path(filepath)
  local current_blob = storage.get_blob_hash(filepath)

  -- Ensure filtered is populated for current blob
  if #filtered == 0 and #all_states > 0 then
    filtered = state.filter_to_blob()
    pos = state.get_position()
  end

  if #filtered == 0 then
    vim.notify(string.format('demo.nvim: No states for blob %s', current_blob or 'none'), vim.log.levels.INFO)
    return
  end

  -- Count bookmarks in filtered set
  local bookmark_count = 0
  for _, s in ipairs(filtered) do
    if s.bookmark then bookmark_count = bookmark_count + 1 end
  end

  local lines = {
    'States for ' .. rel_path,
    string.format('Blob: %s (%d steps, %d bookmarks)', current_blob or 'none', #filtered, bookmark_count),
    '',
  }

  -- Build a set of current state indices for quick lookup
  local current_state_index = pos.state and pos.state.index or nil

  for i, s in ipairs(filtered) do
    local is_current_state = (s.index == current_state_index)
    local marker = is_current_state and '>' or ' '
    local bookmark_str = s.bookmark and (' "' .. s.bookmark .. '"') or ''
    table.insert(lines, string.format('%s %d.%s (%d highlights)', marker, i, bookmark_str, #s.highlights))
  end

  table.insert(lines, '')
  table.insert(lines, '(> = current state)')

  vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
end

function M.reload()
  highlight.clear()
  local cache = state.reload()
  if cache then
    -- Reset position to 0 (blank) and filter to current blob
    state.filter_to_blob()
    cache.current_position = 0
  end
  return cache
end

-- Presenter API
function M.start()
  return presenter.start()
end

function M.stop()
  return presenter.stop()
end

function M.toggle()
  return presenter.toggle()
end

function M.next()
  return presenter.next()
end

function M.prev()
  return presenter.prev()
end

function M.next_step()
  return presenter.next_step()
end

function M.prev_step()
  return presenter.prev_step()
end

function M.goto(name_or_index)
  return presenter.goto_bookmark(nil, name_or_index)
end

function M.info()
  local pinfo = presenter.get_info()
  local vcs = storage.get_vcs_info()
  local all_states = state.get_all()
  local filepath = vim.api.nvim_buf_get_name(0)
  local blob = storage.get_blob_hash(filepath)

  local lines = {
    'Demo.nvim Status:',
    string.format('  VCS: %s', vcs.vcs or 'none'),
    string.format('  File blob: %s', blob or 'N/A'),
    string.format('  Presenter: %s', pinfo.active and 'active' or 'inactive'),
    string.format('  Steps (this blob): %d/%d', pinfo.position, pinfo.total),
    string.format('  Steps (all blobs): %d', #all_states),
    string.format('  Bookmarks (this blob): %d', pinfo.bookmark_count),
  }

  if pinfo.current_state and pinfo.current_state.bookmark then
    table.insert(lines, string.format('  Current bookmark: "%s"', pinfo.current_state.bookmark))
  end

  vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
  return pinfo
end

-- Named sets API
function M.save_set(name)
  return state.save_set(nil, name)
end

function M.load_set(name)
  return state.load_set(nil, name)
end

function M.list_sets()
  return state.list_sets()
end

function M.delete_set(name)
  return state.delete_set(nil, name)
end

-- Direct module access
M.highlight_module = highlight
M.state_module = state
M.storage_module = storage
M.presenter_module = presenter
M.edit_module = edit

return M
