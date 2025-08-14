---Unit tests for termdebug-enhanced.keymaps module
---Run with: nvim -l tests/test_keymaps.lua

-- IMPORTANT: Clear any previously loaded modules to ensure mocks are used
package.loaded["termdebug-enhanced.utils"] = nil
package.loaded["termdebug-enhanced.keymaps"] = nil
package.loaded["termdebug-enhanced.evaluate"] = nil
package.loaded["termdebug-enhanced.memory"] = nil
package.loaded["termdebug-enhanced"] = nil

-- Load test helpers
local helpers = require("tests.test_helpers")

-- Mock the utils module before requiring keymaps
local mock_utils_calls = {}
package.loaded["termdebug-enhanced.utils"] = {
  async_gdb_response = function(cmd, callback, opts)
    table.insert(mock_utils_calls, { command = cmd, opts = opts })
    
    -- Execute callback immediately for testing (no async delay)
    if cmd:match("^info breakpoints") then
      -- Return breakpoint list or empty
      if cmd:match("empty") then
        callback(nil, "No breakpoints or watchpoints.")
      else
        callback(helpers.fixtures.breakpoints_multiple, nil)
      end
    elseif cmd:match("^break ") then
      -- Breakpoint setting
      callback({}, nil)
    elseif cmd:match("^delete ") then
      -- Breakpoint deletion
      callback({}, nil)
    elseif cmd:match("^display ") then
      -- Watch expression
      callback({}, nil)
    elseif cmd:match("^set variable ") then
      -- Variable setting
      callback({}, nil)
    else
      callback(nil, "Unknown command")
    end
  end,
  
  parse_breakpoints = function(lines)
    -- Mock breakpoint parsing
    return {
      { num = 1, file = "/test/main.c", line = 42, enabled = true },
      { num = 2, file = "/test/main.c", line = 15, enabled = false },
    }
  end,
  
  find_breakpoint = function(breakpoints, file, line)
    -- Mock breakpoint finding
    for _, bp in ipairs(breakpoints) do
      if bp.file:match("main.c") and bp.line == line then
        return bp.num
      end
    end
    return nil
  end,
  
  -- Add missing mock functions that modules might use
  track_resource = function() end,
  untrack_resource = function() end,
  cleanup_all_resources = function() return 0 end,
  get_resource_stats = function() return {} end,
  get_performance_metrics = function() return { avg_response_time = 0 } end,
}

-- Mock the evaluate module
local mock_evaluate_calls = {}
package.loaded["termdebug-enhanced.evaluate"] = {
  evaluate_under_cursor = function()
    table.insert(mock_evaluate_calls, "evaluate_under_cursor")
  end,
  
  evaluate_selection = function()
    table.insert(mock_evaluate_calls, "evaluate_selection")
  end,
}

-- Mock the memory module
local mock_memory_calls = {}
package.loaded["termdebug-enhanced.memory"] = {
  view_memory_at_cursor = function()
    table.insert(mock_memory_calls, "view_memory_at_cursor")
  end,
  
  edit_memory_at_cursor = function()
    table.insert(mock_memory_calls, "edit_memory_at_cursor")
  end,
}

-- Mock vim globals for GDB state
vim.g.termdebug_running = true
vim.fn.exists = function(cmd)
  if cmd == ":Termdebug" then return 1 end
  return 0
end

local keymaps = require("termdebug-enhanced.keymaps")

-- Test suite
local tests = {}

-- Mock keymap functions for testing
local set_keymaps = {}
local deleted_keymaps = {}

local original_keymap_set = vim.keymap.set
local original_keymap_del = vim.keymap.del

vim.keymap.set = function(mode, key, callback, opts)
  set_keymaps[mode .. ":" .. key] = { callback = callback, opts = opts }
  return true
end

vim.keymap.del = function(mode, key)
  deleted_keymaps[mode .. ":" .. key] = true
  return true
end

-- Mock vim functions for testing
local mock_line_value = 42
local mock_file_value = "/test/main.c"
local mock_cword_value = "test_var"
local mock_input_value = ""

vim.fn.line = function(expr)
  if expr == "." then
    return mock_line_value
  end
  return 1
end

vim.fn.expand = function(expr)
  if expr == "%:p" then
    return mock_file_value
  elseif expr == "<cword>" then
    return mock_cword_value
  end
  return ""
end

vim.fn.input = function(prompt)
  return mock_input_value
end

-- Mock vim.cmd for testing
local cmd_calls = {}
local original_cmd = vim.cmd
vim.cmd = function(command)
  table.insert(cmd_calls, command)
  -- Don't actually execute commands in tests
