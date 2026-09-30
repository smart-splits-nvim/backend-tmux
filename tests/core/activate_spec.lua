local h = require('tests.helpers')

local activate = require('smart-splits-backend-tmux.activate')

---The value the fake tmux server currently holds for `@pane-is-vim`.
---@param state table
---@return string|nil
local function marker(state)
  return state.options['@pane-is-vim']
end

---@param state table
---@return string|nil
local function detached_marker(state)
  local last = state.spawned[#state.spawned]
  return last and last[#last]
end

describe('activate()', function()
  after_each(function()
    h.restore()
  end)

  it('marks the pane as running Neovim', function()
    local state = h.reset_backend()
    activate.activate()
    assert.are.same({ 'set-option', '-p', '-t', h.PANE, '@pane-is-vim', '1' }, state.first('set-option'))
    assert.are.equal('1', marker(state))
  end)

  it('clears the marker on exit, detached so the write outlives Neovim', function()
    local state = h.reset_backend()
    activate.activate()
    vim.api.nvim_exec_autocmds('VimLeavePre', {})
    assert.are.equal('0', detached_marker(state))
  end)

  it('hands the keys back while suspended and takes them again on resume', function()
    local state = h.reset_backend()
    activate.activate()
    vim.api.nvim_exec_autocmds('VimSuspend', {})
    assert.are.equal('0', marker(state))
    vim.api.nvim_exec_autocmds('VimResume', {})
    assert.are.equal('1', marker(state))
  end)

  describe('nested inside another Neovim', function()
    it("leaves the outer instance's marker alone", function()
      local state = h.reset_backend({ options = { ['@pane-is-vim'] = '1' } })
      activate.activate()
      assert.is_true(activate.is_nested())
      assert.are.equal(0, state.count('set-option'))
      assert.are.equal('1', marker(state))
    end)

    it('does not clear the marker when the inner instance quits', function()
      local state = h.reset_backend({ options = { ['@pane-is-vim'] = '1' } })
      activate.activate()
      vim.api.nvim_exec_autocmds('VimLeavePre', {})
      vim.api.nvim_exec_autocmds('VimSuspend', {})
      assert.are.equal(0, #state.spawned)
      assert.are.equal('1', marker(state))
    end)
  end)

  it('does nothing outside a tmux session', function()
    local state = h.reset_backend()
    h.leave_session()
    activate.activate()
    assert.are.equal(0, #state.calls)
  end)

  it('does nothing when $TMUX_PANE is not set', function()
    local state = h.reset_backend()
    vim.env.TMUX_PANE = nil
    activate.activate()
    assert.are.equal(0, #state.calls)
  end)

  it('is safe to call twice', function()
    local state = h.reset_backend()
    activate.activate()
    activate.activate()
    vim.api.nvim_exec_autocmds('VimSuspend', {})
    assert.are.equal('0', marker(state))
    assert.are.equal(3, state.count('set-option'))
  end)
end)
