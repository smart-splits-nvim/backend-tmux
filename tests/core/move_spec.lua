local h = require('tests.helpers')

local backend = require('smart-splits-backend-tmux')

describe('move()', function()
  after_each(function()
    h.restore()
  end)

  it('moves to the neighbouring tmux pane', function()
    local state = h.reset_backend({ at_edge = { left = true } })
    assert.is_true(backend.move('right'))
    assert.are.same({ 'select-pane', '-R' }, state.first('select-pane'))
  end)

  it('maps every direction to its tmux flag', function()
    local flags = { left = '-L', right = '-R', up = '-U', down = '-D' }
    for direction, flag in pairs(flags) do
      local state = h.reset_backend()
      assert.is_true(backend.move(direction))
      assert.are.same({ 'select-pane', flag }, state.first('select-pane'))
    end
  end)

  describe('at the outer edge of tmux', function()
    it('does not move with at_edge = stop', function()
      local state = h.reset_backend({ at_edge = { left = true } })
      assert.is_false(backend.move('left', { at_edge = 'stop' }))
      assert.are.equal(0, state.count('select-pane'))
      assert.are.equal(0, state.count('split-window'))
    end)

    it('does not move when at_edge is absent', function()
      local state = h.reset_backend({ at_edge = { left = true } })
      assert.is_false(backend.move('left', {}))
      assert.is_false(backend.move('left'))
      assert.are.equal(0, state.count('select-pane'))
    end)

    it('wraps with at_edge = wrap, because select-pane already does', function()
      local state = h.reset_backend({ at_edge = { left = true }, panes = 2 })
      assert.is_true(backend.move('left', { at_edge = 'wrap' }))
      assert.are.same({ 'select-pane', '-L' }, state.first('select-pane'))
    end)

    it('leaves wrapping to core when tmux has a single pane', function()
      local state = h.reset_backend({ at_edge = { left = true, right = true, up = true, down = true }, panes = 1 })
      assert.is_false(backend.move('left', { at_edge = 'wrap' }))
      assert.are.equal(0, state.count('select-pane'))
    end)

    it('creates a tmux pane with at_edge = split', function()
      local splits = { left = '-hb', right = '-h', up = '-vb', down = '-v' }
      for direction, flags in pairs(splits) do
        local state = h.reset_backend({ at_edge = { [direction] = true }, panes = 1 })
        assert.is_true(backend.move(direction, { at_edge = 'split' }))
        assert.are.same({ 'split-window', flags, '-c', '#{pane_current_path}' }, state.first('split-window'), direction)
        assert.are.equal(2, state.panes)
      end
    end)

    it('reports failure when tmux refuses to split', function()
      local state = h.reset_backend({ at_edge = { right = true }, panes = 1, fail_on = { 'split-window' } })
      assert.is_false(backend.move('right', { at_edge = 'split' }))
      assert.are.equal(1, state.count('split-window'))
    end)
  end)

  describe('zoom', function()
    it('refuses to leave a zoomed pane by default', function()
      local state = h.reset_backend({ zoomed = true })
      assert.is_false(backend.move('right'))
      assert.are.equal(0, state.count('select-pane'))
    end)

    it('moves out of a zoomed pane when the option is off', function()
      local state = h.reset_backend({ zoomed = true })
      backend.setup({ disable_nav_when_zoomed = false })
      assert.is_true(backend.move('right'))
      assert.are.equal(0, state.count('display-message'))
      assert.are.same({ 'select-pane', '-R' }, state.first('select-pane'))
    end)
  end)

  it('returns false outside a tmux session, without shelling out', function()
    local state = h.reset_backend()
    h.leave_session()
    assert.is_false(backend.move('right'))
    assert.are.equal(0, #state.calls)
  end)

  it('returns false when disabled', function()
    local state = h.reset_backend()
    backend.setup({ enable = false })
    assert.is_false(backend.move('right'))
    assert.are.equal(0, #state.calls)
  end)

  it('returns false rather than throwing when tmux is unreachable', function()
    h.reset_backend({ fail = true })
    assert.is_false(backend.move('right'))
  end)
end)
