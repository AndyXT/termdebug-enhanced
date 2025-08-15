---@class termdebug-enhanced.utils
---Simplified utilities module - delegates to specialized modules
local M = {}

local lib = require("termdebug-enhanced.lib")
local gdb = require("termdebug-enhanced.gdb")
local async = require("termdebug-enhanced.async")

-- Re-export commonly used functions for backward compatibility
M.find_gdb_buffer = gdb.find_gdb_buffer
M.invalidate_gdb_cache = gdb.invalidate_cache
M.parse_breakpoints = gdb.parse_breakpoints
M.find_breakpoint = gdb.find_breakpoint
M.extract_value = gdb.extract_value

M.async_gdb_response = async.gdb_response
M.debounce = async.debounce

-- Simple GDB response (synchronous-style wrapper)
function M.simple_gdb_response(command, callback, opts)
    return async.gdb_response(command, callback, opts)
end

-- Resource tracking (simplified)
local tracked_resources = {}

---Track a resource for cleanup
---@param id string Unique identifier
---@param resource_type string Type of resource
---@param resource any The resource
---@param cleanup_fn function|nil Cleanup function
function M.track_resource(id, resource_type, resource, cleanup_fn)
    tracked_resources[id] = {
        type = resource_type,
        resource = resource,
        cleanup = cleanup_fn,
    }
end

---Untrack a resource
---@param id string Resource identifier
function M.untrack_resource(id)
    tracked_resources[id] = nil
end

---Clean up a specific resource
---@param id string Resource identifier
---@return boolean success
function M.cleanup_resource(id)
    local resource = tracked_resources[id]
    if not resource then
        return false
    end
    
    if resource.cleanup then
        local ok = pcall(resource.cleanup, resource.resource)
        if not ok then
            return false
        end
    end
    
    tracked_resources[id] = nil
    return true
end

---Clean up all tracked resources
---@return number cleaned_count
function M.cleanup_all_resources()
    local count = 0
    
    for id, _ in pairs(tracked_resources) do
        if M.cleanup_resource(id) then
            count = count + 1
        end
    end
    
    -- Also cleanup async timers
    async.cleanup_timers()
    
    return count
end

---Get resource statistics
---@return table stats
function M.get_resource_stats()
    local stats = {}
    for _, resource in pairs(tracked_resources) do
        stats[resource.type] = (stats[resource.type] or 0) + 1
    end
    return stats
end

-- Validation helpers (simplified)
M.validation = {}

---Normalize memory address
---@param address string Address to normalize
---@return string|nil normalized, string|nil error
function M.validation.normalize_address(address)
    if not address or address == "" then
        return nil, "Empty address"
    end
    
    local trimmed = vim.trim(address)
    
    -- Already in hex format
    if trimmed:match("^0x%x+$") then
        return trimmed, nil
    end
    
    -- Decimal format - convert to hex
    if trimmed:match("^%d+$") then
        return string.format("0x%x", tonumber(trimmed)), nil
    end
    
    -- Variable or symbol name
    if trimmed:match("^[%a_][%w_]*$") then
        return trimmed, nil
    end
    
    return nil, "Invalid address format"
end

---Validate GDB command
---@param command string Command to validate
---@return boolean valid, string|nil error
function M.validation.validate_gdb_command(command)
    if not command or vim.trim(command) == "" then
        return false, "Empty command"
    end
    
    -- Basic dangerous command check
    local dangerous = {"quit", "exit", "shell", "!"}
    local lower = command:lower()
    for _, danger in ipairs(dangerous) do
        if lower:match("^%s*" .. danger) then
            return false, "Potentially dangerous command: " .. danger
        end
    end
    
    return true, nil
end

---Validate GDB command with suggestions
---@param command string Command to validate
---@return boolean valid, string|nil error, string|nil suggestion
function M.validation.validate_gdb_command_with_suggestions(command)
    local valid, error = M.validation.validate_gdb_command(command)
    local suggestion = nil
    
    if not valid then
        if error:match("Empty command") then
            suggestion = "Try 'print variable' or 'info breakpoints'"
        elseif error:match("dangerous command") then
            suggestion = "Use 'continue' or 'step' instead"
        end
    elseif command and command:match("^print$") then
        -- Provide suggestion for incomplete commands
        suggestion = "Add a variable name, e.g., 'print myVariable'"
    end
    
    return valid, error, suggestion
