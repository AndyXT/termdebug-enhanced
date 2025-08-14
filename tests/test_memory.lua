---Unit tests for termdebug-enhanced.memory module
---Run with: nvim -l tests/test_memory.lua

-- Load test helpers
local helpers = require("tests.test_helpers")

-- Mock the utils module before requiring memory
local mock_utils_calls = {}
package.loaded["termdebug-enhanced.utils"] = {
  async_gdb_response = function(cmd, callback, opts)
    table.insert(mock_utils_calls, { command = cmd, opts = opts })
    
    -- Mock responses based on command patterns
    vim.defer_fn(function()
      if cmd:match("^print &") then
        -- Address lookup
        local var = cmd:match("^print &(.+)")
        if var == "test_var" then
          callback({ "$1 = (int *) 0x1234" }, nil)
        elseif var == "invalid_var" then
          callback(nil, "No symbol \"invalid_var\" in current context.")
        else
          callback({ "$1 = (int *) 0x5678" }, nil)
        end
      elseif cmd:match("^x/") then
        -- Memory examination
        local addr = cmd:match("0x%x+") or cmd:match("%d+")
        if addr == "0xdeadbeef" then
          callback(nil, "Cannot access memory at address 0xdeadbeef")
        elseif addr == "0x1234" or addr == "0x5678" then
          callback(helpers.fixtures.memory_hex_dump, nil)
        else
          callback(helpers.fixtures.memory_hex_dump, nil)
        end
      elseif cmd:match("^set %*") then
        -- Memory setting
        if cmd:match("0xdeadbeef") then
          callback(nil, "Cannot access memory at address")
        else
          callback({}, nil)
        end
      elseif cmd:match("^set variable") then
        -- Variable setting
        if cmd:match("invalid_var") then
          callback(nil, "No symbol \"invalid_var\" in current context.")
        else
          callback({}, nil)
        end
      elseif cmd:match("^print ") then
        -- Variable printing
        local var = cmd:match("^print (.+)")
        if var == "test_var" then
          callback({ "$1 = 42" }, nil)
        else
          callback({ "$1 = 100" }, nil)
        end
      else
        callback(nil, "Unknown command")
      end
    end, 10)
  end,
  
  extract_value = function(lines)
    if lines and #lines > 0 then
      for _, line in ipairs(lines) do
        local value = line:match("%$%d+ = (.+)")
        if value then
          return value
        end
      end
    end
    return nil
  end,
  
  find_gdb_buffer = function() return 1 end,
}

-- Mock the main module config
package.loaded["termdebug-enhanced"] = {
  config = {
    memory_viewer = {
      width = 80,
      height = 20,
      format = "hex",
      bytes_per_line = 16
    }
  }
}

-- Mock vim globals for GDB state
vim.g.termdebug_running = true

local memory = require("termdebug-enhanced.memory")

-- Test suite
local tests = {}

-- Mock window/buffer creation for testing
local test_windows = {}
local test_buffers = {}
local original_create_buf = vim.api.nvim_create_buf
local original_open_win = vim.api.nvim_open_win
local original_win_close = vim.api.nvim_win_close
local original_buf_delete = vim.api.nvim_buf_delete

-- Override vim functions for testing
vim.api.nvim_create_buf = function(listed, scratch)
  local buf = original_create_buf(listed, scratch)
  table.insert(test_buffers, buf)
  return buf
end

-- Mock vim.cmd for split creation
local original_cmd = vim.cmd
vim.cmd = function(command)
  if command:match("botright %d+split") then
    -- Don't actually create split in tests
    return
  end
  return original_cmd(command)
end

-- Mock window functions
vim.api.nvim_get_current_win = function()
  return 999 -- Mock window ID
end

vim.api.nvim_win_set_buf = function(win, buf)
  -- Mock successful buffer setting
  return true
end

-- Mock vim.fn.expand for cursor word testing
local mock_expand_value = ""
vim.fn.expand = function(expr)
  if expr == "<cexpr>" or expr == "<cword>" then
    return mock_expand_value
  end
  return ""
end

-- Mock vim.fn.input for user input testing
local mock_input_value = ""
vim.fn.input = function(prompt)
  return mock_input_value
end

-- Mock vim.notify for testing notifications
local notifications = {}
local original_notify = vim.notify
vim.notify = function(msg, level)
  table.insert(notifications, { message = msg, level = level })
end

