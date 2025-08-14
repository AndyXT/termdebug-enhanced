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

---@class GdbUtilsError
---@field type string Error type (timeout, command_failed, not_available, invalid_input)
---@field message string Human-readable error message
---@field command string|nil The GDB command that failed
---@field details string|nil Additional error details

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

-- Validate GDB command input
---@param command string Command to validate
---@return boolean valid, string|nil error_msg
local function validate_gdb_command(command)
  if not command or command == "" then
    return false, "Empty GDB command"
  end
  
  local trimmed = vim.trim(command)
  if trimmed == "" then
    return false, "GDB command contains only whitespace"
  end
  
  -- Check for obviously dangerous commands (basic safety)
  local dangerous_patterns = {
    "^%s*quit%s*$",
    "^%s*exit%s*$",
    "^%s*shell%s+",
    "^%s*!%s*"
  }
  
  for _, pattern in ipairs(dangerous_patterns) do
    if trimmed:lower():match(pattern) then
      return false, "Potentially dangerous GDB command blocked: " .. trimmed
    end
  end
  
  return true, nil
end

---Find the GDB buffer with caching and error handling
---@return number|nil bufnr The GDB buffer number or nil if not found
function M.find_gdb_buffer()
  local now_ok, now = pcall(function()
    return vim.loop.hrtime() / 1000000 -- Convert to milliseconds
  end)
  
  if not now_ok then
    -- Fallback without caching if hrtime fails
    now = 0
  end

  -- Check cache validity
  if gdb_buffer_cache.buffer and now > 0 and
     (now - gdb_buffer_cache.last_check) < gdb_buffer_cache.cache_duration then
    -- Verify buffer still exists and is valid
    local valid_ok, is_valid = pcall(vim.api.nvim_buf_is_valid, gdb_buffer_cache.buffer)
    if valid_ok and is_valid then
      return gdb_buffer_cache.buffer
    end
  end

  -- Search for GDB buffer with error handling
  local list_ok, buf_list = pcall(vim.api.nvim_list_bufs)
  if not list_ok then
    -- Clear cache and return nil if we can't list buffers
    gdb_buffer_cache.buffer = nil
    return nil
  end

  for _, buf in ipairs(buf_list) do
    local valid_ok, is_valid = pcall(vim.api.nvim_buf_is_valid, buf)
    if valid_ok and is_valid then
      local name_ok, name = pcall(vim.api.nvim_buf_get_name, buf)
      if name_ok and name then
        if name:match("gdb") or name:match("debugger") or name:match("Termdebug") then
          -- Cache the result
          gdb_buffer_cache.buffer = buf
          gdb_buffer_cache.last_check = now
          return buf
        end
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

---Async GDB response handler with timer-based polling and comprehensive error handling
---@param command string The GDB command to send
---@param callback fun(response: string[]|nil, error: string|nil): nil Callback function(response, error)
---@param opts AsyncOptions|nil Options: timeout (ms), poll_interval (ms), max_lines
---@return nil
function M.async_gdb_response(command, callback, opts)
  opts = opts or {}
  local timeout = opts.timeout or 3000
  local poll_interval = math.max(opts.poll_interval or 50, 10) -- Minimum 10ms
  local max_lines = math.max(opts.max_lines or 50, 10) -- Minimum 10 lines

  -- Validate input
  local valid, validation_error = validate_gdb_command(command)
  if not valid then
    vim.schedule(function()
      callback(nil, validation_error)
    end)
    return
  end

  -- Check if we can send the command
  if vim.fn.exists(':Termdebug') == 0 then
    vim.schedule(function()
      callback(nil, "Termdebug not available. Run :packadd termdebug")
    end)
    return
  end

  if not vim.g.termdebug_running then
    vim.schedule(function()
      callback(nil, "Debug session not active. Start debugging first")
    end)
    return
  end

  -- Send the command with error handling
  local send_ok, send_err = pcall(vim.fn.TermDebugSendCommand, command)
  if not send_ok then
    vim.schedule(function()
      callback(nil, "Failed to send GDB command: " .. tostring(send_err))
    end)
    return
  end

  -- Set up timer for polling with error handling
  local timer_ok, timer = pcall(vim.loop.new_timer)
  if not timer_ok then
    vim.schedule(function()
      callback(nil, "Failed to create response timer: " .. tostring(timer))
    end)
    return
  end

  local start_time_ok, start_time = pcall(vim.loop.hrtime)
  if not start_time_ok then
    timer:close()
    vim.schedule(function()
      callback(nil, "Failed to get start time for timeout calculation")
    end)
    return
  end

  local command_pattern_ok, command_pattern = pcall(vim.pesc, command)
  if not command_pattern_ok then
    -- Fallback to simple string matching if pattern escaping fails
    command_pattern = command
  end

  local timer_start_ok, timer_start_err = pcall(timer.start, timer, poll_interval, poll_interval, function()
    local elapsed_ok, elapsed = pcall(function()
      return (vim.loop.hrtime() - start_time) / 1000000 -- to ms
    end)

    -- Check for timeout
    if elapsed_ok and elapsed > timeout then
      timer:stop()
      timer:close()
      vim.schedule(function()
        callback(nil, "Timeout waiting for GDB response after " .. timeout .. "ms")
      end)
      return
    elseif not elapsed_ok then
      -- If we can't calculate elapsed time, assume timeout to be safe
      timer:stop()
      timer:close()
      vim.schedule(function()
        callback(nil, "Timer error: cannot calculate elapsed time")
      end)
      return
    end

    -- Try to find response in GDB buffer
    vim.schedule(function()
      local gdb_buf = M.find_gdb_buffer()
      if not gdb_buf then
        return -- Keep polling
      end

      -- Get buffer lines with error handling
      local lines_ok, lines = pcall(vim.api.nvim_buf_get_lines, gdb_buf, -max_lines, -1, false)
      if not lines_ok then
        return -- Keep polling, buffer might be temporarily unavailable
      end

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
      if found_response then
        timer:stop()
        timer:close()
        if #result > 0 then
          callback(result, nil)
        else
          -- Empty response but command was processed
          callback({}, nil)
        end
      end
      -- Otherwise keep polling
    end)
  end)

  if not timer_start_ok then
    timer:close()
    vim.schedule(function()
      callback(nil, "Failed to start response timer: " .. tostring(timer_start_err))
    end)
    return
  end
