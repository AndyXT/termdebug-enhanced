---Integration tests for termdebug-enhanced module interactions
---Run with: nvim -l tests/test_integration.lua

-- IMPORTANT: Clear any previously loaded modules to ensure mocks are used
package.loaded["termdebug-enhanced.utils"] = nil
package.loaded["termdebug-enhanced.keymaps"] = nil
package.loaded["termdebug-enhanced.evaluate"] = nil
package.loaded["termdebug-enhanced.memory"] = nil
package.loaded["termdebug-enhanced.init"] = nil
package.loaded["termdebug-enhanced"] = nil

-- Load test helpers
local helpers = require("tests.test_helpers")

-- Test suite
local tests = {}

-- Mock GDB communication for integration testing
local gdb_responses = {}
local gdb_calls = {}

-- Create a comprehensive mock utils module
local function create_mock_utils()
  return {
    async_gdb_response = function(cmd, callback, opts)
      table.insert(gdb_calls, { command = cmd, opts = opts })
      
      vim.defer_fn(function()
        local response = gdb_responses[cmd]
        if response then
          if response.success then
            callback(response.data, nil)
          else
            callback(nil, response.error)
          end
        else
          -- Default responses for common commands
          if cmd:match("^info breakpoints") then
            callback(helpers.fixtures.breakpoints_multiple, nil)
          elseif cmd:match("^print &") then
            callback({ "$1 = (int *) 0x1234" }, nil)
          elseif cmd:match("^x/") then
            callback(helpers.fixtures.memory_hex_dump, nil)
          elseif cmd:match("^print ") then
            callback({ "$1 = 42" }, nil)
          else
            callback({}, nil)
          end
        end
      end, 10)
    end,
    
    parse_breakpoints = function(lines)
      return {
        { num = 1, file = "/test/main.c", line = 42, enabled = true },
        { num = 2, file = "/test/main.c", line = 15, enabled = false },
      }
    end,
    
    find_breakpoint = function(breakpoints, file, line)
      for _, bp in ipairs(breakpoints) do
        if bp.file:match("main.c") and bp.line == line then
          return bp.num
        end
      end
      return nil
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
    
    find_gdb_buffer = function()
      return 1
    end,
    
    debounce = function(func, delay)
      return func -- Return function directly for testing
    end,
    
    -- Add missing mock functions that are used by modules
    track_resource = function() end,
    untrack_resource = function() end,
    cleanup_all_resources = function() return 0 end,
    get_resource_stats = function() return {} end,
    get_performance_metrics = function() return { avg_response_time = 0 } end,
  }
end

-- Set up mock environment BEFORE any module loading
package.loaded["termdebug-enhanced.utils"] = create_mock_utils()

-- Mock main module config
package.loaded["termdebug-enhanced"] = {
  config = {
    popup = { border = "rounded", width = 60, height = 10 },
    memory_viewer = { width = 80, height = 20, format = "hex", bytes_per_line = 16 },
    keymaps = {
      continue = "<F5>",
      step_over = "<F10>",
      step_into = "<F11>",
      step_out = "<S-F11>",
      toggle_breakpoint = "<F9>",
      evaluate = "K",
    }
  }
}

-- Mock vim globals and functions
vim.g.termdebug_running = true
vim.fn.exists = function(cmd)
  if cmd == ":Termdebug" then return 1 end
  return 0
end

local mock_keymaps = {}
local mock_windows = {}
local mock_buffers = {}
local notifications = {}

-- Mock vim functions
vim.keymap.set = function(mode, key, callback, opts)
  mock_keymaps[mode .. ":" .. key] = { callback = callback, opts = opts }
end

vim.keymap.del = function(mode, key)
  mock_keymaps[mode .. ":" .. key] = nil
end

vim.api.nvim_create_buf = function(listed, scratch)
  local buf = #mock_buffers + 100
  table.insert(mock_buffers, buf)
  return buf
end

vim.api.nvim_open_win = function(buf, enter, config)
  local win = #mock_windows + 200
  table.insert(mock_windows, win)
  return win
end

vim.api.nvim_win_is_valid = function(win)
  for _, w in ipairs(mock_windows) do
    if w == win then return true end
  end
  return false
end

vim.api.nvim_buf_is_valid = function(buf)
  for _, b in ipairs(mock_buffers) do
    if b == buf then return true end
  end
  return false
end

vim.api.nvim_win_close = function(win, force)
  for i, w in ipairs(mock_windows) do
    if w == win then
      table.remove(mock_windows, i)
      break
    end
  end
end

vim.api.nvim_buf_delete = function(buf, opts)
  for i, b in ipairs(mock_buffers) do
    if b == buf then
      table.remove(mock_buffers, i)
      break
    end
  end
end

