---The `tmux` CLI adapter. Every invocation names the server explicitly with
---`-S <socket>`, taken from `$TMUX`, so a Neovim that inherited a stale or
---foreign `$TMUX` can never drive the wrong server.
---
---Nothing here throws: a tmux that is missing, wedged or answering from another
---machine comes back as `false` or `nil`, and the backend degrades to plain
---Neovim movement.

local config = require('smart-splits-backend-tmux.config')

local M = {}

---@alias TmuxBackend.Direction 'left'|'right'|'up'|'down'

---`select-pane`/`resize-pane` direction flags.
local DIRECTION_KEYS = {
  left = 'L',
  right = 'R',
  up = 'U',
  down = 'D',
}

---`#{pane_at_*}` format variables, which answer "is there a pane that way?".
local EDGES = {
  left = 'left',
  right = 'right',
  up = 'top',
  down = 'bottom',
}

---`split-window` flags. `-b` puts the new pane before the current one, which is
---what "split towards the left/up" means. Matches the paired tmux bindings.
local SPLIT_FLAGS = {
  left = '-hb',
  right = '-h',
  up = '-vb',
  down = '-v',
}

M.DIRECTION_KEYS = DIRECTION_KEYS

---Run a tmux command and wait for it. Returns stdout and the exit code; the
---code is negative when the process could not be run at all.
---@param cmd string[]
---@param timeout integer
---@return string|nil stdout, integer code
local function default_runner(cmd, timeout)
  local ok, result = pcall(function()
    return vim.system(cmd, { text = true, timeout = timeout }):wait()
  end)
  if not ok or type(result) ~= 'table' then
    return nil, -1
  end
  return result.stdout or '', result.code
end

---Start a tmux command without waiting for it.
---@param cmd string[]
---@return boolean started
local function default_spawner(cmd)
  local ok, job = pcall(vim.fn.jobstart, cmd, { detach = true })
  return ok and type(job) == 'number' and job > 0
end

local runner = default_runner
local spawner = default_spawner

---Replace the process runners. Tests use this; nothing else should.
---@param run? fun(cmd: string[], timeout: integer):string|nil, integer
---@param spawn? fun(cmd: string[]):boolean
function M.set_runner(run, spawn)
  runner = run or default_runner
  spawner = spawn or default_spawner
end

function M.reset_runner()
  runner = default_runner
  spawner = default_spawner
end

---`$TMUX` is `<socket>,<pid>,<session>`.
---@return string|nil
function M.socket()
  local tmux = vim.env.TMUX
  if type(tmux) ~= 'string' or #tmux == 0 then
    return nil
  end
  local socket = vim.split(tmux, ',', { trimempty = true })[1]
  if not socket or #socket == 0 then
    return nil
  end
  return socket
end

---@return boolean
function M.is_in_session()
  return M.socket() ~= nil
end

---The pane Neovim is running in, as tmux exports it.
---@return string|nil
function M.pane_id()
  local pane = vim.env.TMUX_PANE
  if type(pane) ~= 'string' or #pane == 0 then
    return nil
  end
  return pane
end

---The full argv for a tmux command, or nil when there is no server to talk to.
---Inside Flatpak the multiplexer lives on the host, so the call is relayed.
---@param args (string|number)[]
---@return string[]|nil
function M.argv(args)
  local socket = M.socket()
  if not socket then
    return nil
  end
  local cmd = vim.env.FLATPAK_ID and { 'flatpak-spawn', '--host', 'tmux', '-S', socket } or { 'tmux', '-S', socket }
  for _, arg in ipairs(args) do
    table.insert(cmd, tostring(arg))
  end
  return cmd
end

---@param args (string|number)[]
---@return string|nil stdout, integer code
function M.exec(args)
  local cmd = M.argv(args)
  if not cmd then
    return nil, -1
  end
  return runner(cmd, config.options.timeout)
end

---@param args (string|number)[]
---@return boolean succeeded
function M.exec_ok(args)
  local _, code = M.exec(args)
  return code == 0
end

---@param args (string|number)[]
---@return string[]|nil lines
function M.exec_lines(args)
  local out, code = M.exec(args)
  if code ~= 0 or not out then
    return nil
  end
  return vim.split(out, '\n', { trimempty = true })
