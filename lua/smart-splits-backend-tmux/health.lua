local activate = require('smart-splits-backend-tmux.activate')
local config = require('smart-splits-backend-tmux.config')
local tmux = require('smart-splits-backend-tmux.tmux')

local M = {}

---@param msg string
---@param ... any
local function ok(msg, ...)
  vim.health.ok(msg:format(...))
end

---@param msg string
---@param ... any
local function info(msg, ...)
  vim.health.info(msg:format(...))
end

---@param msg string
---@param ... any
local function warn(msg, ...)
  vim.health.warn(msg:format(...))
end

local function check_binary()
  if vim.env.FLATPAK_ID then
    info('$FLATPAK_ID is set, tmux is called through `flatpak-spawn --host`')
  elseif vim.fn.executable('tmux') ~= 1 then
    vim.health.error('`tmux` is not on $PATH')
    return
  end

  local version = tmux.version()
  if version then
    ok('%s', version)
  else
    warn('`tmux -V` did not answer')
  end
end

---Which keys the tmux half is bound to is the user's business; what this
---backend needs is that *something* over there reads `@pane-is-vim`, because a
---binding that does not will never hand a key to Neovim. So report what does,
---and leave the choice of keys alone.
local function check_bindings()
  local bindings = tmux.root_key_table()
  if not bindings then
    warn('could not read the root key table, `tmux list-keys -T root` failed')
    return
  end

  local aware = {}
  for key, command in pairs(bindings) do
    if command:find('@pane-is-vim', 1, true) then
      table.insert(aware, key)
    end
  end

  if #aware == 0 then
    warn(
      "no tmux key binding reads `@pane-is-vim`, so tmux will handle the movement keys itself and never pass them to Neovim (see this plugin's README)"
    )
    return
  end

  table.sort(aware)
  ok('tmux keys that defer to Neovim via `@pane-is-vim`: %s', table.concat(aware, ', '))
end

local function check_session()
  local socket = tmux.socket()
  if not socket then
    info('$TMUX is not set, this Neovim is not running inside tmux')
    return
  end
  ok('tmux socket: %s', socket)

  local pane = tmux.pane_id()
  if not pane then
    warn('$TMUX_PANE is not set, the `@pane-is-vim` marker cannot be addressed')
    return
  end
  ok('$TMUX_PANE: %s', pane)

  if activate.is_nested() then
    info('`@pane-is-vim` was already set when this instance started, so an outer Neovim owns it')
  elseif tmux.get_pane_is_vim(pane) then
    ok('`@pane-is-vim` is set on this pane, tmux will forward keys to Neovim')
  else
    warn('`@pane-is-vim` is not set on this pane, tmux will swallow the movement keys')
  end

  check_bindings()
end

---Called by core under a header it emits itself, for every backend that
---validated rather than only the one in use, so this has to keep working when
---there is no tmux to talk to.
function M.report()
  check_binary()
  check_session()
  info('enable: %s', vim.inspect(config.options.enable))
  info('disable_nav_when_zoomed: %s', vim.inspect(config.options.disable_nav_when_zoomed))
  info('resize_amount: %s', vim.inspect(config.options.resize_amount))
  info('timeout: %sms', vim.inspect(config.options.timeout))
end

---Entry point for `:checkhealth smart-splits-backend-tmux`, for users who want
---to check the backend without going through core.
function M.check()
  vim.health.start('smart-splits-backend-tmux')
  M.report()
end

return M
