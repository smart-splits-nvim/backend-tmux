---Test scaffolding: a fake `tmux` process runner, plus the environment a tmux
---session would have put Neovim in. Every assertion in `tests/core` is made
---against this rather than a real server, so the suite is hermetic and runs the
---same inside and outside tmux. `tests/integration` covers the real thing.

local activate = require('smart-splits-backend-tmux.activate')
local config = require('smart-splits-backend-tmux.config')
local tmux = require('smart-splits-backend-tmux.tmux')

local M = {}

M.SOCKET = '/tmp/smart-splits-backend-tmux-tests.sock'
M.PANE = '%1'

---Pretend Neovim was started by a tmux server.
---@param opts? { socket?: string, pane?: string }
function M.enter_session(opts)
  opts = opts or {}
  vim.env.TMUX = ('%s,1234,0'):format(opts.socket or M.SOCKET)
  vim.env.TMUX_PANE = opts.pane or M.PANE
end

function M.leave_session()
  vim.env.TMUX = nil
  vim.env.TMUX_PANE = nil
  vim.env.FLATPAK_ID = nil
end

---The arguments of a tmux invocation, with the `tmux -S <socket>` prefix (or
---its `flatpak-spawn` equivalent) stripped off.
---@param cmd string[]
---@return string[]
function M.tmux_args(cmd)
  for index, arg in ipairs(cmd) do
    if arg == '-S' then
      return vim.list_slice(cmd, index + 2)
    end
  end
  return vim.list_slice(cmd, 2)
end

---@param args string[]
---@param flag string
---@return string|nil
local function flag_value(args, flag)
  for index, arg in ipairs(args) do
    if arg == flag then
      return args[index + 1]
    end
  end
  return nil
end

local EDGE_DIRECTIONS = { left = 'left', right = 'right', top = 'up', bottom = 'down' }

---A fake tmux server: it answers the queries the backend makes and records
---everything the backend sent it.
---@param opts? table
function M.fake_tmux(opts)
  opts = opts or {}

  local state = {
    ---every invocation, as the arguments after `tmux -S <socket>`
    calls = {},
    ---every detached invocation, same form
    spawned = {},
    ---which edges of the tmux window the active pane sits against
    at_edge = opts.at_edge or {},
    panes = opts.panes or 2,
    zoomed = opts.zoomed or false,
    ---pane-local options, e.g. `@pane-is-vim`
    options = opts.options or {},
    ---`tmux list-keys -T root` output
    keys = opts.keys or {},
    ---make every invocation fail, as an unreachable server would
    fail = opts.fail or false,
    ---make only these subcommands fail
    fail_on = opts.fail_on or {},
  }

  ---@param subcommand string
  ---@return string[][]
  function state.sent(subcommand)
    return vim.tbl_filter(function(args)
      return args[1] == subcommand
    end, state.calls)
  end

  ---@param subcommand string
  ---@return string[]|nil
  function state.first(subcommand)
    return state.sent(subcommand)[1]
  end

  ---@param subcommand string
  ---@return integer
  function state.count(subcommand)
    return #state.sent(subcommand)
  end

  local handlers = {
    ['list-panes'] = function(args)
      local filter = flag_value(args, '-f')
      if filter then
        local direction = EDGE_DIRECTIONS[filter:match('pane_at_(%a+)') or '']
        return state.at_edge[direction] and '%1\n' or ''
      end
      local lines = {}
      for index = 1, state.panes do
        table.insert(lines, ('%%%d'):format(index))
      end
      return table.concat(lines, '\n') .. '\n'
    end,
    ['display-message'] = function(args)
      if vim.tbl_contains(args, '#{window_zoomed_flag}') then
        return state.zoomed and '1\n' or '0\n'
      end
      return '\n'
    end,
    ['split-window'] = function()
      state.panes = state.panes + 1
      return ''
    end,
    ['show-options'] = function(args)
      return tostring(state.options[args[#args]] or '') .. '\n'
    end,
    ['set-option'] = function(args)
      state.options[args[#args - 1]] = args[#args]
      return ''
    end,
    ['list-keys'] = function()
      return table.concat(state.keys, '\n') .. '\n'
    end,
    ['-V'] = function()
      return 'tmux 3.4\n'
    end,
  }

  tmux.set_runner(function(cmd)
    local args = M.tmux_args(cmd)
    table.insert(state.calls, args)
    if state.fail or vim.tbl_contains(state.fail_on, args[1]) then
      return '', 1
    end
    local handler = handlers[args[1]]
    return handler and handler(args) or '', 0
  end, function(cmd)
    table.insert(state.spawned, M.tmux_args(cmd))
    return not state.fail
  end)

  return state
end

---A `tmux list-keys -T root` listing matching the bindings this backend pairs
---with, so `health()` has something realistic to parse.
---@return string[]
function M.paired_key_bindings()
  local lines = {}
  local template =
    'bind-key    -T root         %s                 if-shell -F "#{@pane-is-vim}" { send-keys %s } { %s }'
  for _, key in ipairs({ 'C-h', 'C-j', 'C-k', 'C-l' }) do
    table.insert(lines, template:format(key, key, 'select-pane -L'))
  end
  for _, key in ipairs({ 'M-h', 'M-j', 'M-k', 'M-l' }) do
    table.insert(lines, template:format(key, key, 'resize-pane -L 3'))
  end
  return lines
end

---Put the backend back the way a fresh Neovim would find it: inside a tmux
---session, with a fake server answering.
---@param opts? table
function M.reset_backend(opts)
  config.setup()
  activate.reset()
  M.leave_session()
  M.enter_session()
  return M.fake_tmux(opts)
end

---Undo everything `reset_backend` set up.
function M.restore()
  tmux.reset_runner()
  activate.reset()
  config.setup()
  M.leave_session()
end

return M
