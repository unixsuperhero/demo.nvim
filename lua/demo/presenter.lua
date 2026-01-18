local highlight = require('demo.highlight')
local state = require('demo.state')

local M = {}

-- Presenter state per buffer
local presenter_state = {}

-- Buffer-local mappings for presenter mode
local presenter_mappings = {
  { 'n', 'j', '<cmd>DemoNext<cr>', 'Next bookmark' },
  { 'n', 'k', '<cmd>DemoPrev<cr>', 'Previous bookmark' },
  { 'n', 'l', '<cmd>DemoNextStep<cr>', 'Next step' },
  { 'n', 'h', '<cmd>DemoPrevStep<cr>', 'Previous step' },
}

local function set_mappings(bufnr)
  for _, map in ipairs(presenter_mappings) do
    vim.keymap.set(map[1], map[2], map[3], { buffer = bufnr, desc = 'Demo: ' .. map[4] })
  end
end

local function unset_mappings(bufnr)
  for _, map in ipairs(presenter_mappings) do
    pcall(vim.keymap.del, map[1], map[2], { buffer = bufnr })
  end
end

local function get_state(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not presenter_state[bufnr] then
    presenter_state[bufnr] = {
      active = false,
    }
  end
  return presenter_state[bufnr]
end

function M.is_active(bufnr)
  return get_state(bufnr).active
end

function M.start(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local pstate = get_state(bufnr)

  -- Load states from disk and filter to current blob
  state.load(bufnr)
  local filtered = state.filter_to_blob(bufnr)

  if #filtered == 0 then
    local pos = state.get_position(bufnr)
    vim.notify(string.format('demo.nvim: No states for current blob (blob: %s)', pos.blob or 'none'), vim.log.levels.WARN)
    return false
  end

  pstate.active = true
  set_mappings(bufnr)

  -- Start at position 0 (blank)
  state.goto_position(bufnr, 0)

  local bookmarks = state.get_bookmarks(bufnr)
  local pos = state.get_position(bufnr)
  vim.notify(string.format('demo.nvim: Presenter started @ %s (%d steps, %d bookmarks)', pos.blob or 'none', #filtered, #bookmarks), vim.log.levels.INFO)
  return true
end

function M.stop(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local pstate = get_state(bufnr)

  if not pstate.active then
    vim.notify('demo.nvim: Presenter is not active', vim.log.levels.WARN)
    return false
  end

  pstate.active = false
  unset_mappings(bufnr)
  highlight.clear(bufnr)

  vim.notify('demo.nvim: Presenter stopped', vim.log.levels.INFO)
  return true
end

function M.toggle(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if M.is_active(bufnr) then
    return M.stop(bufnr)
  else
    return M.start(bufnr)
  end
end

-- Next step (any state)
function M.next_step(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local pstate = get_state(bufnr)

  if not pstate.active then
    vim.notify('demo.nvim: Presenter is not active. Run :DemoStart first.', vim.log.levels.WARN)
    return false
  end

  local pos = state.get_position(bufnr)
  if pos.position >= pos.total then
    vim.notify('demo.nvim: Already at last step', vim.log.levels.INFO)
    return false
  end

  state.goto_position(bufnr, pos.position + 1)
  pos = state.get_position(bufnr)

  local bookmark_str = pos.state and pos.state.bookmark and (' "' .. pos.state.bookmark .. '"') or ''
  vim.notify(string.format('demo.nvim: Step %d/%d%s', pos.position, pos.total, bookmark_str), vim.log.levels.INFO)
  return true
end

-- Previous step (any state)
function M.prev_step(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local pstate = get_state(bufnr)

  if not pstate.active then
    vim.notify('demo.nvim: Presenter is not active. Run :DemoStart first.', vim.log.levels.WARN)
    return false
  end

  local pos = state.get_position(bufnr)
  if pos.position <= 0 then
    vim.notify('demo.nvim: Already at beginning', vim.log.levels.INFO)
    return false
  end

  state.goto_position(bufnr, pos.position - 1)
  pos = state.get_position(bufnr)

  if pos.position == 0 then
    vim.notify(string.format('demo.nvim: Step 0/%d (blank)', pos.total), vim.log.levels.INFO)
  else
    local bookmark_str = pos.state and pos.state.bookmark and (' "' .. pos.state.bookmark .. '"') or ''
    vim.notify(string.format('demo.nvim: Step %d/%d%s', pos.position, pos.total, bookmark_str), vim.log.levels.INFO)
  end
  return true
end

-- Next bookmark
function M.next(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local pstate = get_state(bufnr)

  if not pstate.active then
    vim.notify('demo.nvim: Presenter is not active. Run :DemoStart first.', vim.log.levels.WARN)
    return false
  end

  local next_pos = state.find_bookmark_position(bufnr, 1)
  if not next_pos then
    vim.notify('demo.nvim: No more bookmarks ahead', vim.log.levels.INFO)
    return false
  end

  state.goto_position(bufnr, next_pos)
  local pos = state.get_position(bufnr)
  local bookmarks = state.get_bookmarks(bufnr)

  -- Find which bookmark number this is
  local bookmark_num = 0
  for i, bm in ipairs(bookmarks) do
    if bm.index == pos.state.index then
      bookmark_num = i
      break
    end
  end

  vim.notify(string.format('demo.nvim: Bookmark %d/%d "%s" (step %d)', bookmark_num, #bookmarks, pos.state.bookmark, pos.position), vim.log.levels.INFO)
  return true
end

-- Previous bookmark
function M.prev(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local pstate = get_state(bufnr)

  if not pstate.active then
    vim.notify('demo.nvim: Presenter is not active. Run :DemoStart first.', vim.log.levels.WARN)
    return false
  end

  local prev_pos = state.find_bookmark_position(bufnr, -1)
  if not prev_pos then
    -- No more bookmarks before - go to position 0 (blank/clear)
    local pos = state.get_position(bufnr)
    if pos.position <= 0 then
      vim.notify('demo.nvim: Already at beginning', vim.log.levels.INFO)
      return false
    end
    state.goto_position(bufnr, 0)
    local bookmarks = state.get_bookmarks(bufnr)
    pos = state.get_position(bufnr)
    vim.notify(string.format('demo.nvim: Step 0/%d (blank)', pos.total), vim.log.levels.INFO)
    return true
  end

  state.goto_position(bufnr, prev_pos)
  local pos = state.get_position(bufnr)
  local bookmarks = state.get_bookmarks(bufnr)

  -- Find which bookmark number this is
  local bookmark_num = 0
  for i, bm in ipairs(bookmarks) do
    if bm.index == pos.state.index then
      bookmark_num = i
      break
    end
  end

  vim.notify(string.format('demo.nvim: Bookmark %d/%d "%s" (step %d)', bookmark_num, #bookmarks, pos.state.bookmark, pos.position), vim.log.levels.INFO)
  return true
end

-- Go to specific bookmark by name or step by number
function M.goto_bookmark(bufnr, name_or_index)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local pstate = get_state(bufnr)

  if not pstate.active then
    vim.notify('demo.nvim: Presenter is not active. Run :DemoStart first.', vim.log.levels.WARN)
    return false
  end

  local all_states = state.get_all(bufnr)

  if type(name_or_index) == 'number' then
    -- Go to step number
    if name_or_index < 0 or name_or_index > #all_states then
      vim.notify(string.format('demo.nvim: Invalid step %d', name_or_index), vim.log.levels.WARN)
      return false
    end
    state.goto_position(bufnr, name_or_index)
  else
    -- Find by bookmark name
    local found = false
    for i, s in ipairs(all_states) do
      if s.bookmark == name_or_index then
        state.goto_position(bufnr, i)
        found = true
        break
      end
    end
    if not found then
      vim.notify(string.format('demo.nvim: Bookmark "%s" not found', name_or_index), vim.log.levels.WARN)
      return false
    end
  end

  local pos = state.get_position(bufnr)
  if pos.position == 0 then
    vim.notify(string.format('demo.nvim: Step 0/%d (blank)', pos.total), vim.log.levels.INFO)
  else
    local bookmark_str = pos.state and pos.state.bookmark and (' "' .. pos.state.bookmark .. '"') or ''
    vim.notify(string.format('demo.nvim: Step %d/%d%s', pos.position, pos.total, bookmark_str), vim.log.levels.INFO)
  end
  return true
end

function M.get_info(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local pstate = get_state(bufnr)
  local pos = state.get_position(bufnr)
  local bookmarks = state.get_bookmarks(bufnr)

  return {
    active = pstate.active,
    position = pos.position,
    total = pos.total,
    current_state = pos.state,
    bookmark_count = #bookmarks,
  }
end

return M
