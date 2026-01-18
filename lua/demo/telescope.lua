local M = {}

function M.pick_set()
  local ok, pickers = pcall(require, 'telescope.pickers')
  if not ok then
    vim.notify('demo.nvim: telescope.nvim is required for the picker', vim.log.levels.ERROR)
    return
  end

  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')

  local state = require('demo.state')
  local storage = require('demo.storage')

  local filepath = vim.api.nvim_buf_get_name(0)
  if filepath == '' then
    vim.notify('demo.nvim: No file in current buffer', vim.log.levels.ERROR)
    return
  end

  local sets = storage.list_sets(filepath)
  if #sets == 0 then
    vim.notify('demo.nvim: No saved sets for this file', vim.log.levels.INFO)
    return
  end

  -- Build entries with preview info
  local entries = {}
  for _, set_name in ipairs(sets) do
    local set_states = storage.load_set(filepath, set_name)
    local state_count = set_states and #set_states or 0
    local bookmark_count = 0
    if set_states then
      for _, s in ipairs(set_states) do
        if s.bookmark then bookmark_count = bookmark_count + 1 end
      end
    end
    table.insert(entries, {
      name = set_name,
      display = string.format('%s (%d states, %d bookmarks)', set_name, state_count, bookmark_count),
      ordinal = set_name,
    })
  end

  pickers.new({}, {
    prompt_title = 'Demo.nvim Sets',
    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        return {
          value = entry.name,
          display = entry.display,
          ordinal = entry.ordinal,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
          state.load_set(nil, selection.value)
        end
      end)
      return true
    end,
  }):find()
end

return M