-- Test: view_memory_at_cursor with valid variable
function tests.test_view_memory_valid_variable()
  mock_expand_value = "test_var"
  mock_utils_calls = {}
  notifications = {}
  
  memory.view_memory_at_cursor()
  
  -- Wait for async operations with shorter timeout
  vim.wait(100)
  
  helpers.assert_true(#mock_utils_calls >= 1, "Should make GDB calls")
  helpers.assert_true(mock_utils_calls[1].command:match("print &test_var"), "Should get variable address")
end

-- Test: view_memory_at_cursor with direct address
function tests.test_view_memory_direct_address()
  mock_expand_value = "0x1234"
  mock_utils_calls = {}
  
  memory.view_memory_at_cursor()
  
  -- Wait for async operations
  helpers.wait_for(function() return #mock_utils_calls >= 1 end, 1000)
  
  helpers.assert_true(#mock_utils_calls >= 1, "Should make GDB calls")
  helpers.assert_true(mock_utils_calls[1].command:match("x/.*0x1234"), "Should examine memory at address")
end

-- Test: view_memory_at_cursor with no word under cursor
function tests.test_view_memory_no_word()
  mock_expand_value = ""
  mock_input_value = ""
  notifications = {}
  
  memory.view_memory_at_cursor()
  
  -- Should return early without making GDB calls
  helpers.assert_eq(#mock_utils_calls, 0, "Should not make GDB calls when no input")
end

-- Test: view_memory_at_cursor with invalid variable
function tests.test_view_memory_invalid_variable()
  mock_expand_value = "invalid_var"
  mock_utils_calls = {}
  
  memory.view_memory_at_cursor()
  
  -- Wait for async operations
  helpers.wait_for(function() return #mock_utils_calls >= 1 end, 1000)
  
  helpers.assert_true(#mock_utils_calls >= 1, "Should attempt to get variable address")
end

-- Test: show_memory with valid address
function tests.test_show_memory_valid_address()
  mock_utils_calls = {}
  
  memory.show_memory("0x1234", 256)
  
  -- Wait for async operations
  helpers.wait_for(function() return #mock_utils_calls >= 1 end, 1000)
  
  helpers.assert_true(#mock_utils_calls >= 1, "Should make memory examination call")
  helpers.assert_true(mock_utils_calls[1].command:match("x/256xb 0x1234"), "Should use correct memory command")
end

-- Test: show_memory with invalid address
function tests.test_show_memory_invalid_address()
  mock_utils_calls = {}
  
  memory.show_memory("invalid_address", 256)
  
  -- Should not make GDB calls due to validation failure
  helpers.assert_eq(#mock_utils_calls, 0, "Should not make GDB calls for invalid address")
end

-- Test: show_memory with empty address
function tests.test_show_memory_empty_address()
  mock_utils_calls = {}
  
  memory.show_memory("", 256)
  
  -- Should not make GDB calls due to validation failure
  helpers.assert_eq(#mock_utils_calls, 0, "Should not make GDB calls for empty address")
end

-- Test: show_memory with nil address
function tests.test_show_memory_nil_address()
  mock_utils_calls = {}
  
  memory.show_memory(nil, 256)
  
  -- Should not make GDB calls due to validation failure
  helpers.assert_eq(#mock_utils_calls, 0, "Should not make GDB calls for nil address")
end

-- Test: show_memory with GDB not running
function tests.test_show_memory_gdb_not_running()
  vim.g.termdebug_running = false
  mock_utils_calls = {}
  
  memory.show_memory("0x1234", 256)
  
  -- Should not make GDB calls when GDB not running
  helpers.assert_eq(#mock_utils_calls, 0, "Should not make GDB calls when GDB not running")
  
  -- Restore GDB state
  vim.g.termdebug_running = true
end

-- Test: navigate_memory with positive offset
function tests.test_navigate_memory_positive_offset()
  mock_utils_calls = {}
  
  -- First set up a memory view
  memory.show_memory("0x1000", 256)
  helpers.wait_for(function() return #mock_utils_calls >= 1 end, 1000)
  
  local initial_calls = #mock_utils_calls
  
  -- Navigate forward
  memory.navigate_memory(16)
  helpers.wait_for(function() return #mock_utils_calls > initial_calls end, 1000)
  
  helpers.assert_true(#mock_utils_calls > initial_calls, "Should make additional GDB call for navigation")
end

-- Test: navigate_memory with negative offset
function tests.test_navigate_memory_negative_offset()
  mock_utils_calls = {}
  notifications = {}
  
  -- Set up memory view at higher address
  memory.show_memory("0x2000", 256)
  helpers.wait_for(function() return #mock_utils_calls >= 1 end, 1000)
  
  local initial_calls = #mock_utils_calls
  
  -- Navigate backward
  memory.navigate_memory(-16)
  helpers.wait_for(function() return #mock_utils_calls > initial_calls end, 1000)
  
  helpers.assert_true(#mock_utils_calls > initial_calls, "Should make additional GDB call for backward navigation")
end

-- Test: navigate_memory with underflow protection
function tests.test_navigate_memory_underflow()
  mock_utils_calls = {}
  notifications = {}
  
  -- Set up memory view at low address
  memory.show_memory("0x10", 256)
  helpers.wait_for(function() return #mock_utils_calls >= 1 end, 1000)
  
  local initial_calls = #mock_utils_calls
  
  -- Try to navigate to negative address
  memory.navigate_memory(-100)
  
  -- Should not make additional GDB calls due to underflow protection
  helpers.assert_eq(#mock_utils_calls, initial_calls, "Should not navigate to negative address")
  helpers.assert_true(#notifications > 0, "Should notify about underflow")
end

-- Test: navigate_memory with no active view
function tests.test_navigate_memory_no_active_view()
  -- Clear any existing memory state by creating new module instance
  package.loaded["termdebug-enhanced.memory"] = nil
  memory = require("termdebug-enhanced.memory")
  
  notifications = {}
  
  memory.navigate_memory(16)
  
  helpers.assert_true(#notifications > 0, "Should notify when no memory view active")
end

-- Test: edit_memory_at_cursor with variable
function tests.test_edit_memory_variable()
  mock_expand_value = "test_var"
  mock_input_value = "100"
  mock_utils_calls = {}
  notifications = {}
  
  memory.edit_memory_at_cursor()
  
  -- Wait for async operations
  helpers.wait_for(function() return #mock_utils_calls >= 1 end, 1000)
  
  helpers.assert_true(#mock_utils_calls >= 1, "Should make GDB call to set variable")
  helpers.assert_true(mock_utils_calls[1].command:match("set variable test_var = 100"), "Should use correct set command")
end

-- Test: edit_memory_at_cursor with address and hex bytes
function tests.test_edit_memory_address_hex()
  mock_expand_value = "0x1234"
  mock_input_value = "AB CD EF"
  mock_utils_calls = {}
  
  memory.edit_memory_at_cursor()
  
  -- Wait for async operations
  helpers.wait_for(function() return #mock_utils_calls >= 3 end, 1000)
  
  helpers.assert_true(#mock_utils_calls >= 3, "Should make GDB calls for each byte")
end

-- Test: edit_memory_at_cursor with invalid hex
function tests.test_edit_memory_invalid_hex()
  mock_expand_value = "0x1234"
  mock_input_value = "XY ZZ"
  mock_utils_calls = {}
  notifications = {}
  
  memory.edit_memory_at_cursor()
  
  -- Should not make GDB calls due to validation failure
  helpers.assert_eq(#mock_utils_calls, 0, "Should not make GDB calls for invalid hex")
  helpers.assert_true(#notifications > 0, "Should notify about invalid hex")
end

-- Test: edit_memory_at_cursor with no word under cursor
function tests.test_edit_memory_no_word()
  mock_expand_value = ""
  mock_input_value = ""
  mock_utils_calls = {}
  
  memory.edit_memory_at_cursor()
  
  -- Should return early without making GDB calls
  helpers.assert_eq(#mock_utils_calls, 0, "Should not make GDB calls when no input")
end

-- Test: edit_memory_at_cursor with GDB not running
function tests.test_edit_memory_gdb_not_running()
  vim.g.termdebug_running = false
  mock_expand_value = "test_var"
  mock_input_value = "100"
  mock_utils_calls = {}
  notifications = {}
  
  memory.edit_memory_at_cursor()
  
  helpers.assert_eq(#mock_utils_calls, 0, "Should not make GDB calls when GDB not running")
  helpers.assert_true(#notifications > 0, "Should notify when GDB not running")
  
  -- Restore GDB state
  vim.g.termdebug_running = true
end

-- Test: refresh_memory with active view
function tests.test_refresh_memory_active()
  mock_utils_calls = {}
  
  -- Set up memory view first
  memory.show_memory("0x1234", 256)
  helpers.wait_for(function() return #mock_utils_calls >= 1 end, 1000)
  
  local initial_calls = #mock_utils_calls
  
  -- Refresh
  memory.refresh_memory()
  helpers.wait_for(function() return #mock_utils_calls > initial_calls end, 1000)
  
  helpers.assert_true(#mock_utils_calls > initial_calls, "Should make additional GDB call for refresh")
end

-- Test: refresh_memory with no active view
function tests.test_refresh_memory_no_active()
  -- Clear memory state
  package.loaded["termdebug-enhanced.memory"] = nil
  memory = require("termdebug-enhanced.memory")
  
  mock_utils_calls = {}
  
  memory.refresh_memory()
  
  -- Should not make GDB calls when no active view
  helpers.assert_eq(#mock_utils_calls, 0, "Should not make GDB calls when no active view")
end

-- Test: cleanup_all_windows
function tests.test_cleanup_all_windows()
  -- This test mainly ensures the function exists and doesn't error
  local ok, err = pcall(memory.cleanup_all_windows)
  helpers.assert_true(ok, "cleanup_all_windows should not error: " .. tostring(err))
end

-- Cleanup function
local function cleanup_tests()
  -- Restore original functions
  vim.api.nvim_create_buf = original_create_buf
  vim.cmd = original_cmd
  vim.notify = original_notify
  
  -- Clean up test resources
  helpers.cleanup_test_resources(test_buffers)
  helpers.cleanup_test_resources(test_windows)
  
  -- Clear mock state
  mock_utils_calls = {}
  notifications = {}
  test_buffers = {}
  test_windows = {}
end

-- Run tests with cleanup
local function run_tests()
  helpers.run_test_suite(tests, "termdebug-enhanced.memory")
  cleanup_tests()
end

-- Execute tests
print("Starting memory tests...")
run_tests()
print("Memory tests completed.")