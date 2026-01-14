if vim.g.loaded_demo then
  return
end
vim.g.loaded_demo = true

local demo = require('demo')

-- Setup highlight groups immediately
demo.setup()

-- Highlight commands
vim.api.nvim_create_user_command('DemoHighlight', function(opts)
  local hlgroup = opts.args ~= '' and opts.args or 'DemoHighlight1'
  demo.highlight(hlgroup)
end, {
  nargs = '?',
  range = true,
  desc = 'Highlight visual selection with specified highlight group',
})

vim.api.nvim_create_user_command('DemoHighlightLines', function(opts)
  local args = vim.split(opts.args, '%s+')
  local hlgroup = 'DemoHighlight1'

  -- Parse range: either "10 20" or "10-20" or just use command range
  local start_line, end_line

  if opts.range == 2 then
    start_line = opts.line1
    end_line = opts.line2
    if #args > 0 and args[1] ~= '' then
      hlgroup = args[1]
    end
  else
    if #args >= 2 then
      -- Try "10 20 [hlgroup]" format
      start_line = tonumber(args[1])
      end_line = tonumber(args[2])
      if #args >= 3 then
        hlgroup = args[3]
      end
    elseif #args == 1 and args[1]:match('%d+%-%d+') then
      -- Try "10-20" format
      local s, e = args[1]:match('(%d+)%-(%d+)')
      start_line = tonumber(s)
      end_line = tonumber(e)
    end
  end

  if not start_line or not end_line then
    vim.notify('demo.nvim: Usage: :DemoHighlightLines {start} {end} [hlgroup] or :{range}DemoHighlightLines [hlgroup]', vim.log.levels.ERROR)
    return
  end

  demo.highlight_lines(start_line, end_line, hlgroup)
end, {
  nargs = '*',
  range = true,
  desc = 'Highlight line range with specified highlight group',
})

vim.api.nvim_create_user_command('DemoClear', function()
  demo.clear()
end, {
  desc = 'Clear all demo highlights',
})

vim.api.nvim_create_user_command('DemoClearLine', function(opts)
  local line = opts.args ~= '' and tonumber(opts.args) or vim.fn.line('.')
  demo.clear_line(line)
end, {
  nargs = '?',
  desc = 'Clear highlights on specified line (default: current line)',
})

-- History commands
vim.api.nvim_create_user_command('DemoUndo', function()
  demo.undo()
end, {
  desc = 'Undo last highlight change',
})

vim.api.nvim_create_user_command('DemoRedo', function()
  demo.redo()
end, {
  desc = 'Redo highlight change',
})

-- Bookmark commands
vim.api.nvim_create_user_command('DemoBookmark', function(opts)
  if opts.args == '' then
    vim.notify('demo.nvim: Usage: :DemoBookmark {name}', vim.log.levels.ERROR)
    return
  end
  demo.bookmark(opts.args)
end, {
  nargs = 1,
  desc = 'Save current highlights as a named bookmark',
})

vim.api.nvim_create_user_command('DemoDeleteBookmark', function(opts)
  if opts.args == '' then
    vim.notify('demo.nvim: Usage: :DemoDeleteBookmark {name}', vim.log.levels.ERROR)
    return
  end
  demo.delete_bookmark(opts.args)
end, {
  nargs = 1,
  desc = 'Delete a named bookmark',
})

vim.api.nvim_create_user_command('DemoList', function()
  demo.list_bookmarks()
end, {
  desc = 'List all bookmarks for current file/commit',
})

vim.api.nvim_create_user_command('DemoReload', function()
  demo.reload_bookmarks()
  vim.notify('demo.nvim: Bookmarks reloaded from disk', vim.log.levels.INFO)
end, {
  desc = 'Reload bookmarks from disk (after manual edit)',
})

-- Presenter commands
vim.api.nvim_create_user_command('DemoStart', function()
  demo.start()
end, {
  desc = 'Start presenter mode',
})

vim.api.nvim_create_user_command('DemoStop', function()
  demo.stop()
end, {
  desc = 'Stop presenter mode',
})

vim.api.nvim_create_user_command('DemoNext', function()
  demo.next()
end, {
  desc = 'Go to next bookmark in presenter mode',
})

vim.api.nvim_create_user_command('DemoPrev', function()
  demo.prev()
end, {
  desc = 'Go to previous bookmark in presenter mode',
})

vim.api.nvim_create_user_command('DemoGoto', function(opts)
  local arg = opts.args
  -- Try as number first
  local num = tonumber(arg)
  if num then
    demo.goto(num)
  else
    demo.goto(arg)
  end
end, {
  nargs = 1,
  desc = 'Jump to specific bookmark by name or index',
})

-- Info commands
vim.api.nvim_create_user_command('DemoInfo', function()
  local pinfo = demo.presenter_info()
  local hinfo = demo.history_info()

  local lines = {
    'Demo.nvim Status:',
    string.format('  Presenter: %s', pinfo.active and 'active' or 'inactive'),
  }

  if pinfo.active then
    local current = pinfo.current_index == 0 and '(blank)' or pinfo.current_name or tostring(pinfo.current_index)
    table.insert(lines, string.format('  Current slide: %d/%d (%s)', pinfo.current_index, pinfo.total, current))
  end

  table.insert(lines, string.format('  History: %d states, at position %d', hinfo.total, hinfo.current))

  vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
end, {
  desc = 'Show demo.nvim status info',
})

vim.api.nvim_create_user_command('DemoVcsInfo', function()
  demo.vcs_info()
end, {
  desc = 'Show VCS (jj/git) info',
})
