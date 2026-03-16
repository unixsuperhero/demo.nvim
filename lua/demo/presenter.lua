local highlight = require('demo.highlight')
local state = require('demo.state')

local M = {}

-- Presenter state per buffer
local presenter_state = {}

-- Sidebar state per buffer: { bufnr, winnr }
local sidebar_state = {}

-- Buffer-local mappings for presenter mode
local presenter_mappings = {
  { 'n', 'j', '<cmd>DemoNext<cr>', 'Next bookmark' },
  { 'n', 'k', '<cmd>DemoPrev<cr>', 'Previous bookmark' },
  { 'n', 'l', '<cmd>DemoNextStep<cr>', 'Next step' },
  { 'n', 'h', '<cmd>DemoPrevStep<cr>', 'Previous step' },
  { 'n', 'q', '<cmd>DemoStop<cr>', 'Stop presenter' },
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

-- Scroll the window so the first highlighted line is centered
local function scroll_to_first_highlight(bufnr)
  local pos = state.get_position(bufnr)
  if not pos.state or not pos.state.highlights or #pos.state.highlights == 0 then
    return
  end

  local min_line = math.huge
  for _, hl in ipairs(pos.state.highlights) do
    if hl.start_line < min_line then
      min_line = hl.start_line
    end
  end

  if min_line == math.huge then return end

  local target_line = min_line + 1  -- extmarks are 0-indexed, cursor is 1-indexed
  local wins = vim.fn.win_findbuf(bufnr)
  if #wins == 0 then return end

  local win = wins[1]
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  target_line = math.min(target_line, line_count)

  -- Only scroll if the target line is not already visible
  local top = vim.fn.line('w0', win)
  local bot = vim.fn.line('w$', win)
  if target_line >= top and target_line <= bot then return end

  local col = vim.api.nvim_win_get_cursor(win)[2]
  vim.api.nvim_win_set_cursor(win, { target_line, col })
  vim.api.nvim_win_call(win, function()
    vim.cmd('normal! zz')
  end)
end

local function update_sidebar(bufnr)
  local sb = sidebar_state[bufnr]
  if not sb then return end

  -- Self-clean if the window was closed manually
  if not vim.api.nvim_buf_is_valid(sb.bufnr) or not vim.api.nvim_win_is_valid(sb.winnr) then
    sidebar_state[bufnr] = nil
    return
  end

  local pos = state.get_position(bufnr)
  local lines = {}

  if pos.state then
    if pos.state.bookmark then
      table.insert(lines, '# ' .. pos.state.bookmark)
      table.insert(lines, '')
    end
    if pos.state.description and pos.state.description ~= '' then
      for _, line in ipairs(vim.split(pos.state.description, '\n', { plain = true })) do
        table.insert(lines, line)
      end
    end
  end

  vim.bo[sb.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(sb.bufnr, 0, -1, false, lines)
  vim.bo[sb.bufnr].modifiable = false
end

local function open_sidebar(bufnr)
  local sb_bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[sb_bufnr].buftype = 'nofile'
  vim.bo[sb_bufnr].bufhidden = 'wipe'
  vim.bo[sb_bufnr].swapfile = false
  vim.bo[sb_bufnr].modifiable = false

  -- Open a right split from the source buffer's window
  local source_win = nil
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      source_win = win
      break
    end
  end
  if source_win then
    vim.api.nvim_set_current_win(source_win)
  end

  vim.cmd('botright vsplit')
  local sb_winnr = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(sb_winnr, sb_bufnr)
  vim.api.nvim_win_set_width(sb_winnr, 50)
  vim.wo[sb_winnr].winfixwidth = true
  vim.wo[sb_winnr].wrap = true
  vim.wo[sb_winnr].linebreak = true
  vim.wo[sb_winnr].number = false
  vim.wo[sb_winnr].relativenumber = false
  vim.wo[sb_winnr].signcolumn = 'no'
  vim.wo[sb_winnr].cursorline = false

  -- Return focus to source window
  if source_win then
    vim.api.nvim_set_current_win(source_win)
  end

  sidebar_state[bufnr] = { bufnr = sb_bufnr, winnr = sb_winnr }
end

local function close_sidebar(bufnr)
  local sb = sidebar_state[bufnr]
  if not sb then return end
  if vim.api.nvim_win_is_valid(sb.winnr) then
    vim.api.nvim_win_close(sb.winnr, true)
  end
  if vim.api.nvim_buf_is_valid(sb.bufnr) then
    vim.api.nvim_buf_delete(sb.bufnr, { force = true })
  end
  sidebar_state[bufnr] = nil
end

-- Ensure states are loaded and filtered for the buffer; returns false if none found.
local function ensure_loaded(bufnr)
  local cache = state.get_cache(bufnr)  -- auto-loads from disk if needed
  if not cache then return false end
  if #cache.filtered_states == 0 and not cache.bypass_blob then
    state.filter_to_blob(bufnr)
    cache = state.get_cache(bufnr)
    if #cache.filtered_states == 0 then
      vim.notify('demo.nvim: No states for current file', vim.log.levels.WARN)
      return false
    end
  end
  return true
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

  -- Load states from disk and filter to current blob, unless already loaded
  -- from an explicit path (bypass_blob flag skips re-loading and re-filtering)
  local cache = state.get_cache(bufnr)
  if not (cache and cache.bypass_blob) then
    state.load(bufnr)
  end
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
  close_sidebar(bufnr)

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

  if not ensure_loaded(bufnr) then return false end

  local pos = state.get_position(bufnr)
  if pos.position >= pos.total then
    vim.notify('demo.nvim: Already at last step', vim.log.levels.INFO)
    return false
  end

  state.goto_position(bufnr, pos.position + 1)
  scroll_to_first_highlight(bufnr)
  update_sidebar(bufnr)
  pos = state.get_position(bufnr)

  local bookmark_str = pos.state and pos.state.bookmark and (' "' .. pos.state.bookmark .. '"') or ''
  vim.notify(string.format('demo.nvim: Step %d/%d%s', pos.position, pos.total, bookmark_str), vim.log.levels.INFO)
  return true
end

-- Previous step (any state)
function M.prev_step(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if not ensure_loaded(bufnr) then return false end

  local pos = state.get_position(bufnr)
  if pos.position <= 0 then
    vim.notify('demo.nvim: Already at beginning', vim.log.levels.INFO)
    return false
  end

  state.goto_position(bufnr, pos.position - 1)
  scroll_to_first_highlight(bufnr)
  update_sidebar(bufnr)
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

  if not ensure_loaded(bufnr) then return false end

  local next_pos = state.find_bookmark_position(bufnr, 1)
  if not next_pos then
    vim.notify('demo.nvim: No more bookmarks ahead', vim.log.levels.INFO)
    return false
  end

  state.goto_position(bufnr, next_pos)
  scroll_to_first_highlight(bufnr)
  update_sidebar(bufnr)
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

  if not ensure_loaded(bufnr) then return false end

  local prev_pos = state.find_bookmark_position(bufnr, -1)
  if not prev_pos then
    -- No more bookmarks before - go to position 0 (blank/clear)
    local pos = state.get_position(bufnr)
    if pos.position <= 0 then
      vim.notify('demo.nvim: Already at beginning', vim.log.levels.INFO)
      return false
    end
    state.goto_position(bufnr, 0)
    scroll_to_first_highlight(bufnr)
    update_sidebar(bufnr)
    local bookmarks = state.get_bookmarks(bufnr)
    pos = state.get_position(bufnr)
    vim.notify(string.format('demo.nvim: Step 0/%d (blank)', pos.total), vim.log.levels.INFO)
    return true
  end

  state.goto_position(bufnr, prev_pos)
  scroll_to_first_highlight(bufnr)
  update_sidebar(bufnr)
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

  if not ensure_loaded(bufnr) then return false end

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

  scroll_to_first_highlight(bufnr)
  update_sidebar(bufnr)
  local pos = state.get_position(bufnr)
  if pos.position == 0 then
    vim.notify(string.format('demo.nvim: Step 0/%d (blank)', pos.total), vim.log.levels.INFO)
  else
    local bookmark_str = pos.state and pos.state.bookmark and (' "' .. pos.state.bookmark .. '"') or ''
    vim.notify(string.format('demo.nvim: Step %d/%d%s', pos.position, pos.total, bookmark_str), vim.log.levels.INFO)
  end
  return true
end

function M.start_sidebar(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  open_sidebar(bufnr)
  local ok = M.start(bufnr)
  if ok then update_sidebar(bufnr) end
  return ok
end

function M.toggle_sidebar(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if M.is_active(bufnr) then
    close_sidebar(bufnr)
    return M.stop(bufnr)
  else
    return M.start_sidebar(bufnr)
  end
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
