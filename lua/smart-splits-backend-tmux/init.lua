---@module 'smart-splits.backend'

local activate = require('smart-splits-backend-tmux.activate')
local config = require('smart-splits-backend-tmux.config')
local health = require('smart-splits-backend-tmux.health')
local move = require('smart-splits-backend-tmux.move')
local resize = require('smart-splits-backend-tmux.resize')
local tmux = require('smart-splits-backend-tmux.tmux')

---@type SmartSplitsBackend
local M = {
  name = 'tmux',
  protocol_version = '3.0.0',
  ---Configuration only. Core never calls this, and being configured says
  ---nothing about being selected, so it stays free of side effects.
  ---@param opts? TmuxBackend.PartialConfig
  setup = function(opts)
    config.setup(opts)
  end,
  ---Cheap and side-effect free, as the protocol requires: the tmux server sets
  ---`$TMUX` for every process it starts, and nothing else sets it.
  detect = function()
    return config.options.enable and tmux.is_in_session()
  end,
  move = move.move,
  resize = resize.resize,
  activate = activate.activate,
  health = health.report,
}

return M
