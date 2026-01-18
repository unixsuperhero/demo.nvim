local highlight = require('demo.highlight')
local state = require('demo.state')
local storage = require('demo.storage')

local M = {}

-- Track edit buffers: edit_bufnr -> { source_bufnr, original_position, augroup }
local edit_buffers = {}

-- Format a highlight for display (compact)
local function format_highlight(hl)
  if hl.end_col == -1 then
    if hl.start_line == hl.end_line then
      return string.format('%d %s', hl.start_line, hl.hlgroup)
    else
      return string.format('%d-%d %s', hl.start_line, hl.end_line, hl.hlgroup)
    end
  else
    return string.format('%d:%d-%d:%d %s',
      hl.start_line, hl.start_col, hl.end_line, hl.end_col, hl.hlgroup)
  end
end

-- Parse a highlight from display format
local function parse_highlight(str)
  str = vim.trim(str)
  if str == '' then return nil end

  -- Try character range: "5:3-10:20 HlGroup"
  local s_line, s_col, e_line, e_col, hlgroup = str:match('^(%d+):(%d+)-(%d+):(%d+)%s+(%S+)$')
  if s_line then
    return {
      start_line = tonumber(s_line),
      start_col = tonumber(s_col),
      end_line = tonumber(e_line),
      end_col = tonumber(e_col),
      hlgroup = hlgroup,
    }
  end

  -- Try line range: "5-10 HlGroup"
  local start_l, end_l, hl = str:match('^(%d+)-(%d+)%s+(%S+)$')
  if start_l then
    return {
      start_line = tonumber(start_l),
      start_col = 0,
      end_line = tonumber(end_l),
      end_col = -1,
      hlgroup = hl,
    }
  end

  -- Try single line: "5 HlGroup"
  local single_l, single_hl = str:match('^(%d+)%s+(%S+)$')
  if single_l then
    local ln = tonumber(single_l)
    return {
      start_line = ln,
      start_col = 0,
      end_line = ln,
      end_col = -1,
      hlgroup = single_hl,
    }
  end

  return nil
end

-- Convert state to display line: "1  5-10 DemoHighlight1, 15:3-15:20 DemoHighlight2"
-- With bookmark: "3:intro  5-10 DemoHighlight1"
local function state_to_line(s)
  local prefix
  if s.bookmark then
    prefix = string.format('%d:%s', s.index, s.bookmark)
  else
    prefix = string.format('%d', s.index)
  end

  local hl_strs = {}
  for _, hl in ipairs(s.highlights) do
    table.insert(hl_strs, format_highlight(hl))
  end

  if #hl_strs == 0 then
    return prefix .. '  (empty)'
  end
  return prefix .. '  ' .. table.concat(hl_strs, ', ')
end

