if vim.g.loaded_demo then
  return
end
vim.g.loaded_demo = true

local demo = require('demo')

-- Setup highlight groups immediately
demo.setup()

-- Completion function for highlight groups
local function complete_hlgroups(arg_lead, cmd_line, cursor_pos)
  local groups = {
    'DemoHighlight1',
    'DemoHighlight2',
    'DemoHighlight3',
    'DemoHighlight4',
    'DemoHighlight5',
  }
  if arg_lead == '' then
    return groups
  end
  local matches = {}
  for _, g in ipairs(groups) do
    if g:lower():find(arg_lead:lower(), 1, true) then
      table.insert(matches, g)
    end
  end
  return matches
end

-- Highlight commands
vim.api.nvim_create_user_command('DemoHighlight', function(opts)
  local hlgroup = opts.args ~= '' and opts.args or 'DemoHighlight1'
  if opts.range == 0 then
    -- No range given, highlight current line
    local line = vim.fn.line('.')
    demo.highlight_lines(line, line, hlgroup)
  else
    -- Range given (visual selection), use visual marks
    demo.highlight(hlgroup)
  end
end, {
  nargs = '?',
  range = true,
  complete = complete_hlgroups,
  desc = 'Highlight visual selection or current line with specified highlight group',
})

vim.api.nvim_create_user_command('DemoHighlightLines', function(opts)
  local args = vim.split(opts.args, '%s+')
  local hlgroup = 'DemoHighlight1'
  local start_line, end_line

  if opts.range == 2 then
    start_line = opts.line1
    end_line = opts.line2
    if #args > 0 and args[1] ~= '' then
      hlgroup = args[1]
    end
  else
    if #args >= 2 then
      start_line = tonumber(args[1])
      end_line = tonumber(args[2])
      if #args >= 3 then
        hlgroup = args[3]
      end
    elseif #args == 1 and args[1]:match('%d+%-%d+') then
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

vim.api.nvim_create_user_command('DemoReset', function()
  demo.reset()
end, {
  desc = 'Delete all states for current commit (start over)',
})

vim.api.nvim_create_user_command('DemoClearLine', function(opts)
  local line = opts.args ~= '' and tonumber(opts.args) or vim.fn.line('.')
  demo.clear_line(line)
end, {
  nargs = '?',
  desc = 'Clear highlights on specified line (default: current line)',
})

-- Bookmark commands
vim.api.nvim_create_user_command('DemoBookmark', function(opts)
  local name = opts.args
  if name == '' then
    -- Auto-generate name: find highest bmN and increment
    local state_mod = require('demo.state')
    local filtered = state_mod.get_filtered()
    local max_num = 0
    for _, s in ipairs(filtered) do
      if s.bookmark then
        local num = s.bookmark:match('^bm(%d+)$')
        if num then
          max_num = math.max(max_num, tonumber(num))
        end
      end
    end
    name = 'bm' .. (max_num + 1)
  end
  -- If range given (visual selection), highlight first then bookmark
  if opts.range > 0 then
    demo.highlight('DemoHighlight1')
  end
  demo.bookmark(name)
end, {
  nargs = '?',
  range = true,
  desc = 'Bookmark current state with a name (auto-generates if none given)',
})

vim.api.nvim_create_user_command('DemoDeleteBookmark', function(opts)
  if opts.args == '' then
    vim.notify('demo.nvim: Usage: :DemoDeleteBookmark {name}', vim.log.levels.ERROR)
    return
  end
  demo.delete_bookmark(opts.args)
end, {
  nargs = 1,
  desc = 'Delete a bookmark by name',
})

vim.api.nvim_create_user_command('DemoList', function()
  demo.list()
end, {
  desc = 'List all states and bookmarks',
})

vim.api.nvim_create_user_command('DemoReload', function()
  demo.reload()
  vim.notify('demo.nvim: States reloaded from disk', vim.log.levels.INFO)
end, {
  desc = 'Reload states from disk (after manual edit)',
})

vim.api.nvim_create_user_command('DemoEdit', function()
  demo.edit()
end, {
  desc = 'Open interactive edit buffer for states',
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

vim.api.nvim_create_user_command('DemoToggle', function()
  demo.toggle()
end, {
  desc = 'Toggle presenter mode',
})

-- Bookmark navigation (jump between bookmarks)
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

-- Step navigation (every recorded state)
vim.api.nvim_create_user_command('DemoNextStep', function()
  demo.next_step()
end, {
  desc = 'Go to next step (any state) in presenter mode',
})

vim.api.nvim_create_user_command('DemoPrevStep', function()
  demo.prev_step()
end, {
  desc = 'Go to previous step (any state) in presenter mode',
})

vim.api.nvim_create_user_command('DemoGoto', function(opts)
  local arg = opts.args
  local num = tonumber(arg)
  if num then
    demo.goto(num)
  else
    demo.goto(arg)
  end
end, {
  nargs = 1,
  desc = 'Jump to specific bookmark by name or step by number',
})

-- Info command
vim.api.nvim_create_user_command('DemoInfo', function()
  demo.info()
end, {
  desc = 'Show demo.nvim status info',
})

-- Keymaps
-- <leader>dh - Highlight in visual mode (prompts for highlight group)
vim.keymap.set('v', '<leader>dh', ':DemoHighlight ', { desc = 'Demo: Highlight selection with group' })

-- <leader>dH - Highlight in visual mode (default highlight group)
vim.keymap.set('v', '<leader>dH', ':DemoHighlight<CR>', { desc = 'Demo: Highlight selection' })

-- <leader>db - Bookmark (prompts for name)
vim.keymap.set('n', '<leader>db', ':DemoBookmark ', { desc = 'Demo: Bookmark current state' })
vim.keymap.set('v', '<leader>db', ':DemoBookmark ', { desc = 'Demo: Highlight and bookmark selection' })

-- <leader>dn - Next bookmark
vim.keymap.set('n', '<leader>dn', ':DemoNext<CR>', { desc = 'Demo: Next bookmark' })

-- <leader>dp - Previous bookmark
vim.keymap.set('n', '<leader>dp', ':DemoPrev<CR>', { desc = 'Demo: Previous bookmark' })

-- <leader>ds - Start/Stop toggle
vim.keymap.set('n', '<leader>ds', ':DemoToggle<CR>', { desc = 'Demo: Toggle presenter' })

-- <leader>dc - Clear all highlights
vim.keymap.set('n', '<leader>dc', ':DemoClear<CR>', { desc = 'Demo: Clear highlights' })

-- <leader>dl - List states
vim.keymap.set('n', '<leader>dl', ':DemoList<CR>', { desc = 'Demo: List states' })

-- Bonus: step navigation with Shift
vim.keymap.set('n', '<leader>dN', ':DemoNextStep<CR>', { desc = 'Demo: Next step' })
vim.keymap.set('n', '<leader>dP', ':DemoPrevStep<CR>', { desc = 'Demo: Previous step' })

-- <leader>dr - Reload states from disk
vim.keymap.set('n', '<leader>dr', ':DemoReload<CR>', { desc = 'Demo: Reload states' })

-- <leader>dg - Goto bookmark/step (prompts for name or number)
vim.keymap.set('n', '<leader>dg', ':DemoGoto ', { desc = 'Demo: Goto bookmark/step' })

-- <leader>de - Edit states interactively
vim.keymap.set('n', '<leader>de', ':DemoEdit<CR>', { desc = 'Demo: Edit states' })

-- <leader>dR - Reset (delete all states for current commit)
vim.keymap.set('n', '<leader>dR', ':DemoReset<CR>', { desc = 'Demo: Reset (delete all states)' })

-- Autocmd: Clear highlights and reset state when file contents change from disk
vim.api.nvim_create_autocmd({ 'BufReadPost', 'FileChangedShellPost' }, {
  group = vim.api.nvim_create_augroup('DemoNvimFileChange', { clear = true }),
  callback = function(ev)
    demo.reload()
  end,
  desc = 'Clear demo highlights when file is reloaded from disk',
})
