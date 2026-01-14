local M = {}

local ns_id = vim.api.nvim_create_namespace('demo_highlights')

-- Store highlights per buffer
local highlights = {}

local default_groups = {
  DemoHighlight1 = { bg = "#3d5c5c" },  -- Teal
  DemoHighlight2 = { bg = "#5c3d5c" },  -- Purple
  DemoHighlight3 = { bg = "#5c5c3d" },  -- Olive
  DemoHighlight4 = { bg = "#3d3d5c" },  -- Blue
  DemoHighlight5 = { bg = "#5c3d3d" },  -- Red
}

function M.setup_highlight_groups()
  for name, opts in pairs(default_groups) do
    if vim.fn.hlexists(name) == 0 then
      vim.api.nvim_set_hl(0, name, opts)
    end
  end
end

function M.get_namespace()
  return ns_id
end

-- Add highlight with optional column range
-- end_col = -1 means highlight full lines
function M.add(bufnr, start_line, start_col, end_line, end_col, hlgroup)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  hlgroup = hlgroup or 'DemoHighlight1'
  start_col = start_col or 0
  end_col = end_col or -1

  local extmark_ids = {}

  if end_col == -1 then
    -- Full line highlighting
    for line = start_line, end_line do
      local line_0 = line - 1
      local id = vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_0, 0, {
        end_row = line_0,
        end_col = 0,
        hl_eol = true,
        hl_group = hlgroup,
        priority = 100,
        line_hl_group = hlgroup,
      })
      table.insert(extmark_ids, id)
    end
  else
    -- Character range highlighting (can span multiple lines)
    local start_line_0 = start_line - 1
    local end_line_0 = end_line - 1
    -- Columns are already 0-indexed from visual mode
    local id = vim.api.nvim_buf_set_extmark(bufnr, ns_id, start_line_0, start_col, {
      end_row = end_line_0,
      end_col = end_col,
      hl_group = hlgroup,
      priority = 100,
    })
    table.insert(extmark_ids, id)
  end

  highlights[bufnr] = highlights[bufnr] or {}
  table.insert(highlights[bufnr], {
    start_line = start_line,
    start_col = start_col,
    end_line = end_line,
    end_col = end_col,
    hlgroup = hlgroup,
    extmark_ids = extmark_ids,
  })

  return #highlights[bufnr]
end

-- Convenience: add full line highlight
function M.add_lines(bufnr, start_line, end_line, hlgroup)
  return M.add(bufnr, start_line, 0, end_line, -1, hlgroup)
end

function M.remove(bufnr, index)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local buf_highlights = highlights[bufnr]
  if not buf_highlights or not buf_highlights[index] then
    return false
  end

  local hl = buf_highlights[index]
  for _, id in ipairs(hl.extmark_ids) do
    vim.api.nvim_buf_del_extmark(bufnr, ns_id, id)
  end

  table.remove(buf_highlights, index)
  return true
end

function M.clear(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  highlights[bufnr] = {}
end

function M.clear_line(bufnr, line)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local buf_highlights = highlights[bufnr]
  if not buf_highlights then return end

  for i = #buf_highlights, 1, -1 do
    local hl = buf_highlights[i]
    if line >= hl.start_line and line <= hl.end_line then
      M.remove(bufnr, i)
    end
  end
end

function M.get_all(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return highlights[bufnr] or {}
end

function M.set_all(bufnr, highlight_list)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  M.clear(bufnr)
  for _, hl in ipairs(highlight_list) do
    M.add(bufnr, hl.start_line, hl.start_col, hl.end_line, hl.end_col, hl.hlgroup)
  end
end

function M.from_visual(hlgroup)
  local bufnr = vim.api.nvim_get_current_buf()
  local mode = vim.fn.visualmode()

  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  local start_line = start_pos[2]
  local start_col = start_pos[3] - 1  -- Convert to 0-indexed
  local end_line = end_pos[2]
  local end_col = end_pos[3]  -- End is exclusive, so don't subtract

  -- Handle backwards selection
  if start_line > end_line or (start_line == end_line and start_col > end_col) then
    start_line, end_line = end_line, start_line
    start_col, end_col = end_col, start_col
  end

  -- For line-wise visual mode (V), highlight full lines
  if mode == 'V' then
    return M.add(bufnr, start_line, 0, end_line, -1, hlgroup)
  end

  -- For character-wise (v) or block-wise (^V), use character positions
  return M.add(bufnr, start_line, start_col, end_line, end_col, hlgroup)
end

return M
