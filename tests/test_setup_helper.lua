---Common test setup and teardown utilities for termdebug-enhanced tests
---Provides consistent mocking, state management, and cleanup
local M = {}

---@class TestState
---@field original_vim_state table Original vim global state
---@field mock_calls table Tracking for mock function calls
---@field created_resources table Resources created during tests

---Initialize a clean test environment
---@return TestState Test state object for cleanup
function M.setup_test_environment()
    local state = {
        original_vim_state = {
            termdebug_running = vim.g.termdebug_running,
            exists = vim.fn.exists,
            executable = vim.fn.executable,
            input = vim.fn.input,
            expand = vim.fn.expand,
            line = vim.fn.line,
            getpos = vim.fn.getpos,
        },
        mock_calls = {
            utils_calls = {},
            keymap_calls = {},
            cmd_calls = {},
            notifications = {},
        },
        created_resources = {
            buffers = {},
            windows = {},
            timers = {},
        }
    }
    
    -- Clear all loaded modules for isolation
    local modules_to_clear = {
        "termdebug-enhanced.utils",
        "termdebug-enhanced.keymaps", 
        "termdebug-enhanced.evaluate",
        "termdebug-enhanced.memory",
        "termdebug-enhanced.init",
        "termdebug-enhanced"
    }
    
    for _, module in ipairs(modules_to_clear) do
        package.loaded[module] = nil
    end
    
    -- Set up consistent default state
    vim.g.termdebug_running = true
    
    -- Mock vim functions consistently
    vim.fn.exists = function(cmd)
        if cmd == ":Termdebug" then return 1 end
        return 0
    end
    
    vim.fn.executable = function(cmd)
        -- Mock common debuggers as available
        if cmd:match("gdb") or cmd:match("lldb") then return 1 end
        return 0
    end
    
    vim.fn.input = function(prompt)
        return "test_input"
    end
    
    vim.fn.expand = function(expr)
        if expr == "%:p" then return "/test/file.c"
        elseif expr == "<cword>" or expr == "<cexpr>" then return "test_var"
        end
        return ""
    end
    
    vim.fn.line = function(expr)
        if expr == "." then return 42 end
        return 1
    end
    
    vim.fn.getpos = function(mark)
        if mark == "'<" then return { 0, 1, 5, 0 }
        elseif mark == "'>" then return { 0, 1, 10, 0 }
        end
        return { 0, 1, 1, 0 }
    end
    
    return state
end

