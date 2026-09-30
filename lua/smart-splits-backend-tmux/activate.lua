---The `@pane-is-vim` contract.
---
---The tmux half of this integration cannot tell a Neovim pane from a shell pane
---on its own. It branches on a pane-local option instead:
---
---    bind -n C-h if -F '#{@pane-is-vim}' { send-keys C-h } { select-pane -L }
---
---Unset reads as false, so a pane whose marker is missing has `C-hjkl` swallowed
---by tmux and Neovim never sees the key. Keeping that option truthful for
---exactly as long as Neovim owns the pane is this module's whole job.

local tmux = require('smart-splits-backend-tmux.tmux')

local AUGROUP = 'SmartSplitsBackendTmux'

local M = {}

---Set by an *outer* Neovim, not by us: this instance is running inside another
---one and must leave the marker alone, above all on the way out.
local nested = false

---Whether we have already claimed the marker. Without this a second call would
---read back its own `@pane-is-vim` and mistake this instance for a nested one,
---which would then never clear the marker on the way out.
local activated = false

---@return boolean
function M.is_nested()
  return nested
end

---@param value boolean
local function set_marker(value)
  local pane = tmux.pane_id()
  if not pane then
    return
  end
  tmux.set_pane_is_vim(pane, value)
end

---Called once by core, and only for the backend that won. Anything with a side
---effect belongs here rather than in `setup()`, which runs for every installed
---backend whether or not its multiplexer is the one in use.
function M.activate()
  if not tmux.is_in_session() then
    return
  end

  local pane = tmux.pane_id()
  if not pane then
    vim.notify_once(
      'smart-splits-backend-tmux: $TMUX_PANE is not set, tmux cannot tell this pane is running Neovim; see :checkhealth smart-splits',
      vim.log.levels.WARN
    )
    return
  end

  if nested then
    return
  end
  if not activated then
    -- The marker is already claimed, so an outer Neovim is running in this
    -- pane. Clearing it when this inner instance quits would leave that outer
    -- one invisible to tmux for the rest of its life.
    nested = tmux.get_pane_is_vim(pane)
    if nested then
      return
    end
    activated = true
  end

  -- now as well as on resume: core may be lazy loaded, in which case `VimEnter`
  -- fired long before this ran
  set_marker(true)

  local group = vim.api.nvim_create_augroup(AUGROUP, { clear = true })
  vim.api.nvim_create_autocmd('VimResume', {
    group = group,
    desc = 'tmux: take back C-hjkl for Neovim',
    callback = function()
      set_marker(true)
    end,
  })
  vim.api.nvim_create_autocmd('VimSuspend', {
    group = group,
    desc = 'tmux: hand C-hjkl back to the shell',
    callback = function()
      set_marker(false)
    end,
  })
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    desc = 'tmux: hand C-hjkl back to the shell',
    callback = function()
      -- detached, because the write has to outlive the process making it
      tmux.set_pane_is_vim_detached(pane, false)
    end,
  })
end

---Drop the autocommands and the lifecycle flags. For tests.
function M.reset()
  nested = false
  activated = false
  pcall(vim.api.nvim_del_augroup_by_name, AUGROUP)
end

return M