end

-- Mock vim.notify for testing notifications
local notifications = {}
local original_notify = vim.notify
vim.notify = function(msg, level)
  table.insert(notifications, { message = msg, level = level })
end

-- Test configuration
local test_keymap_config = {
  continue = "<F5>",
  step_over = "<F10>",
  step_into = "<F11>",
  step_out = "<S-F11>",
  stop = "<S-F5>",
  restart = "<C-S-F5>",
  toggle_breakpoint = "<F9>",
  evaluate = "K",
  evaluate_visual = "K",
  watch_add = "<leader>dw",
  memory_view = "<leader>dm",
  memory_edit = "<leader>de",
  variable_set = "<leader>ds",
}

-- Test: setup_keymaps with valid configuration
function tests.test_setup_keymaps_valid_config()
  -- Clear the module-level tables (not create new local ones)
  for k in pairs(set_keymaps) do set_keymaps[k] = nil end
  for k in pairs(notifications) do notifications[k] = nil end
  
  local success, errors = keymaps.setup_keymaps(test_keymap_config)
  
  helpers.assert_true(success, "Should succeed with valid config")
  helpers.assert_eq(#errors, 0, "Should have no errors")
  
  -- Check that keymaps were set
  helpers.assert_not_nil(set_keymaps["n:<F5>"], "Should set continue keymap")
  helpers.assert_not_nil(set_keymaps["n:<F10>"], "Should set step_over keymap")
  helpers.assert_not_nil(set_keymaps["n:<F11>"], "Should set step_into keymap")
  helpers.assert_not_nil(set_keymaps["n:<F9>"], "Should set toggle_breakpoint keymap")
  helpers.assert_not_nil(set_keymaps["n:K"], "Should set evaluate keymap")
  helpers.assert_not_nil(set_keymaps["v:K"], "Should set evaluate_visual keymap")
  
  -- Check success notification
  helpers.assert_true(#notifications > 0, "Should have success notification")
end

-- Test: setup_keymaps with invalid keymap format
function tests.test_setup_keymaps_invalid_format()
  local invalid_config = vim.tbl_deep_extend("force", test_keymap_config, {
    continue = "<invalid-key-format>",
    step_over = "",
    step_into = "   ", -- whitespace only
  })
  
  -- Clear the module-level tables (not create new local ones)
  for k in pairs(set_keymaps) do set_keymaps[k] = nil end
  for k in pairs(notifications) do notifications[k] = nil end
  
  local success, errors = keymaps.setup_keymaps(invalid_config)
  
  helpers.assert_false(success, "Should fail with invalid config")
  helpers.assert_true(#errors > 0, "Should have validation errors")
  
  -- Check that some keymaps were still set (valid ones)
  helpers.assert_not_nil(set_keymaps["n:<F11>"], "Should still set valid keymaps")
end

-- Test: setup_keymaps with GDB not running
function tests.test_setup_keymaps_gdb_not_running()
  vim.g.termdebug_running = false
  -- Clear the module-level tables (not create new local ones)
  for k in pairs(set_keymaps) do set_keymaps[k] = nil end
  for k in pairs(notifications) do notifications[k] = nil end
  
  local success, errors = keymaps.setup_keymaps(test_keymap_config)
  
  -- Should still succeed but with warning
  helpers.assert_true(success, "Should succeed even when GDB not running")
  helpers.assert_true(#notifications > 0, "Should have warning notification")
  
  -- Restore GDB state
  vim.g.termdebug_running = true
end

-- Test: setup_keymaps with termdebug not available
function tests.test_setup_keymaps_termdebug_not_available()
  -- Mock vim.fn.exists to return 0 (not available)
  local original_exists = vim.fn.exists
  vim.fn.exists = function(cmd)
    if cmd == ":Termdebug" then
      return 0
    end
    return original_exists(cmd)
  end
  
  -- Clear the module-level tables (not create new local ones)
  for k in pairs(set_keymaps) do set_keymaps[k] = nil end
  for k in pairs(notifications) do notifications[k] = nil end
  
  local success, errors = keymaps.setup_keymaps(test_keymap_config)
  
  -- Should still succeed but with warning
  helpers.assert_true(success, "Should succeed even when termdebug not available")
  helpers.assert_true(#notifications > 0, "Should have warning notification")
  
  -- Restore
  vim.fn.exists = original_exists
end

-- Test: cleanup_keymaps with active keymaps
function tests.test_cleanup_keymaps_with_active()
  -- First set up keymaps
  -- Clear the module-level tables (not create new local ones)
  for k in pairs(set_keymaps) do set_keymaps[k] = nil end
  for k in pairs(deleted_keymaps) do deleted_keymaps[k] = nil end
  for k in pairs(notifications) do notifications[k] = nil end
  
  keymaps.setup_keymaps(test_keymap_config)
  
  -- Then clean them up
  local success, errors = keymaps.cleanup_keymaps()
  
  helpers.assert_true(success, "Should succeed cleaning up keymaps")
  helpers.assert_eq(#errors, 0, "Should have no cleanup errors")
  
  -- Check that keymaps were deleted
  helpers.assert_true(#deleted_keymaps > 0, "Should delete some keymaps")
end

-- Test: cleanup_keymaps with no active keymaps
function tests.test_cleanup_keymaps_no_active()
  -- Clear any existing state
  package.loaded["termdebug-enhanced.keymaps"] = nil
  keymaps = require("termdebug-enhanced.keymaps")
  
  for k in pairs(deleted_keymaps) do deleted_keymaps[k] = nil end
  for k in pairs(notifications) do notifications[k] = nil end
  
  local success, errors = keymaps.cleanup_keymaps()
  
  helpers.assert_true(success, "Should succeed with no active keymaps")
  helpers.assert_eq(#errors, 0, "Should have no errors")
  helpers.assert_eq(#deleted_keymaps, 0, "Should not delete any keymaps")
end

-- Test: breakpoint toggle functionality
function tests.test_breakpoint_toggle_functionality()
  for k in pairs(set_keymaps) do set_keymaps[k] = nil end
  for k in pairs(mock_utils_calls) do mock_utils_calls[k] = nil end
  for k in pairs(notifications) do notifications[k] = nil end
  mock_line_value = 42
  mock_file_value = "/test/main.c"
  
  keymaps.setup_keymaps({ toggle_breakpoint = "<F9>" })
  
  -- Get the toggle breakpoint callback
  local toggle_callback = set_keymaps["n:<F9>"].callback
  helpers.assert_not_nil(toggle_callback, "Should have toggle breakpoint callback")
  
  -- Execute the callback
  toggle_callback()
  
  -- Since we're executing synchronously now, no need to wait
  helpers.assert_true(#mock_utils_calls >= 1, "Should make GDB call for breakpoint info")
  helpers.assert_true(mock_utils_calls[1].command:match("info breakpoints"), "Should query breakpoint info")
end

-- Test: breakpoint toggle with no file open
function tests.test_breakpoint_toggle_no_file()
  for k in pairs(set_keymaps) do set_keymaps[k] = nil end
  for k in pairs(mock_utils_calls) do mock_utils_calls[k] = nil end
  for k in pairs(notifications) do notifications[k] = nil end
  mock_file_value = ""
  
  keymaps.setup_keymaps({ toggle_breakpoint = "<F9>" })
  
  local toggle_callback = set_keymaps["n:<F9>"].callback
  toggle_callback()
  
  -- Should not make GDB calls when no file
  helpers.assert_eq(#mock_utils_calls, 0, "Should not make GDB calls with no file")
  helpers.assert_true(#notifications > 0, "Should notify about no file")
end

-- Test: breakpoint toggle with GDB not running
function tests.test_breakpoint_toggle_gdb_not_running()
  vim.g.termdebug_running = false
  for k in pairs(set_keymaps) do set_keymaps[k] = nil end
  for k in pairs(mock_utils_calls) do mock_utils_calls[k] = nil end
  for k in pairs(notifications) do notifications[k] = nil end
  mock_file_value = "/test/main.c"
  
  keymaps.setup_keymaps({ toggle_breakpoint = "<F9>" })
  
  local toggle_callback = set_keymaps["n:<F9>"].callback
  toggle_callback()
  
  helpers.assert_eq(#mock_utils_calls, 0, "Should not make GDB calls when GDB not running")
  helpers.assert_true(#notifications > 0, "Should notify about GDB not running")
  
  -- Restore GDB state
  vim.g.termdebug_running = true
end

-- Test: evaluate keymap functionality
function tests.test_evaluate_keymap_functionality()
  for k in pairs(set_keymaps) do set_keymaps[k] = nil end
  mock_evaluate_calls = {}
  
  keymaps.setup_keymaps({ evaluate = "K" })
  
  local evaluate_callback = set_keymaps["n:K"].callback
  helpers.assert_not_nil(evaluate_callback, "Should have evaluate callback")
  
  evaluate_callback()
  
  helpers.assert_eq(#mock_evaluate_calls, 1, "Should call evaluate function")
  helpers.assert_eq(mock_evaluate_calls[1], "evaluate_under_cursor", "Should call correct evaluate function")
end

-- Test: evaluate visual keymap functionality
function tests.test_evaluate_visual_keymap_functionality()
  for k in pairs(set_keymaps) do set_keymaps[k] = nil end
  mock_evaluate_calls = {}
  
  keymaps.setup_keymaps({ evaluate_visual = "K" })
  
  local evaluate_callback = set_keymaps["v:K"].callback
  helpers.assert_not_nil(evaluate_callback, "Should have visual evaluate callback")
  
  evaluate_callback()
  
  helpers.assert_eq(#mock_evaluate_calls, 1, "Should call evaluate function")
  helpers.assert_eq(mock_evaluate_calls[1], "evaluate_selection", "Should call correct evaluate function")
end

-- Test: memory view keymap functionality
function tests.test_memory_view_keymap_functionality()
  for k in pairs(set_keymaps) do set_keymaps[k] = nil end
  mock_memory_calls = {}
  
  keymaps.setup_keymaps({ memory_view = "<leader>dm" })
  
  local memory_callback = set_keymaps["n:<leader>dm"].callback
  helpers.assert_not_nil(memory_callback, "Should have memory view callback")
  
  memory_callback()
  
  helpers.assert_eq(#mock_memory_calls, 1, "Should call memory function")
  helpers.assert_eq(mock_memory_calls[1], "view_memory_at_cursor", "Should call correct memory function")
end

-- Test: memory edit keymap functionality
function tests.test_memory_edit_keymap_functionality()
  for k in pairs(set_keymaps) do set_keymaps[k] = nil end
  mock_memory_calls = {}
  
  keymaps.setup_keymaps({ memory_edit = "<leader>de" })
  
  local memory_callback = set_keymaps["n:<leader>de"].callback
  helpers.assert_not_nil(memory_callback, "Should have memory edit callback")
  
  memory_callback()
  
  helpers.assert_eq(#mock_memory_calls, 1, "Should call memory function")
  helpers.assert_eq(mock_memory_calls[1], "edit_memory_at_cursor", "Should call correct memory function")
end

-- Test: watch add keymap functionality
function tests.test_watch_add_keymap_functionality()
  for k in pairs(set_keymaps) do set_keymaps[k] = nil end
  for k in pairs(mock_utils_calls) do mock_utils_calls[k] = nil end
  mock_input_value = "test_expr"
  
  keymaps.setup_keymaps({ watch_add = "<leader>dw" })
  
  local watch_callback = set_keymaps["n:<leader>dw"].callback
  helpers.assert_not_nil(watch_callback, "Should have watch add callback")
  
  watch_callback()
  
  -- Since we're executing synchronously now, no need to wait
  helpers.assert_true(#mock_utils_calls >= 1, "Should make GDB call for watch")
  helpers.assert_true(mock_utils_calls[1].command:match("display test_expr"), "Should add watch expression")
end

-- Test: watch add with empty input
function tests.test_watch_add_empty_input()
  for k in pairs(set_keymaps) do set_keymaps[k] = nil end
  for k in pairs(mock_utils_calls) do mock_utils_calls[k] = nil end
  mock_input_value = ""
  
  keymaps.setup_keymaps({ watch_add = "<leader>dw" })
  
  local watch_callback = set_keymaps["n:<leader>dw"].callback
  watch_callback()
  
  -- Should not make GDB calls with empty input
  helpers.assert_eq(#mock_utils_calls, 0, "Should not make GDB calls with empty input")
end

-- Test: variable set keymap functionality
function tests.test_variable_set_keymap_functionality()
  for k in pairs(set_keymaps) do set_keymaps[k] = nil end
  for k in pairs(mock_utils_calls) do mock_utils_calls[k] = nil end
  mock_cword_value = "test_var"
  mock_input_value = "100"
  
  keymaps.setup_keymaps({ variable_set = "<leader>ds" })
  
  local var_callback = set_keymaps["n:<leader>ds"].callback
  helpers.assert_not_nil(var_callback, "Should have variable set callback")
  
  var_callback()
  
  -- Since we're executing synchronously now, no need to wait
  helpers.assert_true(#mock_utils_calls >= 1, "Should make GDB call for variable set")
  helpers.assert_true(mock_utils_calls[1].command:match("set variable test_var = 100"), "Should set variable correctly")
end

-- Test: variable set with no word under cursor
function tests.test_variable_set_no_word()
  for k in pairs(set_keymaps) do set_keymaps[k] = nil end
  for k in pairs(mock_utils_calls) do mock_utils_calls[k] = nil end
  for k in pairs(notifications) do notifications[k] = nil end
  mock_cword_value = ""
  
  keymaps.setup_keymaps({ variable_set = "<leader>ds" })
  
  local var_callback = set_keymaps["n:<leader>ds"].callback
  var_callback()
  
  helpers.assert_eq(#mock_utils_calls, 0, "Should not make GDB calls with no word")
  helpers.assert_true(#notifications > 0, "Should notify about no variable")
end

-- Test: variable set with empty value
function tests.test_variable_set_empty_value()
  for k in pairs(set_keymaps) do set_keymaps[k] = nil end
  for k in pairs(mock_utils_calls) do mock_utils_calls[k] = nil end
  mock_cword_value = "test_var"
  mock_input_value = ""
  
  keymaps.setup_keymaps({ variable_set = "<leader>ds" })
  
  local var_callback = set_keymaps["n:<leader>ds"].callback
  var_callback()
  
  helpers.assert_eq(#mock_utils_calls, 0, "Should not make GDB calls with empty value")
end

-- Test: restart keymap functionality
function tests.test_restart_keymap_functionality()
  for k in pairs(set_keymaps) do set_keymaps[k] = nil end
  for k in pairs(cmd_calls) do cmd_calls[k] = nil end
  
  keymaps.setup_keymaps({ restart = "<C-S-F5>" })
  
  local restart_callback = set_keymaps["n:<C-S-F5>"].callback
  helpers.assert_not_nil(restart_callback, "Should have restart callback")
  
  restart_callback()
  
  -- Should call Stop command immediately
  helpers.assert_true(#cmd_calls >= 1, "Should make command calls")
  helpers.assert_eq(cmd_calls[1], "Stop", "Should call Stop command first")
  
  -- Wait for deferred Run command
  helpers.wait_for(function() return #cmd_calls >= 2 end, 200)
  helpers.assert_eq(cmd_calls[2], "Run", "Should call Run command after delay")
end

-- Test: standard debugging keymaps functionality
function tests.test_standard_debugging_keymaps()
  for k in pairs(set_keymaps) do set_keymaps[k] = nil end
  for k in pairs(cmd_calls) do cmd_calls[k] = nil end
  
  keymaps.setup_keymaps({
    continue = "<F5>",
    step_over = "<F10>",
    step_into = "<F11>",
    step_out = "<S-F11>",
    stop = "<S-F5>",
  })
  
  -- Test each keymap
  local continue_callback = set_keymaps["n:<F5>"].callback
  continue_callback()
  helpers.assert_contains(table.concat(cmd_calls, " "), "Continue", "Should call Continue command")
  
  for k in pairs(cmd_calls) do cmd_calls[k] = nil end
  local step_over_callback = set_keymaps["n:<F10>"].callback
  step_over_callback()
  helpers.assert_contains(table.concat(cmd_calls, " "), "Over", "Should call Over command")
  
  for k in pairs(cmd_calls) do cmd_calls[k] = nil end
  local step_into_callback = set_keymaps["n:<F11>"].callback
  step_into_callback()
  helpers.assert_contains(table.concat(cmd_calls, " "), "Step", "Should call Step command")
  
  for k in pairs(cmd_calls) do cmd_calls[k] = nil end
  local step_out_callback = set_keymaps["n:<S-F11>"].callback
  step_out_callback()
  helpers.assert_contains(table.concat(cmd_calls, " "), "Finish", "Should call Finish command")
  
  for k in pairs(cmd_calls) do cmd_calls[k] = nil end
  local stop_callback = set_keymaps["n:<S-F5>"].callback
  stop_callback()
  helpers.assert_contains(table.concat(cmd_calls, " "), "Stop", "Should call Stop command")
end

-- Cleanup function
local function cleanup_tests()
  -- Restore original functions
  vim.keymap.set = original_keymap_set
  vim.keymap.del = original_keymap_del
  vim.cmd = original_cmd
  vim.notify = original_notify
  
  -- Clear mock state
  for k in pairs(set_keymaps) do set_keymaps[k] = nil end
  for k in pairs(deleted_keymaps) do deleted_keymaps[k] = nil end
  for k in pairs(mock_utils_calls) do mock_utils_calls[k] = nil end
  mock_evaluate_calls = {}
  mock_memory_calls = {}
  for k in pairs(notifications) do notifications[k] = nil end
  for k in pairs(cmd_calls) do cmd_calls[k] = nil end
end

-- Run tests with cleanup
local function run_tests()
  helpers.run_test_suite(tests, "termdebug-enhanced.keymaps")
  cleanup_tests()
end

-- Execute tests
run_tests()