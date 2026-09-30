local h = require('tests.helpers')

describe('backend protocol conformance', function()
  before_each(function()
    h.reset_backend()
  end)

  after_each(function()
    h.restore()
  end)

  it('implements the v3 backend protocol', function()
    local backend = require('smart-splits-backend-tmux')
    local protocol_tests = require('smart-splits.protocol_tests')
    for _, test in ipairs(protocol_tests.tests(backend)) do
      local result = test.fn()
      assert.is_true(result, test.name .. ': ' .. tostring(result))
    end
  end)

  it('implements the v3 backend protocol outside a tmux session', function()
    h.leave_session()
    local backend = require('smart-splits-backend-tmux')
    local protocol_tests = require('smart-splits.protocol_tests')
    for _, test in ipairs(protocol_tests.tests(backend)) do
      local result = test.fn()
      assert.is_true(result, test.name .. ': ' .. tostring(result))
    end
  end)

  it('declares the required protocol fields', function()
    local backend = require('smart-splits-backend-tmux')
    assert.are.equal('tmux', backend.name)
    assert.are.equal('3.0.0', backend.protocol_version)
    assert.are.equal('function', type(backend.detect))
    assert.are.equal('function', type(backend.move))
    assert.are.equal('function', type(backend.resize))
    assert.are.equal('function', type(backend.activate))
    assert.are.equal('function', type(backend.health))
  end)
end)
