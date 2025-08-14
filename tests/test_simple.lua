---Simple test to verify test infrastructure
---Run with: nvim --headless -u NONE -c "set rtp+=." -l tests/test_simple.lua

-- Load test helpers
local helpers = require("tests.test_helpers")

-- Test suite
local tests = {}

-- Simple test
function tests.test_basic_assertion()
  helpers.assert_eq(1, 1, "One should equal one")
  helpers.assert_true(true, "True should be true")
  helpers.assert_false(false, "False should be false")
end

function tests.test_string_contains()
  helpers.assert_contains("hello world", "world", "Should contain substring")
end

function tests.test_mock_creation()
  local mock_fn, calls = helpers.create_mock("test_return")
  local result = mock_fn("arg1", "arg2")
  
  helpers.assert_eq(result, "test_return", "Should return mock value")
  helpers.assert_eq(#calls, 1, "Should record one call")
  helpers.assert_eq(calls[1][1], "arg1", "Should record first argument")
  helpers.assert_eq(calls[1][2], "arg2", "Should record second argument")
end

-- Run tests
helpers.run_test_suite(tests, "simple test infrastructure")