end

---Start a tmux command and do not wait for it. For work that has to outlive the
---Neovim process doing it, which is why `VimLeavePre` uses it.
---@param args (string|number)[]
---@return boolean started
function M.spawn(args)
  local cmd = M.argv(args)
  if not cmd then
    return false
  end
  return spawner(cmd)
end

---Is the active pane against the outer edge of its tmux window, with no pane to
---move to? tmux offers no "move without wrapping", so this has to be asked
---before acting rather than inferred from the exit code afterwards.
---@param direction TmuxBackend.Direction
---@return boolean
function M.at_edge(direction)
  local edge = EDGES[direction]
  if not edge then
    return false
  end
  -- filters the window's panes down to "active and against this edge", so one
  -- line back means yes and no lines means no
  local filter = string.format('#{&&:#{pane_active},#{pane_at_%s}}', edge)
  local result = M.exec_lines({ 'list-panes', '-f', filter })
  return type(result) == 'table' and #result == 1
end

---@return integer
function M.pane_count()
  local panes = M.exec_lines({ 'list-panes', '-F', '#{pane_id}' })
  return panes and #panes or 0
end

---@return boolean
function M.is_zoomed()
  local out, code = M.exec({ 'display-message', '-p', '#{window_zoomed_flag}' })
  if code ~= 0 or not out then
    return false
  end
  return vim.trim(out) == '1'
end

---@param direction TmuxBackend.Direction
---@return boolean
function M.select_pane(direction)
  local key = DIRECTION_KEYS[direction]
  if not key then
    return false
  end
  return M.exec_ok({ 'select-pane', '-' .. key })
end

---@param direction TmuxBackend.Direction
---@return boolean
function M.split_pane(direction)
  local flags = SPLIT_FLAGS[direction]
  if not flags then
    return false
  end
  -- new panes start where the current one is, the same as the tmux-side bindings
  return M.exec_ok({ 'split-window', flags, '-c', '#{pane_current_path}' })
end

---@param direction TmuxBackend.Direction
---@param amount integer
---@return boolean
function M.resize_pane(direction, amount)
  local key = DIRECTION_KEYS[direction]
  if not key then
    return false
  end
  return M.exec_ok({ 'resize-pane', '-' .. key, amount })
end

---Read the `@pane-is-vim` marker the tmux bindings branch on.
---@param pane string
---@return boolean
function M.get_pane_is_vim(pane)
  local out = M.exec({ 'show-options', '-pqvt', pane, '@pane-is-vim' })
  return tonumber(vim.trim(out or '')) == 1
end

---@param pane string
---@param value boolean
---@return boolean
function M.set_pane_is_vim(pane, value)
  return M.exec_ok({ 'set-option', '-p', '-t', pane, '@pane-is-vim', value and '1' or '0' })
end

---As `set_pane_is_vim`, but fire-and-forget, for clearing the marker from
---`VimLeavePre`: the write has to survive the process that asked for it.
---@param pane string
---@param value boolean
---@return boolean started
function M.set_pane_is_vim_detached(pane, value)
  return M.spawn({ 'set-option', '-p', '-t', pane, '@pane-is-vim', value and '1' or '0' })
end

---The root key table, as `key -> command`. Used by `health()` to check that the
---tmux half of the integration is actually bound.
---@return table<string, string>|nil
function M.root_key_table()
  local lines = M.exec_lines({ 'list-keys', '-T', 'root' })
  if not lines then
    return nil
  end
  local bindings = {}
  for _, line in ipairs(lines) do
    local key, command = line:match('^bind%-key.*%-T%s+root%s+(%S+)%s+(.+)$')
    if key then
      bindings[key] = command
    end
  end
  return bindings
end

---The `tmux -V` banner. Answers outside a session too, so `health()` can tell
---"tmux is not installed" apart from "you are not in tmux right now".
---@return string|nil version
function M.version()
  local cmd = M.argv({ '-V' }) or { 'tmux', '-V' }
  local out, code = runner(cmd, config.options.timeout)
  if code ~= 0 or not out or #vim.trim(out) == 0 then
    return nil
  end
  return vim.trim(out)
end

return M