-- Parse display line back to state (without blob, that's preserved separately)
local function line_to_state(line, blob)
  -- Parse: "1  highlights..." or "1:bookmark  highlights..."
  local prefix, rest = line:match('^([^%s]+)%s%s(.*)$')
  if not prefix then
    -- Try without highlights
    prefix = line:match('^([^%s]+)%s*$')
    rest = '(empty)'
  end
  if not prefix then return nil end

  local index, bookmark
  local idx_str, bm = prefix:match('^(%d+):(.+)$')
  if idx_str then
    index = tonumber(idx_str)
    bookmark = bm
  else
    index = tonumber(prefix)
    bookmark = nil
  end

  if not index then return nil end

  -- Parse highlights
  local highlights = {}
  if rest and rest ~= '(empty)' then
    for hl_str in rest:gmatch('[^,]+') do
      local hl = parse_highlight(hl_str)
      if hl then
        table.insert(highlights, hl)
      end
    end
  end

  return {
    index = index,
    bookmark = bookmark,
    blob = blob,
    highlights = highlights,
  }
end

-- Render states to buffer lines
function M.render(edit_bufnr)
  local info = edit_buffers[edit_bufnr]
  if not info then return end

  local cache = state.get_cache(info.source_bufnr)
  if not cache then return end

  local lines = {}
  for _, s in ipairs(cache.filtered_states) do
    table.insert(lines, state_to_line(s))
  end

  if #lines == 0 then
    lines = { '# No states for current blob. Add highlights first.' }
  end

  vim.bo[edit_bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(edit_bufnr, 0, -1, false, lines)
  vim.bo[edit_bufnr].modifiable = true
  vim.bo[edit_bufnr].modified = false
end

-- Parse buffer lines back to states
function M.parse(edit_bufnr)
  local info = edit_buffers[edit_bufnr]
  if not info then return {} end

  local cache = state.get_cache(info.source_bufnr)
  if not cache then return {} end

  local lines = vim.api.nvim_buf_get_lines(edit_bufnr, 0, -1, false)
  local new_states = {}
  local blob = cache.current_blob

  for _, line in ipairs(lines) do
    if not line:match('^#') and vim.trim(line) ~= '' then
      local s = line_to_state(line, blob)
      if s then
        table.insert(new_states, s)
      end
    end
  end

  return new_states
end

-- Save changes from edit buffer
function M.save(edit_bufnr)
  local info = edit_buffers[edit_bufnr]
  if not info then return false end

  local cache = state.get_cache(info.source_bufnr)
  if not cache then return false end

  local new_filtered_states = M.parse(edit_bufnr)

  -- Re-index the new states sequentially
  for i, s in ipairs(new_filtered_states) do
    s.index = i
  end

  -- Remove old states for this blob from cache.states
  local current_blob = cache.current_blob
  local other_states = {}
  for _, s in ipairs(cache.states) do
    if s.blob ~= current_blob then
      table.insert(other_states, s)
    end
  end

  -- Add new states at the end, with re-indexed numbers
  -- First, find max index from other states
  local max_index = 0
  for _, s in ipairs(other_states) do
    if s.index > max_index then max_index = s.index end
  end

  -- Re-number the new states starting after max_index
  for i, s in ipairs(new_filtered_states) do
    s.index = max_index + i
  end

  -- Combine
  for _, s in ipairs(new_filtered_states) do
    table.insert(other_states, s)
  end

  -- Sort by index
  table.sort(other_states, function(a, b) return a.index < b.index end)

  -- Update cache
  cache.states = other_states
  cache.filtered_states = new_filtered_states

  -- Reset position to 0 if it's out of bounds
  if cache.current_position > #new_filtered_states then
    cache.current_position = #new_filtered_states
  end

  -- Save to disk
  state.save(info.source_bufnr)

  vim.bo[edit_bufnr].modified = false
  vim.notify('demo.nvim: States saved', vim.log.levels.INFO)
  return true
end

-- Preview highlights from current line
function M.preview_line(edit_bufnr, line_nr)
  local info = edit_buffers[edit_bufnr]
  if not info then return end

  local lines = vim.api.nvim_buf_get_lines(edit_bufnr, line_nr - 1, line_nr, false)
  if #lines == 0 then return end

  local line = lines[1]
  if line:match('^#') or vim.trim(line) == '' then
    -- Comment or empty line, clear preview
    highlight.clear(info.source_bufnr)
    return
  end

  local cache = state.get_cache(info.source_bufnr)
  if not cache then return end

  local s = line_to_state(line, cache.current_blob)
  if s then
    highlight.set_all(info.source_bufnr, s.highlights)
  else
    highlight.clear(info.source_bufnr)
  end
end

-- Close edit buffer and restore original state
function M.close(edit_bufnr)
  local info = edit_buffers[edit_bufnr]
  if not info then return end

  -- Delete autocmds
  if info.augroup then
    vim.api.nvim_del_augroup_by_id(info.augroup)
  end

  -- Restore original position highlights
  local cache = state.get_cache(info.source_bufnr)
  if cache then
    state.goto_position(info.source_bufnr, info.original_position)
  end

  -- Focus source buffer window if it exists
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == info.source_bufnr then
      vim.api.nvim_set_current_win(win)
      break
    end
  end

  -- Clean up
  edit_buffers[edit_bufnr] = nil

  -- Delete edit buffer
  if vim.api.nvim_buf_is_valid(edit_bufnr) then
    vim.api.nvim_buf_delete(edit_bufnr, { force = true })
  end
end

-- Add auto-generated bookmark to current line
function M.add_bookmark(edit_bufnr)
  local info = edit_buffers[edit_bufnr]
  if not info then return end

  local line_nr = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(edit_bufnr, 0, -1, false)
  local current_line = lines[line_nr]

  if not current_line or current_line:match('^#') or vim.trim(current_line) == '' then
    return
  end

  -- Find max bmN across all lines
  local max_num = 0
  for _, line in ipairs(lines) do
    local prefix = line:match('^([^%s]+)')
    if prefix then
      local bm = prefix:match('^%d+:(.+)$')
      if bm then
        local num = bm:match('^bm(%d+)$')
        if num then
          max_num = math.max(max_num, tonumber(num))
        end
      end
    end
  end

  local new_bookmark = 'bm' .. (max_num + 1)

  -- Parse current line and add bookmark
  local prefix, rest = current_line:match('^([^%s]+)%s%s(.*)$')
  if not prefix then
    prefix = current_line:match('^([^%s]+)%s*$')
    rest = '(empty)'
  end
  if not prefix then return end

  -- Extract index (strip existing bookmark if any)
  local index = prefix:match('^(%d+)')
  if not index then return end

  -- Build new line
  local new_line = index .. ':' .. new_bookmark .. '  ' .. rest

  -- Update buffer
  vim.bo[edit_bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(edit_bufnr, line_nr - 1, line_nr, false, { new_line })
  vim.bo[edit_bufnr].modified = true
end

-- Go to state on current line and close
function M.goto_and_close(edit_bufnr)
  local info = edit_buffers[edit_bufnr]
  if not info then return end

  local line_nr = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(edit_bufnr, line_nr - 1, line_nr, false)
  if #lines == 0 then return end

  local line = lines[1]
  if line:match('^#') or vim.trim(line) == '' then
    M.close(edit_bufnr)
    return
  end

  local cache = state.get_cache(info.source_bufnr)
  if not cache then
    M.close(edit_bufnr)
    return
  end

  -- Find position matching this line number (1-indexed position in filtered_states)
  local position = line_nr
  if position > 0 and position <= #cache.filtered_states then
    -- Delete autocmds before closing
    if info.augroup then
      vim.api.nvim_del_augroup_by_id(info.augroup)
    end

    -- Update position (highlights already applied from preview)
    cache.current_position = position

    -- Focus source buffer
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == info.source_bufnr then
        vim.api.nvim_set_current_win(win)
        break
      end
    end

    -- Clean up
    edit_buffers[edit_bufnr] = nil

    -- Delete edit buffer
    if vim.api.nvim_buf_is_valid(edit_bufnr) then
      vim.api.nvim_buf_delete(edit_bufnr, { force = true })
    end
  else
    M.close(edit_bufnr)
  end
end

-- Open edit buffer for source buffer
function M.open(source_bufnr)
  source_bufnr = source_bufnr or vim.api.nvim_get_current_buf()

  local filepath = vim.api.nvim_buf_get_name(source_bufnr)
  if filepath == '' then
    vim.notify('demo.nvim: Cannot edit states for unsaved buffer', vim.log.levels.ERROR)
    return nil
  end

  -- Ensure cache is loaded and filtered
  local cache = state.get_cache(source_bufnr)
  if not cache then
    state.load(source_bufnr)
    cache = state.get_cache(source_bufnr)
  end
  if cache and #cache.filtered_states == 0 then
    state.filter_to_blob(source_bufnr)
    cache = state.get_cache(source_bufnr)
  end

  local rel_path = storage.get_relative_path(filepath)
  local blob = cache and cache.current_blob or 'none'

  -- Create edit buffer
  local edit_bufnr = vim.api.nvim_create_buf(false, true)
  local bufname = string.format('demo://%s @ %s', rel_path, blob)
  vim.api.nvim_buf_set_name(edit_bufnr, bufname)

  -- Store info
  edit_buffers[edit_bufnr] = {
    source_bufnr = source_bufnr,
    original_position = cache and cache.current_position or 0,
  }

  -- Set buffer options
  vim.bo[edit_bufnr].buftype = 'acwrite'
  vim.bo[edit_bufnr].bufhidden = 'wipe'
  vim.bo[edit_bufnr].swapfile = false
  vim.bo[edit_bufnr].filetype = 'demo-edit'

  -- Render states
  M.render(edit_bufnr)

  -- Create augroup for this buffer
  local augroup = vim.api.nvim_create_augroup('DemoEdit' .. edit_bufnr, { clear = true })
  edit_buffers[edit_bufnr].augroup = augroup

  -- BufWriteCmd handler
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    group = augroup,
    buffer = edit_bufnr,
    callback = function()
      M.save(edit_bufnr)
    end,
  })

  -- CursorMoved handler for live preview
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    group = augroup,
    buffer = edit_bufnr,
    callback = function()
      local line_nr = vim.api.nvim_win_get_cursor(0)[1]
      M.preview_line(edit_bufnr, line_nr)
    end,
  })

  -- BufWipeout cleanup
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = augroup,
    buffer = edit_bufnr,
    callback = function()
      local info = edit_buffers[edit_bufnr]
      if info then
        -- Restore original state on wipe
        local c = state.get_cache(info.source_bufnr)
        if c then
          state.goto_position(info.source_bufnr, info.original_position)
        end
        edit_buffers[edit_bufnr] = nil
      end
    end,
  })

  -- Set up buffer-local keymaps
  vim.keymap.set('n', 'q', function()
    M.close(edit_bufnr)
  end, { buffer = edit_bufnr, desc = 'Close edit buffer' })

  vim.keymap.set('n', '<CR>', function()
    M.goto_and_close(edit_bufnr)
  end, { buffer = edit_bufnr, desc = 'Go to this state and close' })

  vim.keymap.set('n', 'B', function()
    M.add_bookmark(edit_bufnr)
  end, { buffer = edit_bufnr, desc = 'Add auto-generated bookmark to current line' })

  -- Open in vertical split on the right, fixed width
  vim.cmd('botright vsplit')
  vim.api.nvim_win_set_buf(0, edit_bufnr)
  vim.api.nvim_win_set_width(0, 20)
  vim.wo.winfixwidth = true

  -- Preview first line
  M.preview_line(edit_bufnr, 1)

  return edit_bufnr
end

return M
