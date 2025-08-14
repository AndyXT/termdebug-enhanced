---Test infrastructure and utilities for termdebug-enhanced
---Provides mocking framework, async testing utilities, and common test fixtures

local M = {}

-- Test framework state
M.tests = {}
M.passed = 0
M.failed = 0

-- Mock storage for restoring original functions
M.mocks = {}

---Assert that two values are equal
---@param actual any Actual value
---@param expected any Expected value
---@param message string|nil Optional error message
function M.assert_eq(actual, expected, message)
  if actual ~= expected then
    error(string.format("%s\nExpected: %s\nActual: %s", 
      message or "Assertion failed", 
      vim.inspect(expected), 
      vim.inspect(actual)))
  end
end

---Assert that a value is true
---@param value any Value to check
---@param message string|nil Optional error message
function M.assert_true(value, message)
  if not value then
    if message then
      error(message)
    else
      error("Expected true, got: " .. vim.inspect(value))
    end
  end
end

---Assert that a value is false
---@param value any Value to check
---@param message string|nil Optional error message
function M.assert_false(value, message)
  if value then
    if message then
      error(message)
    else
      error("Expected false, got: " .. vim.inspect(value))
    end
  end
end

---Assert that a value is nil
---@param value any Value to check
---@param message string|nil Optional error message
function M.assert_nil(value, message)
  if value ~= nil then
    error((message or "Expected nil, got: ") .. vim.inspect(value))
  end
end

---Assert that a value is not nil
---@param value any Value to check
---@param message string|nil Optional error message
function M.assert_not_nil(value, message)
  if value == nil then
    if message then
      error(message)
    else
      error("Expected non-nil value")
    end
  end
end

---Assert that a string contains a substring
---@param str string String to search in
---@param substr string Substring to find
---@param message string|nil Optional error message
function M.assert_contains(str, substr, message)
  if not str:find(substr, 1, true) then
    error(string.format("%s\nString: %s\nExpected to contain: %s",
      message or "String does not contain expected substring",
      str, substr))
  end
end

---Assert that a function throws an error
---@param func function Function to test
---@param expected_error string|nil Expected error pattern
---@param message string|nil Optional error message
function M.assert_error(func, expected_error, message)
  local ok, err = pcall(func)
  if ok then
    error(message or "Expected function to throw an error")
  end
  if expected_error and not tostring(err):match(expected_error) then
    error(string.format("%s\nExpected error pattern: %s\nActual error: %s",
      message or "Error pattern mismatch",
      expected_error, tostring(err)))
  end
end

---Run a single test with error handling
---@param name string Test name
---@param test_fn function Test function
function M.run_test(name, test_fn)
  local ok, err = pcall(test_fn)
  if ok then
    M.passed = M.passed + 1
    print("✓ " .. name)
  else
    M.failed = M.failed + 1
    print("✗ " .. name .. "\n  " .. tostring(err))
  end
end

---Run all tests in a test suite
---@param test_suite table Table of test functions
---@param suite_name string Name of the test suite
function M.run_test_suite(test_suite, suite_name)
  print("Running " .. suite_name .. " tests...\n")
  
  for name, test_fn in pairs(test_suite) do
    if type(test_fn) == "function" then
      M.run_test(name, test_fn)
    end
  end
  
  print(string.format("\nResults: %d passed, %d failed", M.passed, M.failed))
  
  if M.failed > 0 then
    os.exit(1)
  end
end

-- Mock framework functions

---Create a mock function that records calls
---@param return_value any|nil Value to return from mock
---@return function, table Mock function and call history
function M.create_mock(return_value)
  local calls = {}
  local mock_fn = function(...)
    table.insert(calls, {...})
    return return_value
  end
  return mock_fn, calls
end

---Create a mock function with custom behavior
---@param behavior function Function that defines mock behavior
---@return function, table Mock function and call history
function M.create_mock_with_behavior(behavior)
  local calls = {}
  local mock_fn = function(...)
    local args = {...}
    table.insert(calls, args)
    return behavior(unpack(args))
  end
  return mock_fn, calls
end