end

---Validate expression with hints
---@param expression string Expression to validate
---@return boolean valid, string|nil error, string|nil hint
function M.validation.validate_expression_with_hints(expression)
    if not expression or vim.trim(expression) == "" then
        return false, "Empty expression", "Enter a variable name or expression"
    end
    
    local trimmed = vim.trim(expression)
    local hint = nil
    
    -- Provide hints based on expression type
    if trimmed:match("->") then
        hint = "Pointer dereference detected"
    elseif trimmed:match("%[%d+%]") then
        hint = "Array indexing detected"
    end
    
    -- Check for unmatched parentheses
    local paren_count = 0
    for char in trimmed:gmatch(".") do
        if char == "(" then
            paren_count = paren_count + 1
        elseif char == ")" then
            paren_count = paren_count - 1
            if paren_count < 0 then
                return false, "Unmatched closing parenthesis", "Check your parentheses"
            end
        end
    end
    
    if paren_count ~= 0 then
        return false, "Unmatched opening parenthesis", "Missing closing parenthesis"
    end
    
    return true, nil, hint
end

---Normalize hex value
---@param hex_value string Hex value to normalize
---@return string|nil normalized, string|nil error, string|nil suggestion
function M.validation.normalize_hex_value(hex_value)
    if not hex_value or hex_value == "" then
        return nil, "Empty hex value", "Enter a hex value like 0xFF or FF"
    end
    
    local trimmed = vim.trim(hex_value)
    
    -- Remove 0x prefix if present
    local hex_part = trimmed:gsub("^0x", ""):gsub("^0X", "")
    
    -- Check if it's valid hex
    if not hex_part:match("^%x+$") then
        return nil, "Invalid hex format", "Use hex digits (0-9, A-F)"
    end
    
    -- Pad odd-length hex values with leading zero
    if #hex_part % 2 == 1 then
        hex_part = "0" .. hex_part
    end
    
    -- Return normalized with 0x prefix
    return "0x" .. hex_part:upper(), nil, nil
end

---Validate input based on type
---@param input_type string Type of input (expression, address, hex, command)
---@param value string Value to validate
---@return table result Validation result
function M.validation.validate_input(input_type, value)
    local result = {
        valid = false,
        normalized = nil,
        error = nil,
        suggestion = nil,
    }
    
    if input_type == "expression" then
        result.valid, result.error, result.suggestion = M.validation.validate_expression_with_hints(value)
        -- For expressions, the normalized form is the value itself if valid
        if result.valid then
            result.normalized = value
        end
    elseif input_type == "address" then
        result.normalized, result.error = M.validation.normalize_address(value)
        result.valid = result.normalized ~= nil
    elseif input_type == "hex" then
        result.normalized, result.error, result.suggestion = M.validation.normalize_hex_value(value)
        result.valid = result.normalized ~= nil
    elseif input_type == "command" then
        result.valid, result.error, result.suggestion = M.validation.validate_gdb_command_with_suggestions(value)
        -- For commands, the normalized form is the value itself if valid
        if result.valid then
            result.normalized = value
        end
    else
        result.error = "Unknown input type: " .. tostring(input_type)
    end
    
    return result
end

---Simple performance metrics (removed complex tracking)
function M.get_performance_metrics()
    return {}
end

function M.reset_performance_metrics()
    -- No-op for compatibility
end

-- Simplified cache (removed complex implementation)
local simple_cache = {}

function M.cache_gdb_info(key, data, ttl)
    simple_cache[key] = {
        data = data,
        expires = vim.loop.now() + (ttl or 5000),
    }
end

function M.get_cached_gdb_info(key)
    local entry = simple_cache[key]
    if entry and vim.loop.now() < entry.expires then
        return entry.data
    end
    simple_cache[key] = nil
    return nil
end

function M.clear_gdb_info_cache()
    simple_cache = {}
end

-- Cleanup debounced functions (compatibility)
function M.cleanup_debounced_functions()
    -- Handled by async module now
end

return M