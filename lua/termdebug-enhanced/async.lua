---@class termdebug-enhanced.async
---Async operations and timer management
local M = {}

local lib = require("termdebug-enhanced.lib")
local gdb = require("termdebug-enhanced.gdb")

---@class AsyncOptions
---@field timeout number|nil Timeout in milliseconds
---@field poll_interval number|nil Polling interval in milliseconds
---@field max_lines number|nil Maximum lines to read

---@class GdbUtilsError
---@field type string Error type (timeout, command_failed, not_available, invalid_input)
---@field message string Human-readable error message
---@field command string|nil The GDB command that failed
---@field details string|nil Additional error details

-- Active timers tracking
local active_timers = {}

---Execute a GDB command and get response asynchronously
---@param command string GDB command to execute
---@param callback function Callback function(response, error)
---@param opts AsyncOptions|nil Options
function M.gdb_response(command, callback, opts)
    opts = opts or {}
    local timeout = opts.timeout or 3000
    local poll_interval = opts.poll_interval or 50
    local max_lines = opts.max_lines or 100
    
    -- Validate inputs
    if not command or command == "" then
        callback(nil, {
            type = "invalid_input",
            message = "Empty GDB command",
            command = command,
        })
        return
    end
    
    if not callback or type(callback) ~= "function" then
        vim.notify("async_gdb_response: Invalid callback function", vim.log.levels.ERROR)
        return
    end
    
    -- Check if debugging is active
    if not lib.is_debugging() then
        callback(nil, {
            type = "not_available",
            message = "No active debugging session",
            command = command,
        })
        return
    end
    
    -- Find GDB buffer
    local gdb_buf = gdb.find_gdb_buffer()
    if not gdb_buf then
        callback(nil, {
            type = "not_available",
            message = "GDB buffer not found",
            command = command,
        })
        return
    end
    
    -- Get initial line count
    local initial_lines = vim.api.nvim_buf_line_count(gdb_buf)
    
    -- Send command to GDB
    local send_ok = pcall(function()
        if vim.fn.exists("*TermDebugSendCommand") == 1 then
            vim.fn.TermDebugSendCommand(command)
        elseif vim.fn.exists(":Evaluate") == 2 then
            vim.cmd("Evaluate " .. command)
        else
            error("No GDB command interface available")
        end
    end)
    
    if not send_ok then
        callback(nil, {
            type = "command_failed",
            message = "Failed to send command to GDB",
            command = command,
        })
        return
    end
    
    -- Poll for response
    local elapsed = 0
    local timer = vim.loop.new_timer()
    
    -- Track timer for cleanup
    table.insert(active_timers, timer)
    
    timer:start(
        poll_interval,
        poll_interval,
        vim.schedule_wrap(function()
            elapsed = elapsed + poll_interval
            
            -- Check timeout
            if elapsed >= timeout then
                timer:stop()
                timer:close()
                M.remove_timer(timer)
                
                callback(nil, {
                    type = "timeout",
                    message = string.format("GDB command timed out after %dms", timeout),
                    command = command,
                })
                return
            end
            
            -- Check for new output
            local current_lines = vim.api.nvim_buf_line_count(gdb_buf)
            if current_lines > initial_lines then
                timer:stop()
                timer:close()
                M.remove_timer(timer)
                
                -- Get the new lines
                local start_line = math.max(0, initial_lines)
                local end_line = math.min(current_lines, initial_lines + max_lines)
                local response_lines = vim.api.nvim_buf_get_lines(gdb_buf, start_line, end_line, false)
                
                -- Filter out prompts and empty lines
                local filtered = {}
                for _, line in ipairs(response_lines) do
                    if line ~= "(gdb)" and line ~= "" and not line:match("^%(gdb%)%s*$") then
                        table.insert(filtered, line)
                    end
                end
                
                callback(filtered, nil)
            end
        end)
    )
end

---Remove timer from active list
---@param timer userdata Timer to remove
function M.remove_timer(timer)
    for i, t in ipairs(active_timers) do
        if t == timer then
            table.remove(active_timers, i)
            break
        end
    end
end

---Clean up all active timers
function M.cleanup_timers()
    for _, timer in ipairs(active_timers) do
        if timer and not timer:is_closing() then
            timer:stop()
            timer:close()
        end
    end
    active_timers = {}
end

-- Storage for debounced timers
local debounce_timers = {}

---Debounce a function
---@param func function Function to debounce
---@param delay number Delay in milliseconds
---@param key string|nil Unique key for this debounced function (optional)
---@return function Debounced function
function M.debounce(func, delay, key)
    -- If no key provided, generate one based on function
    key = key or tostring(func)
    
    return function(...)
        local args = {...}
        
        -- Cancel existing timer for this key
        if debounce_timers[key] then
            debounce_timers[key]:stop()
            debounce_timers[key]:close()
        end
        
        -- Create new timer
        debounce_timers[key] = vim.loop.new_timer()
        debounce_timers[key]:start(
            delay,
            0,
            vim.schedule_wrap(function()
                debounce_timers[key]:close()
                debounce_timers[key] = nil
                func(unpack(args))
            end)
        )
    end
end

return M