---Mock a vim API function
---@param api_path string API path (e.g., "vim.api.nvim_create_buf")
---@param mock_fn function Mock function
function M.mock_vim_api(api_path, mock_fn)
  local parts = vim.split(api_path, ".", { plain = true })
  local obj = _G
  
  -- Navigate to parent object
  for i = 1, #parts - 1 do
    obj = obj[parts[i]]
  end
  
  local func_name = parts[#parts]
  
  -- Store original for restoration
  if not M.mocks[api_path] then
    M.mocks[api_path] = obj[func_name]
  end
  
  -- Set mock
  obj[func_name] = mock_fn
end

---Restore all mocked functions
function M.restore_mocks()
  for api_path, original_fn in pairs(M.mocks) do
    local parts = vim.split(api_path, ".", { plain = true })
    local obj = _G
    
    -- Navigate to parent object
    for i = 1, #parts - 1 do
      obj = obj[parts[i]]
    end
    
    local func_name = parts[#parts]
    obj[func_name] = original_fn
  end
  
  M.mocks = {}
end

-- Async testing utilities

---Wait for a condition with timeout
---@param condition function Function that returns true when condition is met
---@param timeout number Timeout in milliseconds
---@param interval number|nil Check interval in milliseconds (default: 10)
---@return boolean True if condition was met, false if timeout
function M.wait_for(condition, timeout, interval)
  interval = interval or 10
  local start_time = vim.loop.now()
  
  while vim.loop.now() - start_time < timeout do
    if condition() then
      return true
    end
    vim.wait(interval)
  end
  
  return false
end

---Create a controlled timer for testing async operations
---@param callback function Callback to execute
---@param delay number Delay in milliseconds
---@return table Timer handle with control methods
function M.create_test_timer(callback, delay)
  local timer_state = {
    executed = false,
    cancelled = false,
    callback = callback,
    delay = delay
  }
  
  local timer = vim.loop.new_timer()
  
  timer:start(delay, 0, function()
    if not timer_state.cancelled then
      timer_state.executed = true
      callback()
    end
    timer:close()
  end)
  
  return {
    cancel = function()
      timer_state.cancelled = true
      timer:close()
    end,
    is_executed = function()
      return timer_state.executed
    end,
    is_cancelled = function()
      return timer_state.cancelled
    end
  }
end

-- Test fixtures for common scenarios

---Create mock GDB response for successful command
---@param command string GDB command
---@param response_lines string[] Response lines
---@return table Mock response data
function M.create_gdb_success_response(command, response_lines)
  return {
    command = command,
    response = response_lines,
    error = nil,
    success = true
  }
end

---Create mock GDB response for failed command
---@param command string GDB command
---@param error_message string Error message
---@return table Mock response data
function M.create_gdb_error_response(command, error_message)
  return {
    command = command,
    response = nil,
    error = error_message,
    success = false
  }
end

---Common GDB response fixtures
M.fixtures = {
  -- Breakpoint listing responses
  breakpoints_empty = {
    "No breakpoints or watchpoints."
  },
  
  breakpoints_multiple = {
    "Num     Type           Disp Enb Address            What",
    "1       breakpoint     keep y   0x00001234         in main at main.c:42",
    "2       breakpoint     keep n   main.c:15",
    "3       breakpoint     keep y   0x00005678         at src/test.c:100",
  },
  
  -- Memory examination responses
  memory_hex_dump = {
    "0x1000:	0x12	0x34	0x56	0x78	0x9a	0xbc	0xde	0xf0",
    "0x1008:	0x11	0x22	0x33	0x44	0x55	0x66	0x77	0x88",
    "0x1010:	0xaa	0xbb	0xcc	0xdd	0xee	0xff	0x00	0x11",
  },
  
  memory_access_error = {
    "Cannot access memory at address 0xdeadbeef"
  },
  
  -- Variable evaluation responses
  variable_int = {
    "$1 = 42"
  },
  
  variable_string = {
    "$2 = \"hello world\""
  },
  
  variable_struct = {
    "$3 = {",
    "  x = 10,",
    "  y = 20,",
    "  name = \"test\"",
    "}"
  },
  
  variable_address = {
    "$4 = (int *) 0x1234"
  },
  
  -- Error responses
  variable_not_found = {
    "No symbol \"unknown_var\" in current context."
  },
  
  gdb_not_running = {
    "The program is not being run."
  }
}

-- Floating window and buffer testing utilities

---Create mock buffer for testing
---@param name string|nil Buffer name
---@param lines string[]|nil Initial buffer content
---@return number Mock buffer handle
function M.create_test_buffer(name, lines)
  local buf = vim.api.nvim_create_buf(false, true)
  
  if name then
    vim.api.nvim_buf_set_name(buf, name)
  end
  
  if lines then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end
  
  return buf
end

---Create mock window for testing
---@param buf number Buffer handle
---@param config table|nil Window configuration
---@return number Mock window handle
function M.create_test_window(buf, config)
  config = config or { relative = "editor", width = 50, height = 10, row = 5, col = 5 }
  return vim.api.nvim_open_win(buf, false, config)
end

---Clean up test buffers and windows
---@param handles table List of buffer/window handles to clean up
function M.cleanup_test_resources(handles)
  for _, handle in ipairs(handles or {}) do
    if type(handle) == "number" then
      -- Try as window first, then buffer
      if vim.api.nvim_win_is_valid(handle) then
        pcall(vim.api.nvim_win_close, handle, true)
      elseif vim.api.nvim_buf_is_valid(handle) then
        pcall(vim.api.nvim_buf_delete, handle, { force = true })
      end
    end
  end
end

---Mock the utils.async_gdb_response function for testing
---@param responses table Map of commands to mock responses
---@return function, table Mock function and call history
function M.mock_async_gdb_response(responses)
  local calls = {}
  
  local mock_fn = function(command, callback, opts)
    table.insert(calls, { command = command, opts = opts })
    
    -- Simulate async behavior
    vim.defer_fn(function()
      local response_data = responses[command]
      if response_data then
        if response_data.success then
          callback(response_data.response, nil)
        else
          callback(nil, response_data.error)
        end
      else
        -- Default to error for unknown commands
        callback(nil, "Unknown command: " .. command)
      end
    end, 10) -- Small delay to simulate async
  end
  
  return mock_fn, calls
end

return M