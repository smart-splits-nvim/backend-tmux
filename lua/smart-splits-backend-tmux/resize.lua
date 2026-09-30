---@module 'smart-splits.backend'

local config = require('smart-splits-backend-tmux.config')
local tmux = require('smart-splits-backend-tmux.tmux')

local M = {}

---Resize the current tmux pane. Core calls this only when the Neovim window
---already fills that axis, and never falls back to a Neovim resize afterwards,
---so the return value is reported but changes nothing.
---@param direction SmartSplitsDirection
---@param opts? SmartSplitsBackendResizeOpts
---@return boolean
function M.resize(direction, opts)
  opts = opts or {}
  if not config.options.enable or not tmux.is_in_session() then
    return false
  end

  -- `opts.amount` is already `v:count1 * config.resize.amount`; tmux counts in
  -- cells too, so it passes straight through
  return tmux.resize_pane(direction, opts.amount or config.options.resize_amount)
end

return M
