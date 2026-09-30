local h = require('tests.helpers')

local backend = require('smart-splits-backend-tmux')

---Collect what `health()` reports instead of rendering it, so the assertions
---can be about content rather than "did not throw".
---@param fn fun()
---@return { level: string, message: string }[]
local function collect(fn)
  local original = vim.health
  local reported = {}
  local function record(level)
    return function(message)
      table.insert(reported, { level = level, message = tostring(message) })
    end
  end
  vim.health = {
    start = record('start'),
    ok = record('ok'),
    info = record('info'),
    warn = record('warn'),
    error = record('error'),
  }
  local ok, err = pcall(fn)
  vim.health = original
  assert(ok, err)
  return reported
end

---@param entries { level: string, message: string }[]
---@param level string
---@param pattern string
---@return boolean
local function reported(entries, level, pattern)
  for _, entry in ipairs(entries) do
    if entry.level == level and entry.message:find(pattern, 1, true) then
      return true
    end
  end
  return false
end

describe('health()', function()
  after_each(function()
    h.restore()
  end)

  it('reports the socket, the pane and the bindings when everything is set up', function()
    local state = h.reset_backend({ keys = h.paired_key_bindings(), options = { ['@pane-is-vim'] = '1' } })
    local out = collect(backend.health)
    assert.is_true(reported(out, 'ok', h.SOCKET))
    assert.is_true(reported(out, 'ok', '$TMUX_PANE: ' .. h.PANE))
    assert.is_true(reported(out, 'ok', '`@pane-is-vim` is set on this pane'))
    assert.is_true(reported(out, 'ok', 'tmux keys that defer to Neovim via `@pane-is-vim`: C-h, C-j'))
    assert.are.equal('1', state.options['@pane-is-vim'])
  end)

  it('does not emit its own section header, core does that', function()
    h.reset_backend({ keys = h.paired_key_bindings() })
    local out = collect(backend.health)
    assert.is_false(reported(out, 'start', ''))
  end)

  it('warns when the pane marker is missing', function()
    h.reset_backend({ keys = h.paired_key_bindings() })
    local out = collect(backend.health)
    assert.is_true(reported(out, 'warn', '`@pane-is-vim` is not set on this pane'))
  end)

  it('warns when nothing in tmux reads `@pane-is-vim`', function()
    h.reset_backend({ keys = { 'bind-key    -T root         C-a                send-prefix' } })
    local out = collect(backend.health)
    assert.is_true(reported(out, 'warn', 'no tmux key binding reads `@pane-is-vim`'))
  end)

  it('makes no assumption about which keys the user bound', function()
    h.reset_backend({
      keys = {
        'bind-key    -T root         M-Left             if-shell -F "#{@pane-is-vim}" { send-keys M-Left } { select-pane -L }',
        'bind-key    -T root         C-h                select-pane -L',
      },
    })
    local out = collect(backend.health)
    assert.is_true(reported(out, 'ok', 'tmux keys that defer to Neovim via `@pane-is-vim`: M-Left'))
    assert.is_false(reported(out, 'warn', 'no tmux key binding reads'))
  end)

  it('explains itself outside a tmux session rather than failing', function()
    h.reset_backend()
    h.leave_session()
    local out = collect(backend.health)
    assert.is_true(reported(out, 'info', '$TMUX is not set'))
  end)

  it('survives a tmux that answers nothing', function()
    h.reset_backend({ fail = true })
    local out = collect(backend.health)
    assert.is_true(reported(out, 'warn', 'could not read the root key table'))
  end)

  it('reports the configuration', function()
    h.reset_backend()
    backend.setup({ resize_amount = 7 })
    local out = collect(backend.health)
    assert.is_true(reported(out, 'info', 'resize_amount: 7'))
  end)

  it('exposes a standalone `:checkhealth smart-splits-backend-tmux`', function()
    h.reset_backend()
    local out = collect(require('smart-splits-backend-tmux.health').check)
    assert.is_true(reported(out, 'start', 'smart-splits-backend-tmux'))
  end)
end)
