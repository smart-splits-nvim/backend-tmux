---Options for the tmux backend. Storing them is all this module does: a backend
---that is merely configured may not be the one that ends up selected, so every
---side effect belongs in `activate()` instead.
---@class TmuxBackend.Config
---@field enable boolean whether this backend may be selected at all
---@field disable_nav_when_zoomed boolean refuse to move out of a zoomed tmux pane
---@field resize_amount integer cells to resize by when the caller names no amount
---@field timeout integer milliseconds to wait for a `tmux` invocation

---@class TmuxBackend.PartialConfig
---@field enable? boolean
---@field disable_nav_when_zoomed? boolean
---@field resize_amount? integer
---@field timeout? integer

local M = {}

---@type TmuxBackend.Config
M.defaults = {
  enable = true,
  disable_nav_when_zoomed = true,
  -- smart-splits' own default, and the step size the paired tmux bindings use
  resize_amount = 3,
  -- these run on every keypress at a window edge; a tmux that is not answering
  -- should degrade to plain Neovim movement rather than stall the editor
  timeout = 300,
}

---@type TmuxBackend.Config
M.options = vim.deepcopy(M.defaults)

---@param opts? TmuxBackend.PartialConfig
---@return TmuxBackend.Config
function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', M.defaults, opts or {})
  return M.options
end

return M
