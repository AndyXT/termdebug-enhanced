---Simplified unit tests for termdebug-enhanced.memory module
---Run with: nvim --headless -u NONE -c "set rtp+=." -l tests/test_memory_simple.lua

-- Load test helpers
local helpers = require("tests.test_helpers")

-- Mock the utils module with synchronous responses
local mock_utils_calls = {}
package.loaded["termdebug-enhanced.utils"] = {
  async_gdb_response = function(cmd, callback, opts)
    table.insert(mock_utils_calls, { command = cmd, opts = opts })
    
    -- Immediate synchronous response for testing
    if cmd:match("^print &") then
      local var = cmd:match("^print &(.+)")
      if var == "test_var" then
        callback({ "$1 = (int *) 0x1234" }, nil)
      else
        callback(nil, "No symbol found")
      end
    elseif cmd:match("^x/") then
      if cmd:match("invalid_address") then
        callback(nil, "Cannot access memory at address")
      else
        callback({ "0x1000: 0x12 0x34 0x56 0x78" }, nil)
      end
    else
      callback({}, nil)
    end
  end,
  
  extract_value = function(lines)
    if lines and #lines > 0 then
      return lines[1]:match("%$%d+ = (.+)") or "test_value"
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

-- Mock vim globals
vim.g.termdebug_running = true
vim.fn.exists = function(cmd)
  if cmd == ":Termdebug" then return 1 end
  return 0
end

-- Mock vim functions
local mock_expand_value = ""
vim.fn.expand = function(expr)
  if expr == "<cexpr>" or expr == "<cword>" then
    return mock_expand_value
  end
  return ""
end

local mock_input_value = ""
vim.fn.input = function(prompt)
  return mock_input_value
end

-- Mock window/buffer creation
local test_buffers = {}
local test_windows = {}

vim.api.nvim_create_buf = function(listed, scratch)
  local buf = #test_buffers + 100
  table.insert(test_buffers, buf)
  return buf
end

vim.cmd = function(command) end
vim.api.nvim_get_current_win = function() return 999 end
vim.api.nvim_win_set_buf = function() end
vim.api.nvim_buf_set_lines = function() end
vim.api.nvim_buf_set_name = function() end
vim.api.nvim_buf_set_keymap = function() end

-- Mock notifications
local notifications = {}
vim.notify = function(msg, level)
  table.insert(notifications, { message = msg, level = level })
end

local memory = require("termdebug-enhanced.memory")

-- Test suite
local tests = {}

-- Test: view_memory_at_cursor with valid variable
function tests.test_view_memory_valid_variable()
  mock_expand_value = "test_var"
  mock_utils_calls = {}
  
  memory.view_memory_at_cursor()
  
  helpers.assert_true(#mock_utils_calls >= 1, "Should make GDB calls")
  helpers.assert_true(mock_utils_calls[1].command:match("print &test_var"), "Should get variable address")
end

-- Test: view_memory_at_cursor with direct address
function tests.test_view_memory_direct_address()
  mock_expand_value = "0x1234"
  mock_utils_calls = {}
  
  memory.view_memory_at_cursor()
  
  helpers.assert_true(#mock_utils_calls >= 1, "Should make GDB calls")
  helpers.assert_true(mock_utils_calls[1].command:match("x/.*0x1234"), "Should examine memory at address")
end

-- Test: view_memory_at_cursor with no word under cursor
function tests.test_view_memory_no_word()
  mock_expand_value = ""
  mock_input_value = ""
  mock_utils_calls = {}
  
  memory.view_memory_at_cursor()
  
  helpers.assert_eq(#mock_utils_calls, 0, "Should not make GDB calls when no input")
end

-- Test: show_memory with valid address
function tests.test_show_memory_valid_address()
  mock_utils_calls = {}
  
  memory.show_memory("0x1234", 256)
  
  helpers.assert_true(#mock_utils_calls >= 1, "Should make memory examination call")
  helpers.assert_true(mock_utils_calls[1].command:match("x/256xb 0x1234"), "Should use correct memory command")
end

-- Test: show_memory with invalid address
function tests.test_show_memory_invalid_address()
  mock_utils_calls = {}
  
  memory.show_memory("invalid_address", 256)
  
  helpers.assert_eq(#mock_utils_calls, 1, "Should make GDB call for address (let GDB fail)")
end

-- Test: show_memory with GDB not running
function tests.test_show_memory_gdb_not_running()
  vim.g.termdebug_running = false
  mock_utils_calls = {}
  
  memory.show_memory("0x1234", 256)
  
  helpers.assert_eq(#mock_utils_calls, 0, "Should not make GDB calls when GDB not running")
  
  -- Restore GDB state
  vim.g.termdebug_running = true
end

-- Test: edit_memory_at_cursor with variable
function tests.test_edit_memory_variable()
  mock_expand_value = "test_var"
  mock_input_value = "100"
  mock_utils_calls = {}
  
  memory.edit_memory_at_cursor()
  
  helpers.assert_true(#mock_utils_calls >= 1, "Should make GDB call to set variable")
  helpers.assert_true(mock_utils_calls[1].command:match("set variable test_var = 100"), "Should use correct set command")
end

-- Test: cleanup function exists
function tests.test_cleanup_function()
  local ok, err = pcall(memory.cleanup_all_windows)
  helpers.assert_true(ok, "cleanup_all_windows should not error: " .. tostring(err))
end

-- Run tests
helpers.run_test_suite(tests, "termdebug-enhanced.memory (simplified)")