end

---Parse breakpoint info from GDB output with error handling
---@param lines string[]|nil Array of output lines from "info breakpoints"
---@return BreakpointInfo[] breakpoints Table of breakpoint info {num, file, line, enabled}
function M.parse_breakpoints(lines)
  local breakpoints = {}

  if not lines or type(lines) ~= "table" then
    return breakpoints
  end

  for _, line in ipairs(lines) do
    if type(line) == "string" and line ~= "" then
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
          local num_val = tonumber(num)
          local line_val = tonumber(line_num)
          
          if num_val and line_val then
            table.insert(breakpoints, {
              num = num_val,
              file = file,
              line = line_val,
              enabled = enabled == "y"
            })
          end
        end
      end
    end
  end

  return breakpoints
end

---Check if breakpoint exists at file:line with error handling
---@param breakpoints BreakpointInfo[]|nil Array of breakpoint info
---@param file string|nil File path
---@param line number|nil Line number
---@return number|nil Breakpoint number if exists, nil otherwise
function M.find_breakpoint(breakpoints, file, line)
  if not breakpoints or type(breakpoints) ~= "table" or 
     not file or type(file) ~= "string" or file == "" or
     not line or type(line) ~= "number" then
    return nil
  end

  -- Normalize file path for comparison with error handling
  local normalize_ok, normalized_file = pcall(vim.fn.fnamemodify, file, ":p")
  if not normalize_ok then
    -- Fallback to original file path if normalization fails
    normalized_file = file
  end

  for _, bp in ipairs(breakpoints) do
    if bp and bp.file and bp.line then
      local bp_normalize_ok, bp_file = pcall(vim.fn.fnamemodify, bp.file, ":p")
      if not bp_normalize_ok then
        bp_file = bp.file
      end
      
      if bp_file == normalized_file and bp.line == line then
        return bp.num
      end
    end
  end

  return nil
end

---Create a debounced function with error handling
---@param func function The function to debounce
---@param delay number Delay in milliseconds
---@return function Debounced function
function M.debounce(func, delay)
  if type(func) ~= "function" then
    error("First argument must be a function")
  end
  
  if type(delay) ~= "number" or delay < 0 then
    error("Delay must be a non-negative number")
  end
  
  local timer = nil

  return function(...)
    local args = {...}

    -- Clean up existing timer
    if timer then
      local stop_ok = pcall(timer.stop, timer)
      local close_ok = pcall(timer.close, timer)
      if not stop_ok or not close_ok then
        -- Timer cleanup failed, but continue with new timer
      end
    end

    -- Create new timer with error handling
    local timer_ok, new_timer = pcall(vim.loop.new_timer)
    if not timer_ok then
      -- Fallback: execute function immediately if timer creation fails
      vim.schedule(function()
        local exec_ok, exec_err = pcall(func, unpack(args))
        if not exec_ok then
          vim.notify("Debounced function failed: " .. tostring(exec_err), vim.log.levels.ERROR)
        end
      end)
      return
    end
    
    timer = new_timer
    
    local start_ok, start_err = pcall(timer.start, timer, delay, 0, function()
      local close_ok = pcall(timer.close, timer)
      if not close_ok then
        -- Timer close failed, but continue with function execution
      end
      
      vim.schedule(function()
        local exec_ok, exec_err = pcall(func, unpack(args))
        if not exec_ok then
          vim.notify("Debounced function failed: " .. tostring(exec_err), vim.log.levels.ERROR)
        end
      end)
    end)
    
    if not start_ok then
      -- Timer start failed, execute immediately
      pcall(timer.close, timer)
      vim.schedule(function()
        local exec_ok, exec_err = pcall(func, unpack(args))
        if not exec_ok then
          vim.notify("Debounced function failed: " .. tostring(exec_err), vim.log.levels.ERROR)
        end
      end)
    end
  end
end

---Extract variable value from GDB print output with error handling
---@param lines string[]|nil Array of output lines
---@return string|nil value The extracted value or nil
function M.extract_value(lines)
  if not lines or type(lines) ~= "table" or #lines == 0 then
    return nil
  end

  -- Validate that all lines are strings
  for _, line in ipairs(lines) do
    if type(line) ~= "string" then
      return nil
    end
  end

  -- Join lines and look for value patterns with error handling
  local join_ok, text = pcall(table.concat, lines, " ")
  if not join_ok then
    return nil
  end

  -- Common patterns:
  -- $1 = 42
  -- $2 = 0x1234
  -- $3 = "hello"
  -- $4 = {x = 1, y = 2}
  local match_ok, value = pcall(string.match, text, "%$%d+%s*=%s*(.+)")
  if match_ok and value then
    local trim_ok, trimmed = pcall(vim.trim, value)
    return trim_ok and trimmed or value
  end

  -- Direct value without $n prefix
  local direct_ok, direct = pcall(string.match, text, "^%s*(.+)%s*$")
  if direct_ok and direct and not direct:match("^%(gdb%)") then
    return direct
  end

  return nil
end

return M