---Unit tests for termdebug-enhanced.utils module
---Run with: nvim -l tests/test_utils.lua

local utils = require("termdebug-enhanced.utils")

-- Test framework
local tests = {}
local passed = 0
local failed = 0

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(string.format("%s\nExpected: %s\nActual: %s", 
      message or "Assertion failed", 
      vim.inspect(expected), 
      vim.inspect(actual)))
  end
end

local function assert_true(value, message)
  if not value then
    error((message or "Expected true, got: ") .. vim.inspect(value))
  end
end

local function run_test(name, test_fn)
  local ok, err = pcall(test_fn)
  if ok then
    passed = passed + 1
    print("✓ " .. name)
  else
    failed = failed + 1
    print("✗ " .. name .. "\n  " .. tostring(err))
  end
end

-- Test: parse_breakpoints
function tests.test_parse_breakpoints()
  local lines = {
    "Num     Type           Disp Enb Address            What",
    "1       breakpoint     keep y   0x00001234         in main at main.c:42",
    "2       breakpoint     keep n   main.c:15",
    "3       breakpoint     keep y   0x00005678         at src/test.c:100",
  }
  
  local breakpoints = utils.parse_breakpoints(lines)
  
  assert_eq(#breakpoints, 3, "Should parse 3 breakpoints")
  
  -- Check first breakpoint
  assert_eq(breakpoints[1].num, 1)
  assert_eq(breakpoints[1].file, "main.c")
  assert_eq(breakpoints[1].line, 42)
  assert_true(breakpoints[1].enabled)
  
  -- Check second breakpoint
  assert_eq(breakpoints[2].num, 2)
  assert_eq(breakpoints[2].file, "main.c")
  assert_eq(breakpoints[2].line, 15)
  assert_true(not breakpoints[2].enabled)
  
  -- Check third breakpoint
  assert_eq(breakpoints[3].num, 3)
  assert_eq(breakpoints[3].file, "src/test.c")
  assert_eq(breakpoints[3].line, 100)
  assert_true(breakpoints[3].enabled)
end

-- Test: find_breakpoint
function tests.test_find_breakpoint()
  local breakpoints = {
    { num = 1, file = "/home/user/main.c", line = 42, enabled = true },
    { num = 2, file = "/home/user/test.c", line = 15, enabled = false },
  }
  
  -- Mock vim.fn.fnamemodify to return the same path
  local orig_fnamemodify = vim.fn.fnamemodify
  vim.fn.fnamemodify = function(path, modifier)
    if modifier == ":p" then
      return path
    end
    return orig_fnamemodify(path, modifier)
  end
  
  local bp_num = utils.find_breakpoint(breakpoints, "/home/user/main.c", 42)
  assert_eq(bp_num, 1, "Should find breakpoint 1")
  
  bp_num = utils.find_breakpoint(breakpoints, "/home/user/test.c", 15)
  assert_eq(bp_num, 2, "Should find breakpoint 2")
  
  bp_num = utils.find_breakpoint(breakpoints, "/home/user/main.c", 50)
  assert_eq(bp_num, nil, "Should not find breakpoint at wrong line")
  
  -- Restore original function
  vim.fn.fnamemodify = orig_fnamemodify
end

-- Test: extract_value
function tests.test_extract_value()
  -- Test simple value
  local lines = {"$1 = 42"}
  local value = utils.extract_value(lines)
  assert_eq(value, "42", "Should extract simple number")
  
  -- Test hex value
  lines = {"$2 = 0x1234"}
  value = utils.extract_value(lines)
  assert_eq(value, "0x1234", "Should extract hex value")
  
  -- Test string value
  lines = {"$3 = \"hello world\""}
  value = utils.extract_value(lines)
  assert_eq(value, "\"hello world\"", "Should extract string")
  
  -- Test struct value
  lines = {"$4 = {x = 10, y = 20}"}
  value = utils.extract_value(lines)
  assert_eq(value, "{x = 10, y = 20}", "Should extract struct")
  
  -- Test multi-line value
  lines = {
    "$5 = {",
    "  x = 10,",
    "  y = 20",
    "}"
  }
  value = utils.extract_value(lines)
  assert_true(value and value:match("x = 10"), "Should extract multi-line struct")
  
  -- Test no value
  lines = {"(gdb) "}
  value = utils.extract_value(lines)
  assert_eq(value, nil, "Should return nil for no value")
end

-- Test: debounce
function tests.test_debounce()
  local call_count = 0
  local last_arg = nil
  
  local function test_fn(arg)
    call_count = call_count + 1
    last_arg = arg
  end
  
  local debounced = utils.debounce(test_fn, 50)
  
  -- Call multiple times quickly
  debounced("first")
  debounced("second")
  debounced("third")
  
  -- Should not have been called yet
  assert_eq(call_count, 0, "Function should not be called immediately")
  
  -- Wait for debounce delay
  vim.wait(100, function() return call_count > 0 end, 10)
  
  -- Should have been called once with last argument
  assert_eq(call_count, 1, "Function should be called once after delay")
  assert_eq(last_arg, "third", "Should use last argument")
end

-- Test: GDB buffer cache
function tests.test_gdb_buffer_cache()
  -- Create a mock buffer with GDB name
  local gdb_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(gdb_buf, "/tmp/test-gdb")
  
  -- First call should search and cache
  local found = utils.find_gdb_buffer()
  assert_eq(found, gdb_buf, "Should find GDB buffer")
  
  -- Second call should use cache (can't easily test this without mocking time)
  local found2 = utils.find_gdb_buffer()
  assert_eq(found2, gdb_buf, "Should return cached buffer")
  
  -- Invalidate cache
  utils.invalidate_gdb_cache()
  
  -- Delete the buffer
  vim.api.nvim_buf_delete(gdb_buf, { force = true })
  
  -- Should not find buffer after deletion
  found = utils.find_gdb_buffer()
  assert_eq(found, nil, "Should not find deleted buffer")
end

-- Run all tests
print("Running termdebug-enhanced.utils tests...\n")

for name, test_fn in pairs(tests) do
  run_test(name, test_fn)
end

print(string.format("\nResults: %d passed, %d failed", passed, failed))

if failed > 0 then
  os.exit(1)
end