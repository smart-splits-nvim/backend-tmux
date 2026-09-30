---The tmux half, `smart-splits.tmux`, run against a real tmux server.
---
---What it emits is a tmux command string inside a tmux command string, so the
---only assertion worth making is that tmux itself accepts it and reads the
---bindings back the way the Neovim half expects. Hence a real server rather
---than a string comparison.

local script = vim.fn.getcwd() .. '/smart-splits.tmux'

local socket

---@param args string[]
---@return string stdout, integer code
local function tmux(args)
  local cmd = vim.list_extend({ 'tmux', '-S', socket }, args)
  local result = vim.system(cmd, { text = true, timeout = 5000 }):wait()
  return vim.trim(result.stdout or ''), result.code
end

---Run the plugin script the way TPM would: from inside the session, so plain
---`tmux` calls reach this server.
---@return integer code, string stderr
local function run_plugin()
  local result = vim
    .system({ script }, {
      text = true,
      timeout = 10000,
      env = { TMUX = ('%s,0,0'):format(socket) },
    })
    :wait()
  return result.code, vim.trim(result.stderr or '')
end

---The command bound to `key` in `key_table`. `list-keys` takes a key argument
---but answers nothing for it, so list the table and pick the line out.
---@param key string
---@param key_table? string
---@return string|nil
local function binding(key, key_table)
  local out, code = tmux({ 'list-keys', '-T', key_table or 'root' })
  if code ~= 0 then
    return nil
  end
  for _, line in ipairs(vim.split(out, '\n', { trimempty = true })) do
    local bound, command = line:match('^bind%-key.*%-T%s+%S+%s+(%S+)%s+(.+)$')
    if bound == key then
      return command
    end
  end
  return nil
end

if vim.fn.executable('tmux') ~= 1 then
  describe('smart-splits.tmux', function()
    pending('tmux is not installed')
  end)
  return
end

describe('smart-splits.tmux', function()
  before_each(function()
    socket = vim.fn.tempname()
    local _, code = tmux({ '-f', '/dev/null', 'new-session', '-d', '-x', '200', '-y', '50' })
    assert.are.equal(0, code, 'could not start a tmux server on ' .. socket)
  end)

  after_each(function()
    tmux({ 'kill-server' })
  end)

  it('is executable, as TPM requires', function()
    assert.are.equal(1, vim.fn.executable(script))
  end)

  it('binds the default keys, all deferring to Neovim', function()
    local code, stderr = run_plugin()
    assert.are.equal(0, code, stderr)

    for _, key in ipairs({ 'C-h', 'C-j', 'C-k', 'C-l', 'M-h', 'M-j', 'M-k', 'M-l' }) do
      local bound = binding(key)
      assert.is_not_nil(bound, key .. ' is not bound')
      assert.is_truthy(bound:find('@pane-is-vim', 1, true), key .. ': ' .. bound)
      assert.is_truthy(bound:find('send-keys ' .. key, 1, true), key .. ': ' .. bound)
    end
  end)

  it('resizes by the configured step', function()
    tmux({ 'set-option', '-g', '@smart-splits_resize_step_size', '7' })
    assert.are.equal(0, (run_plugin()))
    assert.is_truthy(binding('M-l'):find('resize-pane -R 7', 1, true), binding('M-l'))
  end)

  it('binds whichever keys it is told to', function()
    tmux({ 'set-option', '-g', '@smart-splits_move_left_key', 'M-Left' })
    tmux({ 'set-option', '-g', '@smart-splits_resize_left_key', 'C-Left' })
    assert.are.equal(0, (run_plugin()))

    assert.is_truthy(binding('M-Left'):find('@pane-is-vim', 1, true))
    assert.is_truthy(binding('C-Left'):find('resize-pane -L', 1, true))
    -- the default it replaced is left alone
    assert.is_nil(binding('C-h'))
  end)

  describe('at_edge', function()
    it('wraps by default, which is what select-pane does', function()
      assert.are.equal(0, (run_plugin()))
      local bound = binding('C-l')
      assert.is_truthy(bound:find('select-pane -R', 1, true), bound)
      assert.is_falsy(bound:find('pane_at_right', 1, true), bound)
      assert.is_falsy(bound:find('split-window', 1, true), bound)
    end)

    it('stops at the edge when asked', function()
      tmux({ 'set-option', '-g', '@smart-splits_at_edge', 'stop' })
      assert.are.equal(0, (run_plugin()))
      local bound = binding('C-l')
      assert.is_truthy(bound:find('pane_at_right', 1, true), bound)
      assert.is_falsy(bound:find('split-window', 1, true), bound)
    end)

    it('splits at the edge when asked, inheriting the directory', function()
      tmux({ 'set-option', '-g', '@smart-splits_at_edge', 'split' })
      assert.are.equal(0, (run_plugin()))

      local splits = { ['C-h'] = '-hb', ['C-j'] = '-v', ['C-k'] = '-vb', ['C-l'] = '-h' }
      for key, flags in pairs(splits) do
        local bound = binding(key)
        assert.is_truthy(bound:find('split-window ' .. flags, 1, true), key .. ': ' .. bound)
        assert.is_truthy(bound:find('pane_current_path', 1, true), key .. ': ' .. bound)
      end
    end)

    it('falls back to wrapping when given a value it does not know', function()
      tmux({ 'set-option', '-g', '@smart-splits_at_edge', 'nonsense' })
      assert.are.equal(0, (run_plugin()))
      local bound = binding('C-l')
      assert.is_truthy(bound:find('select-pane -R', 1, true), bound)
      assert.is_falsy(bound:find('pane_at_right', 1, true), bound)
    end)
  end)

  describe('copy mode', function()
    it('navigates panes directly, with no Neovim to defer to', function()
      assert.are.equal(0, (run_plugin()))
      local bound = binding('C-l', 'copy-mode-vi')
      assert.is_truthy(bound:find('select-pane -R', 1, true), bound)
      assert.is_falsy(bound:find('@pane-is-vim', 1, true), bound)
    end)

    it('never splits, since that would drop out of copy mode', function()
      tmux({ 'set-option', '-g', '@smart-splits_at_edge', 'split' })
      assert.are.equal(0, (run_plugin()))
      local bound = binding('C-l', 'copy-mode-vi')
      assert.is_falsy(bound:find('split-window', 1, true), bound)
      assert.is_truthy(bound:find('pane_at_right', 1, true), bound)
    end)
  end)

  it('emits bindings the Neovim half recognises as deferring to it', function()
    assert.are.equal(0, (run_plugin()))
    local tmux_adapter = require('smart-splits-backend-tmux.tmux')
    vim.env.TMUX = ('%s,0,0'):format(socket)
    local bindings = tmux_adapter.root_key_table()
    vim.env.TMUX = nil

    assert.is_not_nil(bindings)
    for _, key in ipairs({ 'C-h', 'C-j', 'C-k', 'C-l', 'M-h', 'M-j', 'M-k', 'M-l' }) do
      assert.is_not_nil(bindings[key], key .. ' was not parsed out of list-keys')
      assert.is_truthy(bindings[key]:find('@pane-is-vim', 1, true), key .. ': ' .. bindings[key])
    end
  end)
end)
