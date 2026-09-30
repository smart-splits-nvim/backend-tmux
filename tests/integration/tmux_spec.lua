---Integration tests against a real tmux server on a private socket.
---
---The fakes in `tests/core` pin down what the backend *sends*; these pin down
---that tmux answers the way the backend assumes. Nothing here touches the
---developer's own tmux: each test gets a fresh server, started with `-f
---/dev/null` so no user config can change the layout out from under it.

local activate = require('smart-splits-backend-tmux.activate')
local backend = require('smart-splits-backend-tmux')
local tmux = require('smart-splits-backend-tmux.tmux')

local socket

---Run a tmux command against the test server, bypassing the backend.
---@param args string[]
---@return string stdout, integer code
local function tmux_raw(args)
  local cmd = vim.list_extend({ 'tmux', '-S', socket }, args)
  local result = vim.system(cmd, { text = true, timeout = 5000 }):wait()
  return vim.trim(result.stdout or ''), result.code
end

---@param format string
---@return string[]
local function list_panes(format)
  local out = tmux_raw({ 'list-panes', '-F', format })
  return vim.split(out, '\n', { trimempty = true })
end

---@return string[]
local function pane_ids()
  return list_panes('#{pane_id}')
end

---@return string|nil
local function active_pane()
  for _, line in ipairs(list_panes('#{pane_active}#{pane_id}')) do
    local active, id = line:match('^(%d)(.+)$')
    if active == '1' then
      return id
    end
  end
  return nil
end

---@param pane string
---@return integer
local function pane_width(pane)
  local out = tmux_raw({ 'display-message', '-p', '-t', pane, '#{pane_width}' })
  return tonumber(out) or 0
end

---@param pane string
---@return string
local function pane_is_vim(pane)
  return (tmux_raw({ 'show-options', '-pqvt', pane, '@pane-is-vim' }))
end

if vim.fn.executable('tmux') ~= 1 then
  describe('tmux integration', function()
    pending('tmux is not installed')
  end)
  return
end

describe('tmux integration', function()
  ---The pane Neovim would be running in.
  local pane

  before_each(function()
    socket = vim.fn.tempname()
    -- `new-session` refuses to nest, so start the server before `$TMUX` is set
    vim.env.TMUX = nil
    vim.env.TMUX_PANE = nil
    local _, code = tmux_raw({ '-f', '/dev/null', 'new-session', '-d', '-x', '200', '-y', '50' })
    assert.are.equal(0, code, 'could not start a tmux server on ' .. socket)

    pane = pane_ids()[1]
    local pid = tmux_raw({ 'display-message', '-p', '-t', pane, '#{pid}' })
    -- exactly what tmux exports into a pane's environment
    vim.env.TMUX = ('%s,%s,0'):format(socket, pid)
    vim.env.TMUX_PANE = pane

    tmux.reset_runner()
    activate.reset()
    backend.setup()
  end)

  after_each(function()
    tmux_raw({ 'kill-server' })
    vim.env.TMUX = nil
    vim.env.TMUX_PANE = nil
    activate.reset()
    backend.setup()
  end)

  it('detects the session it was started from', function()
    assert.is_true(backend.detect())
    assert.are.equal(socket, tmux.socket())
  end)

  it('knows a lone pane is against every edge', function()
    for _, direction in ipairs({ 'left', 'right', 'up', 'down' }) do
      assert.is_true(tmux.at_edge(direction), direction)
    end
  end)

  it('does not move, or wrap, when tmux has nowhere to go', function()
    assert.is_false(backend.move('right'))
    assert.is_false(backend.move('right', { at_edge = 'stop' }))
    assert.is_false(backend.move('right', { at_edge = 'wrap' }))
    assert.are.equal(1, #pane_ids())
  end)

  it('creates a tmux pane at the edge with at_edge = split', function()
    assert.is_true(backend.move('right', { at_edge = 'split' }))
    assert.are.equal(2, #pane_ids())
    -- tmux focuses the new pane, so ask about ours again before probing edges
    tmux_raw({ 'select-pane', '-t', pane })
    assert.is_false(tmux.at_edge('right'))
    assert.is_true(tmux.at_edge('left'))
  end)

  it('splits before the current pane for left and up', function()
    assert.is_true(backend.move('left', { at_edge = 'split' }))
    tmux_raw({ 'select-pane', '-t', pane })
    assert.is_false(tmux.at_edge('left'))
    assert.is_true(tmux.at_edge('right'))

    assert.is_true(backend.move('up', { at_edge = 'split' }))
    tmux_raw({ 'select-pane', '-t', pane })
    assert.is_false(tmux.at_edge('up'))
    assert.is_true(tmux.at_edge('down'))
  end)

  it('moves to the neighbouring pane', function()
    assert.is_true(backend.move('right', { at_edge = 'split' }))
    local neighbour = active_pane()
    assert.are_not.equal(pane, neighbour)

    -- focus is on the new pane; put it back on ours and walk across
    tmux_raw({ 'select-pane', '-t', pane })
    assert.are.equal(pane, active_pane())
    assert.is_true(backend.move('right'))
    assert.are.equal(neighbour, active_pane())
  end)

  it('wraps at the edge, because select-pane already does', function()
    assert.is_true(backend.move('right', { at_edge = 'split' }))
    local neighbour = active_pane()
    tmux_raw({ 'select-pane', '-t', pane })

    assert.is_true(backend.move('left', { at_edge = 'wrap' }))
    assert.are.equal(neighbour, active_pane())
  end)

  it('resizes the pane by the requested number of cells', function()
    assert.is_true(backend.move('right', { at_edge = 'split' }))
    tmux_raw({ 'select-pane', '-t', pane })
    local before = pane_width(pane)

    assert.is_true(backend.resize('right', { amount = 5 }))
    assert.are.equal(before + 5, pane_width(pane))

    assert.is_true(backend.resize('left', { amount = 5 }))
    assert.are.equal(before, pane_width(pane))
  end)

  it('refuses to navigate out of a zoomed pane', function()
    assert.is_true(backend.move('right', { at_edge = 'split' }))
    tmux_raw({ 'select-pane', '-t', pane })
    tmux_raw({ 'resize-pane', '-Z', '-t', pane })
    assert.is_true(tmux.is_zoomed())
    assert.is_false(backend.move('right'))

    -- with the guard off it still will not move: a zoomed pane fills its
    -- window, so tmux reports it against every edge
    backend.setup({ disable_nav_when_zoomed = false })
    assert.is_false(backend.move('right'))

    tmux_raw({ 'resize-pane', '-Z', '-t', pane })
    assert.is_false(tmux.is_zoomed())
    assert.is_true(backend.move('right'))
  end)

  describe('the `@pane-is-vim` marker', function()
    it('is set while Neovim owns the pane and cleared when it leaves', function()
      assert.are.equal('', pane_is_vim(pane))
      activate.activate()
      assert.are.equal('1', pane_is_vim(pane))

      vim.api.nvim_exec_autocmds('VimLeavePre', {})
      -- cleared by a detached process, so it lands slightly after we ask
      local cleared = vim.wait(5000, function()
        return pane_is_vim(pane) == '0'
      end, 50)
      assert.is_true(cleared, 'marker was ' .. pane_is_vim(pane))
    end)

    it('follows suspend and resume', function()
      activate.activate()
      vim.api.nvim_exec_autocmds('VimSuspend', {})
      assert.are.equal('0', pane_is_vim(pane))
      vim.api.nvim_exec_autocmds('VimResume', {})
      assert.are.equal('1', pane_is_vim(pane))
    end)

    it('is left to the outer instance when Neovim is nested', function()
      tmux_raw({ 'set-option', '-p', '-t', pane, '@pane-is-vim', '1' })
      activate.activate()
      assert.is_true(activate.is_nested())

      vim.api.nvim_exec_autocmds('VimLeavePre', {})
      vim.wait(200)
      assert.are.equal('1', pane_is_vim(pane))
    end)
  end)

  it('reports a healthy setup', function()
    activate.activate()
    for _, key in ipairs({ 'C-h', 'C-j', 'C-k', 'C-l' }) do
      tmux_raw({ 'bind-key', '-n', key, 'if-shell', '-F', '#{@pane-is-vim}', 'send-keys ' .. key, 'select-pane -L' })
    end
    for _, key in ipairs({ 'M-h', 'M-j', 'M-k', 'M-l' }) do
      tmux_raw({ 'bind-key', '-n', key, 'if-shell', '-F', '#{@pane-is-vim}', 'send-keys ' .. key, 'resize-pane -L 3' })
    end

    local reported = {}
    local original = vim.health
    local function record(level)
      return function(message)
        table.insert(reported, level .. ': ' .. tostring(message))
      end
    end
    vim.health = {
      start = record('start'),
      ok = record('ok'),
      info = record('info'),
      warn = record('warn'),
      error = record('error'),
    }
    local ok, err = pcall(backend.health)
    vim.health = original
    assert(ok, err)

    local joined = table.concat(reported, '\n')
    assert.is_truthy(joined:find('ok: tmux socket: ' .. socket, 1, true), joined)
    assert.is_truthy(joined:find('ok: $TMUX_PANE: ' .. pane, 1, true), joined)
    assert.is_truthy(joined:find('`@pane-is-vim` is set on this pane', 1, true), joined)
    assert.is_truthy(joined:find('ok: tmux ', 1, true), joined)
    -- parsed straight out of a real `list-keys -T root`
    assert.is_truthy(joined:find('ok: tmux keys that defer to Neovim via `@pane-is-vim`:', 1, true), joined)
    assert.is_truthy(joined:find('C-h, C-j, C-k, C-l, M-h, M-j, M-k, M-l', 1, true), joined)
  end)
end)
