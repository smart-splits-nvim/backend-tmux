---@module 'smart-splits.backend'

local config = require('smart-splits-backend-tmux.config')
local tmux = require('smart-splits-backend-tmux.tmux')

local M = {}

---Move focus one tmux pane. Core only calls this once the cursor is already at
---the edge of Neovim's own layout, and only falls back to Neovim's `at_edge`
---behaviour when this returns `false`; so at the outer edge of tmux, `split`
---has to make a tmux pane here or core will make a Neovim one instead.
---@param direction SmartSplitsDirection
---@param opts? SmartSplitsBackendMoveOpts
---@return boolean
function M.move(direction, opts)
  opts = opts or {}
  if not config.options.enable or not tmux.is_in_session() then
    return false
  end

  -- a zoomed pane fills its window, so moving out of it would also unzoom it;
  -- core has no concept of zoom, so the decision is ours
  if config.options.disable_nav_when_zoomed and tmux.is_zoomed() then
    return false
  end

  -- `select-pane -L` wraps around the window and reports success either way, so
  -- core could not tell a wrap from an ordinary move. Ask first instead.
  if not tmux.at_edge(direction) then
    return tmux.select_pane(direction)
  end

  local at_edge = opts.at_edge or 'stop'
  if at_edge == 'wrap' then
    -- with a single pane there is nothing to wrap to, and answering `true`
    -- would rob core of the chance to wrap among Neovim's windows
    if tmux.pane_count() < 2 then
      return false
    end
    return tmux.select_pane(direction)
  elseif at_edge == 'split' then
    return tmux.split_pane(direction)
  end

  return false
end

return M
