---@class termdebug-enhanced.gdb
---GDB communication and buffer management
local M = {}

local lib = require("termdebug-enhanced.lib")

---@class GdbBufferCache
---@field buffer number|nil Cached buffer number
---@field last_check number Last check timestamp
---@field cache_duration number Cache duration in milliseconds

-- Cache for GDB buffer to improve performance
---@type GdbBufferCache
local gdb_buffer_cache = {
    buffer = nil,
    last_check = 0,
    cache_duration = 2000, -- Cache for 2 seconds
}

---Find the GDB buffer
---Uses caching to improve performance, avoiding repeated buffer searches
---@return number|nil bufnr Buffer number or nil if not found
function M.find_gdb_buffer()
    local now = vim.loop.now()
    
    -- Check cache validity
    if gdb_buffer_cache.buffer and (now - gdb_buffer_cache.last_check) < gdb_buffer_cache.cache_duration then
        -- Verify buffer still exists and is valid
        if vim.api.nvim_buf_is_valid(gdb_buffer_cache.buffer) then
            local name = vim.api.nvim_buf_get_name(gdb_buffer_cache.buffer)
            if name:match("gdb") then
                return gdb_buffer_cache.buffer
            end
        end
    end
    
    -- Search for GDB buffer
    local buffers = vim.api.nvim_list_bufs()
    for _, buf in ipairs(buffers) do
        if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
            local name = vim.api.nvim_buf_get_name(buf)
            if name:match("gdb") or name:match("debugger") then
                -- Update cache
                gdb_buffer_cache.buffer = buf
                gdb_buffer_cache.last_check = now
                return buf
            end
        end
    end
    
    -- Clear cache if buffer not found
    gdb_buffer_cache.buffer = nil
    return nil
end

---Invalidate the GDB buffer cache
function M.invalidate_cache()
    gdb_buffer_cache.buffer = nil
    gdb_buffer_cache.last_check = 0
end

---Parse breakpoint information from GDB output
---@param lines string[] GDB output lines
---@return BreakpointInfo[] breakpoints
function M.parse_breakpoints(lines)
    local breakpoints = {}
    
    for _, line in ipairs(lines) do
        -- Parse GDB breakpoint format:
        -- Num     Type           Disp Enb Address            What
        -- 1       breakpoint     keep y   0x0000000000001234 in main at test.c:10
        -- 2       breakpoint     keep n   main.c:15
        
        -- First try with "at" prefix
        local num, file, line_num = line:match("^(%d+)%s+breakpoint.+at%s+([^:]+):(%d+)")
        
        -- If that fails, try without "at" (direct file:line format)
        if not num then
            num, file, line_num = line:match("^(%d+)%s+breakpoint.+%s+([^%s:]+):(%d+)")
        end
        
        if num and file and line_num then
            local enabled = line:match("keep%s+y") ~= nil
            table.insert(breakpoints, {
                num = tonumber(num),
                file = file,
                line = tonumber(line_num),
                enabled = enabled,
            })
        end
    end
    
    return breakpoints
end

---Find a breakpoint at a specific file and line
---@param breakpoints BreakpointInfo[] List of breakpoints
---@param file string File path
---@param line number Line number
---@return number|nil Breakpoint number or nil
function M.find_breakpoint(breakpoints, file, line)
    for _, bp in ipairs(breakpoints) do
        if bp.file == file and bp.line == line then
            return bp.num
        end
        -- Also check if file ends with the breakpoint file (relative path matching)
        if file:match(bp.file .. "$") and bp.line == line then
            return bp.num
        end
    end
    return nil
end

---Extract value from GDB print output
---@param lines string[] Output lines from GDB
---@return string|nil value The extracted value or nil
function M.extract_value(lines)
    if not lines or #lines == 0 then
        return nil
    end
    
    -- Join all lines
    local text = table.concat(lines, "\n")
    
    -- Skip empty or prompt-only responses
    if text:match("^%s*%(gdb%)%s*$") or text:match("^%s*$") then
        return nil
    end
    
    -- Common GDB output patterns
    -- $1 = value
    local value = text:match("%$%d+%s*=%s*(.+)")
    if value then
        return vim.trim(value)
    end
    
    -- Don't return raw text if it's just a prompt
    if text == "(gdb)" or text:match("^%(gdb%)%s") then
        return nil
    end
    
    -- Direct value output (but not empty)
    value = text:match("^%s*(.+)%s*$")
    if value and value ~= "" and value ~= "(gdb)" then
        return value
    end
    
    return nil
end

return M