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

-- Get current commit SHA (short form)
-- Uses git HEAD which is stable (unlike jj's @ which changes on every edit)
function M.get_commit()
  local _, vcs = M.get_repo_root()

  if vcs == 'jj' then
    local commit = run_cmd('git rev-parse HEAD')
    if commit and commit ~= '' then
      return commit:sub(1, 7)
    end
    commit = run_cmd('jj log --no-graph -r @- -T "commit_id"')
    if commit and commit ~= '' then
      return commit:sub(1, 7)
    end
  else
    local commit = run_cmd('git rev-parse HEAD')
    if commit and commit ~= '' then
      return commit:sub(1, 7)
    end
  end

  return nil
end

function M.get_relative_path(filepath)
  local root = M.get_repo_root()
  if not root then return filepath end

  filepath = vim.fn.fnamemodify(filepath, ':p')
  root = vim.fn.fnamemodify(root, ':p')

  if vim.startswith(filepath, root) then
    return filepath:sub(#root + 1)
  end
  return filepath
end

function M.get_storage_dir()
  local data_dir = vim.fn.stdpath('data') .. '/demo'
  local root = M.get_repo_root()
  if not root then
    -- Use cwd as fallback, hash it for safety
    local cwd = vim.fn.getcwd()
    local safe_name = cwd:gsub('/', '__'):gsub(':', '_')
    return data_dir .. '/' .. safe_name
  end
  -- Use repo root path to create unique folder per repo
  local safe_name = root:gsub('/', '__'):gsub(':', '_')
  return data_dir .. '/' .. safe_name
end

function M.get_states_path(filepath)
  local rel_path = M.get_relative_path(filepath)
  local safe_name = rel_path:gsub('/', '__')
  local storage_dir = M.get_storage_dir()
  return storage_dir .. '/' .. safe_name .. '.demo'
end

function M.ensure_dir(filepath)
  local dir = vim.fn.fnamemodify(filepath, ':h')
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, 'p')
  end
end

-- Parse highlight line
local function parse_highlight_line(line)
  line = vim.trim(line)
  if line == '' or line:match('^#') then
    return nil
  end

  -- Try character range: "5:3-10:20 HlGroup"
  local s_line, s_col, e_line, e_col, hlgroup = line:match('^(%d+):(%d+)-(%d+):(%d+)%s+(%S+)$')
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
  local start_l, end_l, hl = line:match('^(%d+)-(%d+)%s+(%S+)$')
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
  local single_l, single_hl = line:match('^(%d+)%s+(%S+)$')
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

-- Format highlight for storage
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

-- Parse section header: [index:bookmark @ commit] or [index @ commit]
local function parse_section_header(line)
  -- Try [index:bookmark @ commit]
  local index, bookmark, commit = line:match('^%[(%d+):([^@%]]+)%s*@%s*([^%]]+)%]$')
  if index then
    return tonumber(index), vim.trim(bookmark), vim.trim(commit)
  end

  -- Try [index @ commit] (no bookmark)
  index, commit = line:match('^%[(%d+)%s*@%s*([^%]]+)%]$')
  if index then
    return tonumber(index), nil, vim.trim(commit)
  end

  -- Try [index:bookmark] (no commit)
  index, bookmark = line:match('^%[(%d+):([^%]]+)%]$')
  if index then
    return tonumber(index), vim.trim(bookmark), nil
  end

  -- Try [index] only
  index = line:match('^%[(%d+)%]$')
  if index then
    return tonumber(index), nil, nil
  end

  return nil, nil, nil
end

function M.read_states(filepath)
  local states_path = M.get_states_path(filepath)
  if vim.fn.filereadable(states_path) == 0 then
    return {}
  end

  local lines = vim.fn.readfile(states_path)
  local states = {}
  local current_state = nil

  for _, line in ipairs(lines) do
    local index, bookmark, commit = parse_section_header(line)
    if index then
      if current_state then
        table.insert(states, current_state)
      end
      current_state = {
        index = index,
        bookmark = bookmark,
        commit = commit,
        highlights = {},
      }
    elseif current_state then
      local hl = parse_highlight_line(line)
      if hl then
        table.insert(current_state.highlights, hl)
      end
    end
  end

  if current_state then
    table.insert(states, current_state)
  end

  -- Sort by index
  table.sort(states, function(a, b) return a.index < b.index end)

  return states
end

function M.write_states(filepath, states)
  local states_path = M.get_states_path(filepath)
  M.ensure_dir(states_path)

  local rel_path = M.get_relative_path(filepath)
  local lines = {
    '# demo.nvim states for ' .. rel_path,
    '# Format: [index:bookmark @ commit] or [index @ commit]',
    '# Bookmarks mark important steps. Reorder sections to change order.',
    '',
  }

  for _, state in ipairs(states) do
    local header
    if state.bookmark and state.commit then
      header = string.format('[%d:%s @ %s]', state.index, state.bookmark, state.commit)
    elseif state.bookmark then
      header = string.format('[%d:%s]', state.index, state.bookmark)
    elseif state.commit then
      header = string.format('[%d @ %s]', state.index, state.commit)
    else
      header = string.format('[%d]', state.index)
    end
    table.insert(lines, header)
    for _, hl in ipairs(state.highlights) do
      table.insert(lines, format_highlight(hl))
    end
    table.insert(lines, '')
  end

  vim.fn.writefile(lines, states_path)
  return states_path
end

function M.get_vcs_info()
  local root, vcs = M.get_repo_root()
  local commit = M.get_commit()
  return {
    root = root,
    vcs = vcs,
    commit = commit,
  }
end

return M
