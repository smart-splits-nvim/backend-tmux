local h = require('tests.helpers')

describe('detect()', function()
  before_each(function()
    h.reset_backend()
  end)

  after_each(function()
    h.restore()
  end)

  it('returns true inside a tmux session', function()
    local backend = require('smart-splits-backend-tmux')
    assert.is_true(backend.detect())
  end)

  it('returns false outside a tmux session', function()
    local backend = require('smart-splits-backend-tmux')
    h.leave_session()
    assert.is_false(backend.detect())
  end)

  it('returns false when $TMUX is empty', function()
    local backend = require('smart-splits-backend-tmux')
    vim.env.TMUX = ''
    assert.is_false(backend.detect())
  end)

  it('returns false when disabled', function()
    local backend = require('smart-splits-backend-tmux')
    backend.setup({ enable = false })
    assert.is_false(backend.detect())
  end)

  it('does not shell out', function()
    local backend = require('smart-splits-backend-tmux')
    local state = h.reset_backend()
    backend.detect()
    assert.are.equal(0, #state.calls)
  end)
end)