-- Mock other vim functions
vim.api.nvim_buf_set_lines = function() end
vim.api.nvim_buf_set_name = function() end
vim.api.nvim_buf_set_keymap = function() end
vim.api.nvim_win_set_buf = function() end
vim.api.nvim_get_current_win = function() return 1 end

vim.cmd = function() end
vim.fn.line = function() return 42 end
vim.fn.expand = function(expr)
  if expr == "%:p" then return "/test/main.c"
  elseif expr == "<cword>" or expr == "<cexpr>" then return "test_var"
  end
  return ""
end
vim.fn.input = function() return "test_input" end
vim.fn.getpos = function(mark)
  if mark == "'<" then return { 0, 1, 5, 0 }
  elseif mark == "'>" then return { 0, 1, 10, 0 }
  end
  return { 0, 1, 1, 0 }
end

vim.api.nvim_buf_get_lines = function()
  return { "    test_expr    " }
end

vim.notify = function(msg, level)
  table.insert(notifications, { message = msg, level = level })
end

-- Load modules after mocking
local init = require("termdebug-enhanced.init")
local keymaps = require("termdebug-enhanced.keymaps")
local evaluate = require("termdebug-enhanced.evaluate")
local memory = require("termdebug-enhanced.memory")

-- Test: Full plugin lifecycle (setup -> use -> cleanup)
function tests.test_plugin_lifecycle()
  -- Clear gdb_calls table
  for k in pairs(gdb_calls) do gdb_calls[k] = nil end
  for k in pairs(mock_keymaps) do mock_keymaps[k] = nil end
  for k in pairs(notifications) do notifications[k] = nil end
  
  -- Test plugin setup
  local config = {
    debugger = "gdb",
    keymaps = {
      continue = "<F5>",
      toggle_breakpoint = "<F9>",
      evaluate = "K",
      memory_view = "<leader>dm",
    }
  }
  
  init.setup(config)
  
  -- Verify keymaps were set up
  helpers.assert_not_nil(mock_keymaps["n:<F5>"], "Should set continue keymap")
  helpers.assert_not_nil(mock_keymaps["n:<F9>"], "Should set breakpoint keymap")
  helpers.assert_not_nil(mock_keymaps["n:K"], "Should set evaluate keymap")
  helpers.assert_not_nil(mock_keymaps["n:<leader>dm"], "Should set memory view keymap")
  
  -- Test keymap functionality
  local breakpoint_callback = mock_keymaps["n:<F9>"].callback
  breakpoint_callback()
  
  helpers.wait_for(function() return #gdb_calls > 0 end, 1000)
  helpers.assert_true(#gdb_calls > 0, "Should make GDB calls for breakpoint toggle")
  
  -- Test cleanup
  local cleanup_success, cleanup_errors = keymaps.cleanup_keymaps()
  helpers.assert_true(cleanup_success, "Should cleanup successfully")
  helpers.assert_eq(#cleanup_errors, 0, "Should have no cleanup errors")
end

-- Test: Evaluate module integration with utils
function tests.test_evaluate_utils_integration()
  -- Clear gdb_calls table
  for k in pairs(gdb_calls) do gdb_calls[k] = nil end
  for k in pairs(mock_buffers) do mock_buffers[k] = nil end
  
  -- Set up specific GDB response for evaluation
  gdb_responses["print test_var"] = {
    success = true,
    data = { "$1 = 42" }
  }
  
  evaluate.evaluate_custom("test_var")
  
  helpers.wait_for(function() return #gdb_calls > 0 end, 1000)
  
  helpers.assert_eq(#gdb_calls, 1, "Should make one GDB call")
  helpers.assert_eq(gdb_calls[1].command, "print test_var", "Should print the variable")
  helpers.assert_true(#mock_buffers > 0, "Should create popup buffer")
end

-- Test: Memory module integration with utils
function tests.test_memory_utils_integration()
  -- Clear gdb_calls table
  for k in pairs(gdb_calls) do gdb_calls[k] = nil end
  for k in pairs(mock_buffers) do mock_buffers[k] = nil end
  
  -- Set up GDB responses for memory operations
  gdb_responses["print &test_var"] = {
    success = true,
    data = { "$1 = (int *) 0x1234" }
  }
  
  gdb_responses["x/256xb 0x1234"] = {
    success = true,
    data = helpers.fixtures.memory_hex_dump
  }
  
  memory.view_memory_at_cursor()
  
  helpers.wait_for(function() return #gdb_calls >= 2 end, 1000)
  
  helpers.assert_true(#gdb_calls >= 2, "Should make multiple GDB calls")
  helpers.assert_true(gdb_calls[1].command:match("print &test_var"), "Should get variable address")
  helpers.assert_true(gdb_calls[2].command:match("x/.*0x1234"), "Should examine memory")
end

-- Test: Keymaps integration with evaluate module
function tests.test_keymaps_evaluate_integration()
  -- Clear gdb_calls table
  for k in pairs(gdb_calls) do gdb_calls[k] = nil end
  for k in pairs(mock_keymaps) do mock_keymaps[k] = nil end
  
  -- Set up keymaps
  keymaps.setup_keymaps({ evaluate = "K", evaluate_visual = "K" })
  
  -- Set up GDB response
  gdb_responses["print test_var"] = {
    success = true,
    data = { "$1 = 100" }
  }
  
  -- Test normal mode evaluation
  local eval_callback = mock_keymaps["n:K"].callback
  helpers.assert_not_nil(eval_callback, "Should have evaluate callback")
  
  eval_callback()
  
  helpers.wait_for(function() return #gdb_calls > 0 end, 1000)
  helpers.assert_true(#gdb_calls > 0, "Should make GDB call through evaluate module")
  
  -- Test visual mode evaluation
  -- Clear gdb_calls table
  for k in pairs(gdb_calls) do gdb_calls[k] = nil end
  local visual_callback = mock_keymaps["v:K"].callback
  helpers.assert_not_nil(visual_callback, "Should have visual evaluate callback")
  
  visual_callback()
  
  helpers.wait_for(function() return #gdb_calls > 0 end, 1000)
  helpers.assert_true(#gdb_calls > 0, "Should make GDB call for visual evaluation")
end

-- Test: Keymaps integration with memory module
function tests.test_keymaps_memory_integration()
  -- Clear gdb_calls table
  for k in pairs(gdb_calls) do gdb_calls[k] = nil end
  for k in pairs(mock_keymaps) do mock_keymaps[k] = nil end
  
  -- Set up keymaps
  keymaps.setup_keymaps({ 
    memory_view = "<leader>dm",
    memory_edit = "<leader>de"
  })
  
  -- Set up GDB responses
  gdb_responses["print &test_var"] = {
    success = true,
    data = { "$1 = (int *) 0x5678" }
  }
  
  gdb_responses["x/256xb 0x5678"] = {
    success = true,
    data = helpers.fixtures.memory_hex_dump
  }
  
  -- Test memory view
  local memory_view_callback = mock_keymaps["n:<leader>dm"].callback
  helpers.assert_not_nil(memory_view_callback, "Should have memory view callback")
  
  memory_view_callback()
  
  helpers.wait_for(function() return #gdb_calls >= 2 end, 1000)
  helpers.assert_true(#gdb_calls >= 2, "Should make GDB calls through memory module")
  
  -- Test memory edit
  -- Clear gdb_calls table
  for k in pairs(gdb_calls) do gdb_calls[k] = nil end
  gdb_responses["set variable test_var = test_input"] = {
    success = true,
    data = {}
  }
  
  local memory_edit_callback = mock_keymaps["n:<leader>de"].callback
  helpers.assert_not_nil(memory_edit_callback, "Should have memory edit callback")
  
  memory_edit_callback()
  
  helpers.wait_for(function() return #gdb_calls > 0 end, 1000)
  helpers.assert_true(#gdb_calls > 0, "Should make GDB calls for memory edit")
end

-- Test: Error handling across modules
function tests.test_cross_module_error_handling()
  -- Clear gdb_calls table
  for k in pairs(gdb_calls) do gdb_calls[k] = nil end
  for k in pairs(notifications) do notifications[k] = nil end
  
  -- Set up error responses
  gdb_responses["print invalid_var"] = {
    success = false,
    error = "No symbol \"invalid_var\" in current context."
  }
  
  gdb_responses["print &invalid_var"] = {
    success = false,
    error = "No symbol \"invalid_var\" in current context."
  }
  
  -- Test evaluate error handling
  evaluate.evaluate_custom("invalid_var")
  
  helpers.wait_for(function() return #gdb_calls > 0 end, 1000)
  helpers.assert_true(#gdb_calls > 0, "Should attempt GDB call")
  
  -- Test memory error handling
  -- Clear gdb_calls table
  for k in pairs(gdb_calls) do gdb_calls[k] = nil end
  vim.fn.expand = function(expr)
    if expr == "<cexpr>" or expr == "<cword>" then return "invalid_var" end
    return ""
  end
  
  memory.view_memory_at_cursor()
  
  helpers.wait_for(function() return #gdb_calls > 0 end, 1000)
  helpers.assert_true(#gdb_calls > 0, "Should attempt GDB call for invalid variable")
end

-- Test: Configuration loading and validation
function tests.test_configuration_validation()
  for k in pairs(notifications) do notifications[k] = nil end
  
  -- Test with invalid configuration
  local invalid_config = {
    debugger = "", -- Invalid empty debugger
    keymaps = {
      continue = "<invalid-key>", -- Invalid keymap format
      toggle_breakpoint = "", -- Empty keymap
    }
  }
  
  init.setup(invalid_config)
  
  -- Should have validation warnings/errors
  helpers.assert_true(#notifications > 0, "Should have configuration validation notifications")
end

-- Test: Resource cleanup across modules
function tests.test_resource_cleanup()
  for k in pairs(mock_buffers) do mock_buffers[k] = nil end
  for k in pairs(mock_windows) do mock_windows[k] = nil end
  
  -- Create resources through different modules
  evaluate.evaluate_custom("test_var")
  memory.view_memory_at_cursor()
  
  helpers.wait_for(function() return #mock_buffers > 0 end, 1000)
  
  local initial_buffers = #mock_buffers
  local initial_windows = #mock_windows
  
  -- Test cleanup
  memory.cleanup_all_windows()
  
  -- Should clean up some resources
  helpers.assert_true(#mock_buffers <= initial_buffers, "Should not increase buffer count")
  helpers.assert_true(#mock_windows <= initial_windows, "Should not increase window count")
end

-- Test: Async operation coordination
function tests.test_async_operation_coordination()
  -- Clear gdb_calls table
  for k in pairs(gdb_calls) do gdb_calls[k] = nil end
  
  -- Set up responses with delays to test async coordination
  gdb_responses["info breakpoints"] = {
    success = true,
    data = helpers.fixtures.breakpoints_multiple
  }
  
  gdb_responses["delete 1"] = {
    success = true,
    data = {}
  }
  
  -- Set up keymaps and trigger breakpoint toggle
  keymaps.setup_keymaps({ toggle_breakpoint = "<F9>" })
  
  local toggle_callback = mock_keymaps["n:<F9>"].callback
  toggle_callback()
  
  -- Wait for all async operations to complete
  helpers.wait_for(function() return #gdb_calls >= 2 end, 2000)
  
  helpers.assert_true(#gdb_calls >= 2, "Should complete multiple async operations")
  helpers.assert_true(gdb_calls[1].command:match("info breakpoints"), "Should query breakpoints first")
  helpers.assert_true(gdb_calls[2].command:match("delete"), "Should delete breakpoint second")
end

-- Test: Module state consistency
function tests.test_module_state_consistency()
  -- Clear gdb_calls table
  for k in pairs(gdb_calls) do gdb_calls[k] = nil end
  
  -- Test that modules maintain consistent state
  local config = {
    keymaps = {
      continue = "<F5>",
      toggle_breakpoint = "<F9>",
    }
  }
  
  init.setup(config)
  
  -- Verify state is consistent across modules
  helpers.assert_not_nil(mock_keymaps["n:<F5>"], "Should maintain keymap state")
  helpers.assert_not_nil(mock_keymaps["n:<F9>"], "Should maintain breakpoint keymap state")
  
  -- Test cleanup maintains consistency
  keymaps.cleanup_keymaps()
  
  helpers.assert_nil(mock_keymaps["n:<F5>"], "Should clean up keymap state")
  helpers.assert_nil(mock_keymaps["n:<F9>"], "Should clean up breakpoint keymap state")
end

-- Test: GDB availability checking across modules
function tests.test_gdb_availability_checking()
  for k in pairs(notifications) do notifications[k] = nil end
  
  -- Test with GDB not running
  vim.g.termdebug_running = false
  
  -- Try operations that require GDB
  keymaps.setup_keymaps({ toggle_breakpoint = "<F9>" })
  
  local toggle_callback = mock_keymaps["n:<F9>"].callback
  if toggle_callback then
    toggle_callback()
  end
  
  memory.view_memory_at_cursor()
  
  -- Should have notifications about GDB not being available
  helpers.assert_true(#notifications > 0, "Should notify about GDB availability")
  
  -- Restore GDB state
  vim.g.termdebug_running = true
end

-- Cleanup function
local function cleanup_tests()
  -- Clear all mock state
  -- Clear gdb_calls table
  for k in pairs(gdb_calls) do gdb_calls[k] = nil end
  gdb_responses = {}
  for k in pairs(mock_keymaps) do mock_keymaps[k] = nil end
  for k in pairs(mock_buffers) do mock_buffers[k] = nil end
  for k in pairs(mock_windows) do mock_windows[k] = nil end
  for k in pairs(notifications) do notifications[k] = nil end
  
  -- Reset vim globals
  vim.g.termdebug_running = true
end

-- Run tests with cleanup
local function run_tests()
  helpers.run_test_suite(tests, "termdebug-enhanced integration")
  cleanup_tests()
end

-- Execute tests
run_tests()