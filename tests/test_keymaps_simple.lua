---Simplified unit tests for termdebug-enhanced.keymaps module
---Run with: nvim --headless -u NONE -c "set rtp+=." -l tests/test_keymaps_simple.lua

-- Load test helpers
local helpers = require("tests.test_helpers")

-- Mock the utils module
package.loaded["termdebug-enhanced.utils"] = {
  async_gdb_response = function(cmd, callback, opts)
    -- Immediate callback for testing
    callback({}, nil)
  end,
  parse_breakpoints = function() return {} end,
  find_breakpoint = function() return nil end,
}

-- Mock the evaluate module
package.loaded["termdebug-enhanced.evaluate"] = {
  evaluate_under_cursor = function() end,
  evaluate_selection = function() end,
}

-- Mock the memory module
package.loaded["termdebug-enhanced.memory"] = {
  view_memory_at_cursor = function() end,
  edit_memory_at_cursor = function() end,
}

-- Mock vim globals
vim.g.termdebug_running = true

-- Mock keymap functions
local set_keymaps = {}
local deleted_keymaps = {}

vim.keymap.set = function(mode, key, callback, opts)
  set_keymaps[mode .. ":" .. key] = { callback = callback, opts = opts }
  return true
end

vim.keymap.del = function(mode, key)
  deleted_keymaps[mode .. ":" .. key] = true
  set_keymaps[mode .. ":" .. key] = nil
  return true
end

-- Mock other vim functions
vim.fn.line = function() return 42 end
vim.fn.expand = function(expr)
  if expr == "%:p" then return "/test/main.c"
  elseif expr == "<cword>" then return "test_var"
  end
  return ""
end
vim.fn.input = function() return "test_input" end
vim.cmd = function() end

-- Mock notifications
local notifications = {}
vim.notify = function(msg, level)
  table.insert(notifications, { message = msg, level = level })
end

local keymaps = require("termdebug-enhanced.keymaps")

-- Test suite
local tests = {}

-- Test configuration
local test_config = {
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
function tests.test_setup_keymaps_valid()
  set_keymaps = {}
  notifications = {}
  
  local success, errors = keymaps.setup_keymaps(test_config)
  
  helpers.assert_true(success, "Should succeed with valid config")
  helpers.assert_eq(#errors, 0, "Should have no errors")
  helpers.assert_not_nil(set_keymaps["n:<F5>"], "Should set continue keymap")
  helpers.assert_not_nil(set_keymaps["n:<F9>"], "Should set breakpoint keymap")
end

-- Test: setup_keymaps with invalid keymap
function tests.test_setup_keymaps_invalid()
  set_keymaps = {}
  notifications = {}
  
  local invalid_config = {
    continue = "",  -- Invalid empty keymap
    step_over = "<F10>",  -- Valid keymap
  }
  
  local success, errors = keymaps.setup_keymaps(invalid_config)
  
  helpers.assert_false(success, "Should fail with invalid config")
  helpers.assert_true(#errors > 0, "Should have validation errors")
  helpers.assert_not_nil(set_keymaps["n:<F10>"], "Should still set valid keymaps")
end

-- Test: cleanup_keymaps
function tests.test_cleanup_keymaps()
  set_keymaps = {}
  deleted_keymaps = {}
  
  -- First set up keymaps
  keymaps.setup_keymaps(test_config)
  helpers.assert_true(#set_keymaps > 0, "Should have set keymaps")
  
  -- Then clean them up
  local success, errors = keymaps.cleanup_keymaps()
  
  helpers.assert_true(success, "Should succeed cleaning up")
  helpers.assert_eq(#errors, 0, "Should have no cleanup errors")
  helpers.assert_true(#deleted_keymaps > 0, "Should have deleted keymaps")
end

-- Test: keymap validation
function tests.test_keymap_validation()
  set_keymaps = {}
  
  local config_with_invalid = {
    continue = "<invalid-key-format>",
    step_over = "   ",  -- whitespace only
    step_into = "<F11>",  -- valid
  }
  
  local success, errors = keymaps.setup_keymaps(config_with_invalid)
  
  helpers.assert_false(success, "Should fail with invalid keymaps")
  helpers.assert_true(#errors > 0, "Should have validation errors")
  helpers.assert_not_nil(set_keymaps["n:<F11>"], "Should set valid keymaps")
end

-- Test: GDB not running warning
function tests.test_gdb_not_running()
  vim.g.termdebug_running = false
  notifications = {}
  
  keymaps.setup_keymaps(test_config)
  
  helpers.assert_true(#notifications > 0, "Should have warning notification")
  
  -- Restore GDB state
  vim.g.termdebug_running = true
end

-- Run tests
helpers.run_test_suite(tests, "termdebug-enhanced.keymaps (simplified)")