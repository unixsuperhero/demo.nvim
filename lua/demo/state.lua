local highlight = require('demo.highlight')

local M = {}

-- History per buffer: { [bufnr] = { states = {}, current_index = 0 } }
local history = {}

local function deep_copy(tbl)
  if type(tbl) ~= 'table' then return tbl end
  local copy = {}
  for k, v in pairs(tbl) do
    if type(v) == 'table' then
      copy[k] = deep_copy(v)
    else
      copy[k] = v
    end
  end
  return copy
end

local function get_buffer_history(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not history[bufnr] then
    history[bufnr] = { states = {}, current_index = 0 }
  end
  return history[bufnr]
end

function M.snapshot(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local h = get_buffer_history(bufnr)

  local highlights = highlight.get_all(bufnr)
  -- Deep copy to avoid reference issues
  local state = {}
  for _, hl in ipairs(highlights) do
    table.insert(state, {
      start_line = hl.start_line,
      end_line = hl.end_line,
      hlgroup = hl.hlgroup,
    })
  end

  -- Truncate any redo history
  if h.current_index < #h.states then
    for i = #h.states, h.current_index + 1, -1 do
      table.remove(h.states, i)
    end
  end

  table.insert(h.states, state)
  h.current_index = #h.states

  return h.current_index
end

function M.get_current(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local h = get_buffer_history(bufnr)
  if h.current_index > 0 and h.current_index <= #h.states then
    return deep_copy(h.states[h.current_index])
  end
  return {}
end

function M.get_at(bufnr, index)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local h = get_buffer_history(bufnr)
  if index > 0 and index <= #h.states then
    return deep_copy(h.states[index])
  end
  return nil
end

function M.goto_state(bufnr, index)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local h = get_buffer_history(bufnr)

  if index < 0 or index > #h.states then
    return false
  end

  h.current_index = index

  if index == 0 then
    highlight.clear(bufnr)
  else
    highlight.set_all(bufnr, h.states[index])
  end

  return true
end

function M.undo(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local h = get_buffer_history(bufnr)
  if h.current_index > 0 then
    return M.goto_state(bufnr, h.current_index - 1)
  end
  return false
end

function M.redo(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local h = get_buffer_history(bufnr)
  if h.current_index < #h.states then
    return M.goto_state(bufnr, h.current_index + 1)
  end
  return false
end

function M.get_history_info(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local h = get_buffer_history(bufnr)
  return {
    total = #h.states,
    current = h.current_index,
  }
end

function M.clear_history(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  history[bufnr] = { states = {}, current_index = 0 }
end

function M.apply_state(bufnr, state)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  highlight.set_all(bufnr, state)
end

return M