---Create a mock utils module with predictable responses
---@param state TestState Test state for tracking
---@return table Mock utils module
function M.create_mock_utils(state)
    return {
        async_gdb_response = function(cmd, callback, opts)
            table.insert(state.mock_calls.utils_calls, { command = cmd, opts = opts })
            
            -- Immediate response for synchronous testing
            if cmd:match("^info breakpoints") then
                callback({
                    "Num     Type           Disp Enb Address            What",
                    "1       breakpoint     keep y   0x00001234         in main at main.c:42",
                }, nil)
            elseif cmd:match("^print &") then
                local var = cmd:match("^print &(.+)")
                if var == "test_var" then
                    callback({ "$1 = (int *) 0x1234" }, nil)
                else
                    callback(nil, "No symbol found")
                end
            elseif cmd:match("^x/") then
                if cmd:match("invalid") then
                    callback(nil, "Cannot access memory")
                else
                    callback({
                        "0x1000:	0x12	0x34	0x56	0x78",
                        "0x1008:	0x9a	0xbc	0xde	0xf0",
                    }, nil)
                end
            elseif cmd:match("^print ") then
                callback({ "$1 = 42" }, nil)
            elseif cmd:match("^set ") then
                callback({}, nil)
            else
                callback(nil, "Unknown command: " .. cmd)
            end
        end,
        
        parse_breakpoints = function(lines)
            if not lines then return {} end
            return {
                { num = 1, file = "/test/main.c", line = 42, enabled = true },
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
                    if value then return value end
                end
            end
            return nil
        end,
        
        find_gdb_buffer = function() return 1 end,
        debounce = function(func, delay) return func end,
        
        simple_gdb_response = function(cmd, callback)
            table.insert(state.mock_calls.utils_calls, { command = cmd, simple = true })
            -- Immediate response for testing
            if cmd:match("print") then
                callback({ "$1 = 42" }, nil)
            else
                callback({ "(gdb) " .. cmd }, nil)
            end
        end,
    }
end

---Set up consistent keymap mocking
---@param state TestState Test state for tracking
function M.setup_keymap_mocking(state)
    local original_set = vim.keymap.set
    local original_del = vim.keymap.del
    
    state.original_vim_state.keymap_set = original_set
    state.original_vim_state.keymap_del = original_del
    
    vim.keymap.set = function(mode, key, callback, opts)
        state.mock_calls.keymap_calls[mode .. ":" .. key] = { 
            callback = callback, 
            opts = opts 
        }
        return true
    end
    
    vim.keymap.del = function(mode, key)
        state.mock_calls.keymap_calls[mode .. ":" .. key] = nil
        return true
    end
end

---Set up consistent vim API mocking
---@param state TestState Test state for tracking  
function M.setup_vim_api_mocking(state)
    local original_create_buf = vim.api.nvim_create_buf
    local original_open_win = vim.api.nvim_open_win
    local original_cmd = vim.cmd
    local original_notify = vim.notify
    
    state.original_vim_state.create_buf = original_create_buf
    state.original_vim_state.open_win = original_open_win
    state.original_vim_state.cmd = original_cmd
    state.original_vim_state.notify = original_notify
    
    vim.api.nvim_create_buf = function(listed, scratch)
        local buf = #state.created_resources.buffers + 100
        table.insert(state.created_resources.buffers, buf)
        return buf
    end
    
    vim.api.nvim_open_win = function(buf, enter, config)
        local win = #state.created_resources.windows + 200  
        table.insert(state.created_resources.windows, win)
        return win
    end
    
    vim.cmd = function(command)
        table.insert(state.mock_calls.cmd_calls, command)
    end
    
    vim.notify = function(msg, level)
        table.insert(state.mock_calls.notifications, { 
            message = msg, 
            level = level 
        })
    end
    
    -- Mock other commonly used vim API functions
    vim.api.nvim_buf_set_lines = function() end
    vim.api.nvim_buf_set_name = function() end  
    vim.api.nvim_buf_set_keymap = function() end
    vim.api.nvim_win_set_buf = function() end
    vim.api.nvim_get_current_win = function() return 1 end
    vim.api.nvim_win_is_valid = function(win)
        for _, w in ipairs(state.created_resources.windows) do
            if w == win then return true end
        end
        return false
    end
    vim.api.nvim_buf_is_valid = function(buf)
        for _, b in ipairs(state.created_resources.buffers) do
            if b == buf then return true end
        end
        return false
    end
end

---Clean up test environment and restore original state
---@param state TestState Test state to clean up
function M.teardown_test_environment(state)
    -- Restore vim global state
    vim.g.termdebug_running = state.original_vim_state.termdebug_running
    vim.fn.exists = state.original_vim_state.exists
    vim.fn.executable = state.original_vim_state.executable
    vim.fn.input = state.original_vim_state.input
    vim.fn.expand = state.original_vim_state.expand
    vim.fn.line = state.original_vim_state.line
    vim.fn.getpos = state.original_vim_state.getpos
    
    -- Restore vim API functions if they were mocked
    if state.original_vim_state.create_buf then
        vim.api.nvim_create_buf = state.original_vim_state.create_buf
    end
    if state.original_vim_state.open_win then
        vim.api.nvim_open_win = state.original_vim_state.open_win
    end
    if state.original_vim_state.cmd then
        vim.cmd = state.original_vim_state.cmd
    end
    if state.original_vim_state.notify then
        vim.notify = state.original_vim_state.notify
    end
    if state.original_vim_state.keymap_set then
        vim.keymap.set = state.original_vim_state.keymap_set
    end
    if state.original_vim_state.keymap_del then
        vim.keymap.del = state.original_vim_state.keymap_del
    end
    
    -- Clear created resources
    for _, timer in ipairs(state.created_resources.timers) do
        if timer and timer.close then
            pcall(timer.close, timer)
        end
    end
    
    -- Clear mock call tracking
    for k in pairs(state.mock_calls.utils_calls) do
        state.mock_calls.utils_calls[k] = nil
    end
    for k in pairs(state.mock_calls.keymap_calls) do
        state.mock_calls.keymap_calls[k] = nil
    end
    for k in pairs(state.mock_calls.cmd_calls) do
        state.mock_calls.cmd_calls[k] = nil
    end
    for k in pairs(state.mock_calls.notifications) do
        state.mock_calls.notifications[k] = nil
    end
end

---Assert that mock calls match expected patterns
---@param state TestState Test state with mock calls
---@param expected_calls table Expected call patterns
function M.assert_mock_calls(state, expected_calls)
    local helpers = require("tests.test_helpers")
    
    if expected_calls.utils_min then
        helpers.assert_true(
            #state.mock_calls.utils_calls >= expected_calls.utils_min,
            string.format("Expected at least %d utils calls, got %d", 
                expected_calls.utils_min, #state.mock_calls.utils_calls)
        )
    end
    
    if expected_calls.utils_patterns then
        for i, pattern in ipairs(expected_calls.utils_patterns) do
            if state.mock_calls.utils_calls[i] then
                helpers.assert_true(
                    state.mock_calls.utils_calls[i].command:match(pattern),
                    string.format("Utils call %d should match pattern '%s', got '%s'",
                        i, pattern, state.mock_calls.utils_calls[i].command)
                )
            else
                error(string.format("Expected utils call %d with pattern '%s', but no call found", i, pattern))
            end
        end
    end
    
    if expected_calls.notifications_min then
        helpers.assert_true(
            #state.mock_calls.notifications >= expected_calls.notifications_min,
            string.format("Expected at least %d notifications, got %d",
                expected_calls.notifications_min, #state.mock_calls.notifications)
        )
    end
end

return M