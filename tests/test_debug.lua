---Unit tests for termdebug-enhanced.debug module
---Run with: nvim --headless -u NONE -c "set rtp+=." -l tests/test_debug.lua

local helpers = require("tests.test_helpers")
local setup_helper = require("tests.test_setup_helper")

-- Test suite
local tests = {}

-- Test state
local test_state

-- Set up clean environment before each test
local function setup_test()
    test_state = setup_helper.setup_test_environment()
    setup_helper.setup_vim_api_mocking(test_state)
    
    -- Mock the utils module
    package.loaded["termdebug-enhanced.utils"] = setup_helper.create_mock_utils(test_state)
    
    -- Mock main module config
    package.loaded["termdebug-enhanced"] = {
        config = {
            popup = { border = "rounded", width = 60, height = 10 },
            memory_viewer = { width = 80, height = 20, format = "hex", bytes_per_line = 16 },
        }
    }
end

local function teardown_test()
    if test_state then
        setup_helper.teardown_test_environment(test_state)
    end
end

-- Test: debug module loads without errors
function tests.test_debug_module_loads()
    setup_test()
    
    local ok, debug_module = pcall(require, "termdebug-enhanced.debug")
    helpers.assert_true(ok, "Debug module should load without errors")
    helpers.assert_true(type(debug_module) == "table", "Debug module should return a table")
    
    teardown_test()
end

-- Test: test_popup function
function tests.test_popup_function()
    setup_test()
    
    local debug_module = require("termdebug-enhanced.debug")
    
    -- Should have test_popup function
    helpers.assert_true(type(debug_module.test_popup) == "function", "Should have test_popup function")
    
    -- Should execute without errors
    local ok, err = pcall(debug_module.test_popup)
    helpers.assert_true(ok, "test_popup should execute without errors: " .. tostring(err))
    
    -- Should create buffers/windows
    helpers.assert_true(#test_state.created_resources.buffers > 0, "Should create test buffers")
    
    teardown_test()
end

-- Test: test_gdb_response function  
function tests.test_gdb_response_function()
    setup_test()
    
    local debug_module = require("termdebug-enhanced.debug")
    
    -- Should have test_gdb_response function
    helpers.assert_true(type(debug_module.test_gdb_response) == "function", "Should have test_gdb_response function")
    
    -- Should execute without errors
    local ok, err = pcall(debug_module.test_gdb_response)
    helpers.assert_true(ok, "test_gdb_response should execute without errors: " .. tostring(err))
    
    -- Should generate notifications (the function always notifies)
    helpers.assert_true(#test_state.mock_calls.notifications > 0, "Should generate notifications")
    
    teardown_test()
end

-- Test: debug_all_buffers function
function tests.test_debug_all_buffers_function()
    setup_test()
    
    local debug_module = require("termdebug-enhanced.debug") 
    
    -- Should have debug_all_buffers function
    helpers.assert_true(type(debug_module.debug_all_buffers) == "function", "Should have debug_all_buffers function")
    
    -- Should execute without errors
    local ok, err = pcall(debug_module.debug_all_buffers)
    helpers.assert_true(ok, "debug_all_buffers should execute without errors: " .. tostring(err))
    
    -- Should generate notifications
    helpers.assert_true(#test_state.mock_calls.notifications > 0, "Should generate debug notifications")
    
    teardown_test()
end

-- Test: diagnose_gdb_functions function
function tests.test_diagnose_gdb_functions()
    setup_test()
    
    local debug_module = require("termdebug-enhanced.debug")
    
    -- Should have diagnose_gdb_functions function
    helpers.assert_true(type(debug_module.diagnose_gdb_functions) == "function", "Should have diagnose_gdb_functions function")
    
    -- Should execute without errors
    local ok, err = pcall(debug_module.diagnose_gdb_functions)
    helpers.assert_true(ok, "diagnose_gdb_functions should execute without errors: " .. tostring(err))
    
    -- Should generate diagnostic output
    helpers.assert_true(#test_state.mock_calls.notifications > 0, "Should generate diagnostic notifications")
    
    teardown_test()
end

-- Test: error handling with invalid GDB state
function tests.test_error_handling_no_gdb()
    setup_test()
    
    -- Set GDB as not running
    vim.g.termdebug_running = false
    
    local debug_module = require("termdebug-enhanced.debug")
    
    -- Functions should handle missing GDB gracefully
    local ok1, err1 = pcall(debug_module.test_gdb_response)
    helpers.assert_true(ok1, "Should handle missing GDB gracefully: " .. tostring(err1))
    
    local ok2, err2 = pcall(debug_module.diagnose_gdb_functions)
    helpers.assert_true(ok2, "Should handle missing GDB gracefully: " .. tostring(err2))
    
    teardown_test()
end

-- Test: error handling with termdebug not available
function tests.test_error_handling_no_termdebug()
    setup_test()
    
    -- Mock termdebug as not available
    vim.fn.exists = function(cmd)
        return 0 -- All commands return not available
    end
    
    local debug_module = require("termdebug-enhanced.debug")
    
    -- Functions should handle missing termdebug gracefully
    local ok, err = pcall(debug_module.diagnose_gdb_functions)
    helpers.assert_true(ok, "Should handle missing termdebug gracefully: " .. tostring(err))
    
    -- Should provide helpful diagnostic info
    helpers.assert_true(#test_state.mock_calls.notifications > 0, "Should provide diagnostic feedback")
    
    teardown_test()
end

-- Test: debug utilities with mock data
function tests.test_debug_utilities_with_mock_data()
    setup_test()
    
    -- Create some mock buffers
    vim.api.nvim_create_buf(false, true)
    vim.api.nvim_create_buf(false, true)
    
    local debug_module = require("termdebug-enhanced.debug")
    
    -- Debug all buffers with existing buffers
    local ok, err = pcall(debug_module.debug_all_buffers)
    helpers.assert_true(ok, "Should handle existing buffers: " .. tostring(err))
    
    -- Should report on the created buffers
    local found_buffer_info = false
    for _, notification in ipairs(test_state.mock_calls.notifications) do
        if notification.message:match("buffer") then
            found_buffer_info = true
            break
        end
    end
    helpers.assert_true(found_buffer_info, "Should report buffer information")
    
    teardown_test()
end

-- Run tests
helpers.run_test_suite(tests, "termdebug-enhanced.debug")