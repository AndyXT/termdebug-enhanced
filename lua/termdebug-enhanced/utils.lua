---@class GdbBufferCache
---@field buffer number|nil Cached buffer number
---@field last_check number Last check timestamp
---@field cache_duration number Cache duration in milliseconds

---@class BreakpointInfo
---@field num number Breakpoint number
---@field file string File path
---@field line number Line number
---@field enabled boolean Whether breakpoint is enabled

---@class AsyncOptions
---@field timeout number|nil Timeout in milliseconds
---@field poll_interval number|nil Polling interval in milliseconds
---@field max_lines number|nil Maximum lines to read

---@class termdebug-enhanced.utils
---@field gdb_buffer_cache GdbBufferCache Cache for GDB buffer lookup
local M = {}

-- Cache for GDB buffer to improve performance
---@type GdbBufferCache
local gdb_buffer_cache = {
  buffer = nil,
  last_check = 0,
  cache_duration = 1000 -- Cache for 1 second
}

---Find the GDB buffer with caching
---@return number|nil bufnr The GDB buffer number or nil if not found
function M.find_gdb_buffer()
  local now = vim.loop.hrtime() / 1000000 -- Convert to milliseconds

  -- Check cache validity
  if gdb_buffer_cache.buffer and
     (now - gdb_buffer_cache.last_check) < gdb_buffer_cache.cache_duration then
    -- Verify buffer still exists and is valid
    if vim.api.nvim_buf_is_valid(gdb_buffer_cache.buffer) then
      return gdb_buffer_cache.buffer
    end
  end

  -- Search for GDB buffer
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if name:match("gdb") or name:match("debugger") or name:match("Termdebug") then
        -- Cache the result
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
---@return nil
function M.invalidate_gdb_cache()
  gdb_buffer_cache.buffer = nil
  gdb_buffer_cache.last_check = 0
end

---Async GDB response handler with timer-based polling
---@param command string The GDB command to send
---@param callback fun(response: string[]|nil, error: string|nil): nil Callback function(response, error)
---@param opts AsyncOptions|nil Options: timeout (ms), poll_interval (ms), max_lines
---@return nil
function M.async_gdb_response(command, callback, opts)
  opts = opts or {}
  local timeout = opts.timeout or 3000
  local poll_interval = opts.poll_interval or 50
  local max_lines = opts.max_lines or 50

  -- Check if we can send the command
  if vim.fn.exists(':Termdebug') == 0 then
    callback(nil, "Termdebug not available")
    return
  end

  if not vim.g.termdebug_running then
    callback(nil, "Debug session not active")
    return
  end

  -- Send the command
  local ok, err = pcall(vim.fn.TermDebugSendCommand, command)
  if not ok then
    callback(nil, "Failed to send command: " .. tostring(err))
    return
  end

  -- Set up timer for polling
  local timer = vim.loop.new_timer()
  local start_time = vim.loop.hrtime()
  local command_pattern = vim.pesc(command)

  timer:start(poll_interval, poll_interval, function()
    local elapsed = (vim.loop.hrtime() - start_time) / 1000000 -- to ms

    -- Check for timeout
    if elapsed > timeout then
      timer:stop()
      timer:close()
      vim.schedule(function()
        callback(nil, "Timeout waiting for GDB response")
      end)
      return
    end

    -- Try to find response in GDB buffer
    vim.schedule(function()
      local gdb_buf = M.find_gdb_buffer()
      if not gdb_buf then
        return -- Keep polling
      end

      -- Get buffer lines
      local lines = vim.api.nvim_buf_get_lines(gdb_buf, -max_lines, -1, false)
      local result = {}
      local capture = false
      local found_response = false

      -- Process lines from bottom to top
      for i = #lines, 1, -1 do
        local line = lines[i]

        -- Check for end of response (gdb prompt)
        if line:match("^%(gdb%)") and capture then
          found_response = true
          break
        -- Check for our command
        elseif command_pattern and line:match(command_pattern) then
          capture = true
        -- Capture response lines
        elseif capture and not line:match("^%(gdb%)") then
          table.insert(result, 1, line)
        end
      end

      -- If we found a complete response, stop timer and callback
      if found_response and #result > 0 then
        timer:stop()
        timer:close()
        callback(result, nil)
      elseif found_response and #result == 0 then
        -- Empty response but command was processed
        timer:stop()
        timer:close()
        callback({"No output"}, nil)
      end
      -- Otherwise keep polling
    end)
  end)
end

---Parse breakpoint info from GDB output
---@param lines string[] Array of output lines from "info breakpoints"
---@return BreakpointInfo[] breakpoints Table of breakpoint info {num, file, line, enabled}
function M.parse_breakpoints(lines)
  local breakpoints = {}

  for _, line in ipairs(lines) do
    -- Parse breakpoint lines like:
    -- "1       breakpoint     keep y   0x00001234 in main at main.c:42"
    -- "2       breakpoint     keep n   main.c:15"
    local num, enabled, location = line:match("^(%d+)%s+breakpoint%s+%w+%s+([yn])%s+(.+)")
    if num and enabled and location then
      -- Extract file and line from location
      local file, line_num = location:match("([^%s:]+):(%d+)$")
      if not file then
        -- Try alternate format with "at" - look for "at file:line"
        file, line_num = location:match("at%s+([^%s:]+):(%d+)$")
      end
      if not file then
        -- Try format with "in function at file:line"
        file, line_num = location:match("in%s+%w+%s+at%s+([^%s:]+):(%d+)$")
      end

      if file and line_num then
        table.insert(breakpoints, {
          num = tonumber(num),
          file = file,
          line = tonumber(line_num),
          enabled = enabled == "y"
        })
      end
    end
  end

  return breakpoints
end

---Check if breakpoint exists at file:line
---@param breakpoints BreakpointInfo[] Array of breakpoint info
---@param file string File path
---@param line number Line number
---@return number|nil Breakpoint number if exists, nil otherwise
function M.find_breakpoint(breakpoints, file, line)
  -- Normalize file path for comparison
  local normalized_file = vim.fn.fnamemodify(file, ":p")

  for _, bp in ipairs(breakpoints) do
    local bp_file = vim.fn.fnamemodify(bp.file, ":p")
    if bp_file == normalized_file and bp.line == line then
      return bp.num
    end
  end

  return nil
end

---Create a debounced function
---@param func function The function to debounce
---@param delay number Delay in milliseconds
---@return function Debounced function
function M.debounce(func, delay)
  local timer = nil

  return function(...)
    local args = {...}

    if timer then
      timer:stop()
      timer:close()
    end

    timer = vim.loop.new_timer()
    timer:start(delay, 0, function()
      timer:close()
      vim.schedule(function()
        func(table.unpack(args))
      end)
    end)
  end
end

---Extract variable value from GDB print output
---@param lines string[] Array of output lines
---@return string|nil value The extracted value or nil
function M.extract_value(lines)
  if not lines or #lines == 0 then
    return nil
  end

  -- Join lines and look for value patterns
  local text = table.concat(lines, " ")

  -- Common patterns:
  -- $1 = 42
  -- $2 = 0x1234
  -- $3 = "hello"
  -- $4 = {x = 1, y = 2}
  local value = text:match("%$%d+%s*=%s*(.+)")
  if value then
    return vim.trim(value)
  end

  -- Direct value without $n prefix
  local direct = text:match("^%s*(.+)%s*$")
  if direct and not direct:match("^%(gdb%)") then
    return direct
  end

  return nil
end

return M