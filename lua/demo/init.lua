local highlight = require('demo.highlight')
local state = require('demo.state')
local storage = require('demo.storage')
local presenter = require('demo.presenter')

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

function M.list()
  local all_states = state.get_all()
  local bookmarks = state.get_bookmarks()
  local pos = state.get_position()

  if #all_states == 0 then
    vim.notify('demo.nvim: No states recorded for this file', vim.log.levels.INFO)
    return
  end

  local filepath = vim.api.nvim_buf_get_name(0)
  local rel_path = storage.get_relative_path(filepath)
  local current_commit = storage.get_commit()

  local lines = {
    'States for ' .. rel_path .. ' (commit: ' .. (current_commit or 'none') .. '):',
    string.format('Total: %d steps, %d bookmarks, current position: %d', #all_states, #bookmarks, pos.position),
    '',
  }

  for i, s in ipairs(all_states) do
    local marker = (i == pos.position) and '>' or ' '
    local bookmark_str = s.bookmark and (' "' .. s.bookmark .. '"') or ''
    local commit_str = s.commit and (' @ ' .. s.commit) or ''
    table.insert(lines, string.format('%s %d.%s%s (%d highlights)', marker, s.index, bookmark_str, commit_str, #s.highlights))
  end

  vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
end

function M.reload()
  return state.reload()
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

  local lines = {
    'Demo.nvim Status:',
    string.format('  VCS: %s', vcs.vcs or 'none'),
    string.format('  Commit: %s', vcs.commit or 'N/A'),
    string.format('  Presenter: %s', pinfo.active and 'active' or 'inactive'),
    string.format('  Position: %d/%d steps', pinfo.position, pinfo.total),
    string.format('  Bookmarks: %d', pinfo.bookmark_count),
  }

  if pinfo.current_state and pinfo.current_state.bookmark then
    table.insert(lines, string.format('  Current bookmark: "%s"', pinfo.current_state.bookmark))
  end

  vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
  return pinfo
end

-- Direct module access
M.highlight_module = highlight
M.state_module = state
M.storage_module = storage
M.presenter_module = presenter

return M
