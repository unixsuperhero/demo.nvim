local M = {}

local function run_cmd(cmd)
  local handle = io.popen(cmd .. ' 2>/dev/null')
  if not handle then return nil end
  local result = handle:read('*a')
  handle:close()
  if result then
    return vim.trim(result)
  end
  return nil
end

function M.get_repo_root()
  -- Try jj first
  local root = run_cmd('jj root')
  if root and root ~= '' then
    return root, 'jj'
  end
  -- Fallback to git
  root = run_cmd('git rev-parse --show-toplevel')
  if root and root ~= '' then
    return root, 'git'
  end
  return nil, nil
end

function M.get_commit_id()
  -- Try jj first: get the commit_id of the current working copy
  local commit = run_cmd('jj log --no-graph -r @ -T "commit_id"')
  if commit and commit ~= '' and #commit >= 8 then
    return commit:sub(1, 12), 'jj'  -- Use first 12 chars for readability
  end
  -- Fallback to git
  commit = run_cmd('git rev-parse HEAD')
  if commit and commit ~= '' then
    return commit:sub(1, 12), 'git'
  end
  return nil, nil
end

function M.get_relative_path(filepath)
  local root = M.get_repo_root()
  if not root then return filepath end

  -- Normalize paths
  filepath = vim.fn.fnamemodify(filepath, ':p')
  root = vim.fn.fnamemodify(root, ':p')

  if vim.startswith(filepath, root) then
    return filepath:sub(#root + 1)
  end
  return filepath
end

function M.get_storage_dir()
  local root = M.get_repo_root()
  if not root then
    return vim.fn.getcwd() .. '/.demo'
  end
  return root .. '/.demo'
end

function M.get_bookmark_path(filepath)
  local commit = M.get_commit_id()
  if not commit then
    commit = 'uncommitted'
  end

  local rel_path = M.get_relative_path(filepath)
  -- Replace path separators with underscores for flat storage
  local safe_name = rel_path:gsub('/', '__')

  local storage_dir = M.get_storage_dir()
  return storage_dir .. '/' .. commit .. '/' .. safe_name .. '.txt'
end

function M.ensure_dir(filepath)
  local dir = vim.fn.fnamemodify(filepath, ':h')
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, 'p')
  end
end

-- Parse a single highlight from storage format: "start_line:start_col-end_line:end_col:hlgroup"
local function parse_highlight(str)
  local pattern = '(%d+):(%d+)-(%d+):(%d+):(%S+)'
  local start_line, start_col, end_line, end_col, hlgroup = str:match(pattern)
  if start_line then
    return {
      start_line = tonumber(start_line),
      end_line = tonumber(end_line),
      hlgroup = hlgroup,
    }
  end
  return nil
end

-- Format a highlight for storage
local function format_highlight(hl)
  -- Using col 1 and 0 as placeholders since we highlight full lines
  return string.format('%d:1-%d:0:%s', hl.start_line, hl.end_line, hl.hlgroup)
end

function M.parse_bookmark_line(line)
  if line:match('^#') or line:match('^%s*$') then
    return nil  -- Comment or empty line
  end

  local parts = vim.split(line, '|')
  if #parts < 1 then return nil end

  local name = parts[1]
  local highlights = {}

  for i = 2, #parts do
    local hl = parse_highlight(parts[i])
    if hl then
      table.insert(highlights, hl)
    end
  end

  return {
    name = name,
    highlights = highlights,
  }
end

function M.format_bookmark_line(name, highlights)
  local parts = { name }
  for _, hl in ipairs(highlights) do
    table.insert(parts, format_highlight(hl))
  end
  return table.concat(parts, '|')
end

function M.read_bookmarks(filepath)
  local bookmark_path = M.get_bookmark_path(filepath)
  if vim.fn.filereadable(bookmark_path) == 0 then
    return {}
  end

  local lines = vim.fn.readfile(bookmark_path)
  local bookmarks = {}

  for _, line in ipairs(lines) do
    local bookmark = M.parse_bookmark_line(line)
    if bookmark then
      table.insert(bookmarks, bookmark)
    end
  end

  return bookmarks
end

function M.write_bookmarks(filepath, bookmarks)
  local bookmark_path = M.get_bookmark_path(filepath)
  M.ensure_dir(bookmark_path)

  local lines = {
    '# demo.nvim bookmark file',
    '# format: name|start:col-end:col:hlgroup|...',
    '# reorder lines to change bookmark order',
  }

  for _, bookmark in ipairs(bookmarks) do
    table.insert(lines, M.format_bookmark_line(bookmark.name, bookmark.highlights))
  end

  vim.fn.writefile(lines, bookmark_path)
  return bookmark_path
end

function M.has_uncommitted_changes()
  -- Check jj first
  local status = run_cmd('jj status')
  if status then
    -- jj status shows "Working copy changes:" if there are changes
    if status:match('Working copy changes:') then
      return true, 'jj'
    end
    return false, 'jj'
  end

  -- Fallback to git
  status = run_cmd('git status --porcelain')
  if status and status ~= '' then
    return true, 'git'
  end
  return false, 'git'
end

function M.get_vcs_info()
  local root, vcs = M.get_repo_root()
  local commit, commit_vcs = M.get_commit_id()
  local has_changes, changes_vcs = M.has_uncommitted_changes()

  return {
    root = root,
    vcs = vcs or commit_vcs or changes_vcs,
    commit = commit,
    has_uncommitted = has_changes,
  }
end

return M
