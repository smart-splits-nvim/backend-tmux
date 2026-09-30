local h = require('tests.helpers')

local backend = require('smart-splits-backend-tmux')

describe('resize()', function()
  after_each(function()
    h.restore()
  end)

  it('resizes by the amount core resolved', function()
    local state = h.reset_backend()
    assert.is_true(backend.resize('right', { amount = 5 }))
    assert.are.same({ 'resize-pane', '-R', '5' }, state.first('resize-pane'))
  end)

  it('maps every direction to its tmux flag', function()
    local flags = { left = '-L', right = '-R', up = '-U', down = '-D' }
    for direction, flag in pairs(flags) do
      local state = h.reset_backend()
      assert.is_true(backend.resize(direction, { amount = 1 }))
      assert.are.same({ 'resize-pane', flag, '1' }, state.first('resize-pane'))
    end
  end)

  it('falls back to its own default when no amount is given', function()
    local state = h.reset_backend()
    assert.is_true(backend.resize('down', {}))
    assert.is_true(backend.resize('down'))
    assert.are.same({ 'resize-pane', '-D', '3' }, state.first('resize-pane'))
    assert.are.equal(2, state.count('resize-pane'))
  end)

  it('takes the default from config', function()
    local state = h.reset_backend()
    backend.setup({ resize_amount = 10 })
    assert.is_true(backend.resize('up'))
    assert.are.same({ 'resize-pane', '-U', '10' }, state.first('resize-pane'))
  end)

  it('returns false outside a tmux session, without shelling out', function()
    local state = h.reset_backend()
    h.leave_session()
    assert.is_false(backend.resize('up'))
    assert.are.equal(0, #state.calls)
  end)

  it('returns false when disabled', function()
    local state = h.reset_backend()
    backend.setup({ enable = false })
    assert.is_false(backend.resize('up'))
    assert.are.equal(0, #state.calls)
  end)

  it('returns false rather than throwing when tmux is unreachable', function()
    h.reset_backend({ fail = true })
    assert.is_false(backend.resize('up'))
  end)
end)
