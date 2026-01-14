local M = {}

local ns_id = vim.api.nvim_create_namespace('demo_highlights')

-- Store highlights per buffer: { [bufnr] = { {start_line, end_line, hlgroup, extmark_ids}, ... } }
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

function M.add(bufnr, start_line, end_line, hlgroup)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  hlgroup = hlgroup or 'DemoHighlight1'

  -- Ensure 0-indexed for extmarks, but store 1-indexed for user display
  local start_0 = start_line - 1
  local end_0 = end_line - 1

  local extmark_ids = {}
  for line = start_0, end_0 do
    local id = vim.api.nvim_buf_set_extmark(bufnr, ns_id, line, 0, {
      end_row = line,
      end_col = 0,
      hl_eol = true,
      hl_group = hlgroup,
      priority = 100,
      line_hl_group = hlgroup,
    })
    table.insert(extmark_ids, id)
  end

  highlights[bufnr] = highlights[bufnr] or {}
  table.insert(highlights[bufnr], {
    start_line = start_line,
    end_line = end_line,
    hlgroup = hlgroup,
    extmark_ids = extmark_ids,
  })

  return #highlights[bufnr]
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

  -- Find and remove highlights that include this line
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
    M.add(bufnr, hl.start_line, hl.end_line, hl.hlgroup)
  end
end

function M.from_visual(hlgroup)
  local bufnr = vim.api.nvim_get_current_buf()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_line = start_pos[2]
  local end_line = end_pos[2]

  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  return M.add(bufnr, start_line, end_line, hlgroup)
end

return M
