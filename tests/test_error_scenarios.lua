---Comprehensive error scenario tests for termdebug-enhanced
---Tests edge cases, error conditions, and recovery mechanisms
---Run with: nvim --headless -u NONE -c "set rtp+=." -l tests/test_error_scenarios.lua

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
    setup_helper.setup_keymap_mocking(test_state)
end

local function teardown_test()
    if test_state then
        setup_helper.teardown_test_environment(test_state)
    end
end

-- Test: GDB timeout scenarios
function tests.test_gdb_timeout_handling()
    setup_test()
    
    -- Mock utils with timeout behavior
    package.loaded["termdebug-enhanced.utils"] = {
        async_gdb_response = function(cmd, callback, opts)
            table.insert(test_state.mock_calls.utils_calls, { command = cmd, opts = opts })
            -- Simulate timeout by calling callback with timeout error
            callback(nil, "Timeout: GDB did not respond within 3000ms")
        end,
        find_gdb_buffer = function() return 1 end,
    }
    
    local evaluate = require("termdebug-enhanced.evaluate")
    
    -- Should handle timeout gracefully
    local ok, err = pcall(evaluate.evaluate_custom, "test_var")
    helpers.assert_true(ok, "Should handle GDB timeout gracefully: " .. tostring(err))
    
    -- Should make a GDB call (which will timeout)
    helpers.assert_true(#test_state.mock_calls.utils_calls > 0, "Should attempt GDB call")
    
    teardown_test()
end

-- Test: Invalid memory address handling
function tests.test_invalid_memory_access()
    setup_test()
    
    -- Mock utils with memory access error
    package.loaded["termdebug-enhanced.utils"] = {
        async_gdb_response = function(cmd, callback, opts)
            table.insert(test_state.mock_calls.utils_calls, { command = cmd, opts = opts })
            if cmd:match("^x/") then
                callback(nil, "Cannot access memory at address 0xdeadbeef")
            else
                callback({}, nil)
            end
        end,
        extract_value = function() return nil end,
        find_gdb_buffer = function() return 1 end,
    }
    
    package.loaded["termdebug-enhanced"] = {
        config = {
            memory_viewer = { width = 80, height = 20, format = "hex", bytes_per_line = 16 }
        }
    }
    
    local memory = require("termdebug-enhanced.memory")
    
    -- Should handle invalid memory access gracefully
    local ok, err = pcall(memory.show_memory, "0xdeadbeef", 256)
    helpers.assert_true(ok, "Should handle invalid memory access gracefully: " .. tostring(err))
    
    -- Should create error display
    helpers.assert_true(#test_state.created_resources.buffers > 0, "Should create error display buffer")
    
    teardown_test()
end

-- Test: Vim API failure scenarios
function tests.test_vim_api_failures()
    setup_test()
    
    -- Mock vim API functions to fail
    vim.api.nvim_create_buf = function()
        error("Failed to create buffer: out of memory")
    end
    
    vim.api.nvim_open_win = function()
        error("Failed to open window: invalid configuration")
    end
    
    package.loaded["termdebug-enhanced.utils"] = setup_helper.create_mock_utils(test_state)
    
    local evaluate = require("termdebug-enhanced.evaluate")
    
    -- Should handle vim API failures gracefully
    local ok, err = pcall(evaluate.evaluate_custom, "test_var")
    helpers.assert_true(ok, "Should handle vim API failures gracefully: " .. tostring(err))
    
    teardown_test()
end

-- Test: Corrupted GDB buffer scenarios
function tests.test_corrupted_gdb_buffer()
    setup_test()
    
    -- Mock utils with corrupted buffer behavior
    package.loaded["termdebug-enhanced.utils"] = {
        async_gdb_response = function(cmd, callback, opts)
            table.insert(test_state.mock_calls.utils_calls, { command = cmd, opts = opts })
            -- Simulate corrupted/incomplete response
            callback({"(gdb) ", "Segmentation fault", "Program received signal SIGSEGV"}, nil)
        end,
        find_gdb_buffer = function() return nil end, -- Buffer not found
        extract_value = function() return nil end,
    }
    
    local evaluate = require("termdebug-enhanced.evaluate")
    
    -- Should handle missing GDB buffer gracefully
    local ok, err = pcall(evaluate.evaluate_custom, "test_var")
    helpers.assert_true(ok, "Should handle missing GDB buffer gracefully: " .. tostring(err))
    
    teardown_test()
end

-- Test: Module loading failures
function tests.test_module_loading_failures()
    setup_test()
    
    -- Temporarily break module loading
    local original_require = require
    _G.require = function(module_name)
        if module_name:match("termdebug%-enhanced%.evaluate") then
            error("Module not found: " .. module_name)
        end
        return original_require(module_name)
    end
    
    package.loaded["termdebug-enhanced.utils"] = setup_helper.create_mock_utils(test_state)
    
    local keymaps = require("termdebug-enhanced.keymaps")
    
    -- Should handle missing evaluate module gracefully
    local ok, err = pcall(keymaps.setup_keymaps, { evaluate = "K" })
    helpers.assert_true(ok, "Should handle missing evaluate module gracefully: " .. tostring(err))
    
    -- Restore require
    _G.require = original_require
    
    teardown_test()
end

-- Test: Invalid configuration scenarios
function tests.test_invalid_configuration()
    setup_test()
    
    package.loaded["termdebug-enhanced.utils"] = setup_helper.create_mock_utils(test_state)
    
    local init = require("termdebug-enhanced.init")
    
    -- Test with completely invalid config (function should cause tbl_deep_extend to fail)
    local function_config = function() end
    local ok1, err1 = init.setup(function_config)
    -- The function should fail at merge or validation
    helpers.assert_false(ok1, "Should reject function config")
    helpers.assert_true(type(err1) == "table" and #err1 > 0, "Should return validation errors")
    
    -- Test with partially invalid config that will fail validation
    local ok3, err3 = init.setup({
        debugger = "", -- Invalid empty debugger
        keymaps = {
            continue = 123, -- Invalid non-string keymap
        }
    })
    -- Should fail validation but not crash
    helpers.assert_false(ok3, "Should fail with invalid config")
    helpers.assert_true(type(err3) == "table" and #err3 > 0, "Should return validation errors")
    
    teardown_test()
end

-- Test: Permission/file system errors
function tests.test_filesystem_errors()
    setup_test()
    
    -- Mock file operations to fail
    vim.fn.filereadable = function() return 0 end -- Files not readable
    vim.fn.executable = function() return 0 end   -- Executables not found
    
    package.loaded["termdebug-enhanced.utils"] = setup_helper.create_mock_utils(test_state)
    
    local init = require("termdebug-enhanced.init")
    
    -- Should handle missing executables gracefully
    local ok, errors = init.setup({
        debugger = "nonexistent-gdb",
        gdbinit = "nonexistent.gdbinit"
    })
    
    helpers.assert_false(ok, "Should fail with missing executables")
    helpers.assert_true(#errors > 0, "Should report validation errors")
    
    -- Should mention specific issues
    local found_debugger_error = false
    for _, error in ipairs(errors) do
        if error:match("debugger") or error:match("executable") then
            found_debugger_error = true
            break
        end
    end
    helpers.assert_true(found_debugger_error, "Should report debugger availability issue")
    
    teardown_test()
end

-- Test: Race condition scenarios
function tests.test_race_conditions()
    setup_test()
    
    local call_count = 0
    
    -- Mock utils with race condition simulation
    package.loaded["termdebug-enhanced.utils"] = {
        async_gdb_response = function(cmd, callback, opts)
            call_count = call_count + 1
            table.insert(test_state.mock_calls.utils_calls, { command = cmd, opts = opts })
            
            -- Simulate rapid responses that could cause race conditions
            local response_delay = math.random(1, 5)
            vim.defer_fn(function()
                callback({ "$" .. call_count .. " = result_" .. call_count }, nil)
            end, response_delay)
        end,
        find_gdb_buffer = function() return 1 end,
        extract_value = function(lines)
            if lines and #lines > 0 then
                return lines[1]:match("= (.+)") or "no_value"
            end
            return nil
        end,
    }
    
    local evaluate = require("termdebug-enhanced.evaluate")
    
    -- Trigger multiple rapid evaluations
    for i = 1, 5 do
        local ok, err = pcall(evaluate.evaluate_custom, "var_" .. i)
        helpers.assert_true(ok, "Rapid evaluation " .. i .. " should not crash: " .. tostring(err))
    end
    
    -- Should handle multiple concurrent requests
    helpers.assert_true(#test_state.mock_calls.utils_calls >= 5, "Should handle multiple rapid requests")
    
    teardown_test()
end

-- Test: Memory exhaustion scenarios
function tests.test_memory_exhaustion()
    setup_test()
    
    -- Mock large memory allocations
    package.loaded["termdebug-enhanced.utils"] = {
        async_gdb_response = function(cmd, callback, opts)
            table.insert(test_state.mock_calls.utils_calls, { command = cmd, opts = opts })
            
            -- Simulate very large response that could cause memory issues
            local large_response = {}
            for i = 1, 1000 do -- Simulate large memory dump
                table.insert(large_response, string.format("0x%04x: %s", i * 16, string.rep("0x42 ", 16)))
            end
            
            callback(large_response, nil)
        end,
        find_gdb_buffer = function() return 1 end,
    }
    
    package.loaded["termdebug-enhanced"] = {
        config = {
            memory_viewer = { width = 80, height = 20, format = "hex", bytes_per_line = 16 }
        }
    }
    
    local memory = require("termdebug-enhanced.memory")
    
    -- Should handle large memory dumps gracefully
    local ok, err = pcall(memory.show_memory, "0x1000", 16384) -- Large memory size
    helpers.assert_true(ok, "Should handle large memory dumps gracefully: " .. tostring(err))
    
    teardown_test()
end

-- Test: Cleanup after errors
function tests.test_cleanup_after_errors()
    setup_test()
    
    package.loaded["termdebug-enhanced.utils"] = setup_helper.create_mock_utils(test_state)
    
    local keymaps = require("termdebug-enhanced.keymaps")
    
    -- Set up keymaps
    local ok1, err1 = keymaps.setup_keymaps({
        continue = "<F5>",
        step_over = "<F10>",
    })
    helpers.assert_true(ok1, "Setup should succeed: " .. tostring(err1))
    
    -- Verify keymaps were created
    local keymap_count = 0
    for _ in pairs(test_state.mock_calls.keymap_calls) do
        keymap_count = keymap_count + 1
    end
    helpers.assert_true(keymap_count > 0, "Should create keymaps")
    
    -- Now test cleanup
    local ok2, err2 = keymaps.cleanup_keymaps()
    helpers.assert_true(ok2, "Cleanup should succeed: " .. tostring(err2))
    
    teardown_test()
end

-- Run tests
helpers.run_test_suite(tests, "termdebug-enhanced error scenarios")