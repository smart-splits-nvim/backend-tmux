local h = require('tests.helpers')
local tmux = require('smart-splits-backend-tmux.tmux')

describe('tmux adapter', function()
  before_each(function()
    h.reset_backend()
  end)

  after_each(function()
    h.restore()
  end)

  describe('socket()', function()
    it('takes the first field of $TMUX', function()
      vim.env.TMUX = '/private/tmp/tmux-501/default,91234,0'
      assert.are.equal('/private/tmp/tmux-501/default', tmux.socket())
    end)

    it('is nil when $TMUX is unset or empty', function()
      h.leave_session()
      assert.is_nil(tmux.socket())
      vim.env.TMUX = ''
      assert.is_nil(tmux.socket())
    end)
  end)

  describe('argv()', function()
    it('targets the server named by $TMUX', function()
      vim.env.TMUX = '/tmp/some.sock,1,0'
      assert.are.same({ 'tmux', '-S', '/tmp/some.sock', 'list-panes' }, tmux.argv({ 'list-panes' }))
    end)

    it('relays through the host under Flatpak', function()
      vim.env.TMUX = '/tmp/some.sock,1,0'
      vim.env.FLATPAK_ID = 'io.neovim.nvim'
      assert.are.same(
        { 'flatpak-spawn', '--host', 'tmux', '-S', '/tmp/some.sock', 'select-pane', '-L' },
        tmux.argv({ 'select-pane', '-L' })
      )
    end)

    it('stringifies numeric arguments', function()
      assert.are.same({ 'resize-pane', '-L', '3' }, h.tmux_args(tmux.argv({ 'resize-pane', '-L', 3 })))
    end)

    it('is nil outside a session', function()
      h.leave_session()
      assert.is_nil(tmux.argv({ 'list-panes' }))
    end)
  end)

  describe('at_edge()', function()
    it('asks whether the active pane is against that edge', function()
      local state = h.reset_backend({ at_edge = { up = true } })
      assert.is_true(tmux.at_edge('up'))
      assert.are.same({ 'list-panes', '-f', '#{&&:#{pane_active},#{pane_at_top}}' }, state.first('list-panes'))
    end)

    it('maps every direction to its tmux edge', function()
      local edges = { left = 'left', right = 'right', up = 'top', down = 'bottom' }
      for direction, edge in pairs(edges) do
        local state = h.reset_backend()
        tmux.at_edge(direction)
        assert.are.equal(('#{&&:#{pane_active},#{pane_at_%s}}'):format(edge), state.first('list-panes')[3])
      end
    end)

    it('is false when there is a pane that way', function()
      h.reset_backend({ at_edge = { left = true } })
      assert.is_false(tmux.at_edge('right'))
    end)

    it('is false when tmux cannot be reached', function()
      h.reset_backend({ at_edge = { left = true }, fail = true })
      assert.is_false(tmux.at_edge('left'))
    end)
  end)

  describe('is_zoomed()', function()
    it('reads the window zoom flag', function()
      local state = h.reset_backend({ zoomed = true })
      assert.is_true(tmux.is_zoomed())
      assert.are.same({ 'display-message', '-p', '#{window_zoomed_flag}' }, state.first('display-message'))
    end)

    it('is false when not zoomed, and when tmux fails', function()
      h.reset_backend({ zoomed = false })
      assert.is_false(tmux.is_zoomed())
      h.reset_backend({ zoomed = true, fail = true })
      assert.is_false(tmux.is_zoomed())
    end)
  end)

  describe('pane markers', function()
    it('round-trips `@pane-is-vim`', function()
      local state = h.reset_backend()
      assert.is_false(tmux.get_pane_is_vim('%1'))
      assert.is_true(tmux.set_pane_is_vim('%1', true))
      assert.are.same({ 'set-option', '-p', '-t', '%1', '@pane-is-vim', '1' }, state.first('set-option'))
      assert.is_true(tmux.get_pane_is_vim('%1'))
      tmux.set_pane_is_vim('%1', false)
      assert.is_false(tmux.get_pane_is_vim('%1'))
    end)

    it('clears detached, so the write outlives the process', function()
      local state = h.reset_backend()
      assert.is_true(tmux.set_pane_is_vim_detached('%1', false))
      assert.are.equal(0, #state.calls)
      assert.are.same({ 'set-option', '-p', '-t', '%1', '@pane-is-vim', '0' }, state.spawned[1])
    end)
  end)

  describe('root_key_table()', function()
    it('parses `list-keys -T root` into key -> command', function()
      h.reset_backend({ keys = h.paired_key_bindings() })
      local bindings = tmux.root_key_table()
      assert.is_not_nil(bindings)
      assert.is_truthy(bindings['C-h']:find('@pane-is-vim', 1, true))
      assert.is_truthy(bindings['M-l']:find('resize-pane', 1, true))
      assert.is_nil(bindings['C-a'])
    end)

    it('is nil when tmux cannot be reached', function()
      h.reset_backend({ fail = true })
      assert.is_nil(tmux.root_key_table())
    end)
  end)

  it('never talks to a server it was not told about', function()
    h.leave_session()
    local state = h.fake_tmux()
    assert.is_false(tmux.select_pane('left'))
    assert.is_false(tmux.resize_pane('left', 3))
    assert.is_false(tmux.split_pane('left'))
    assert.are.equal(0, #state.calls)
  end)
end)
