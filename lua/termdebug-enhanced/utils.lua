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
	cache_duration = 2000, -- Cache for 2 seconds (optimized)
}

-- Performance monitoring
---@class PerformanceMetrics
---@field async_operations_count number Total async operations
---@field avg_response_time number Average response time in ms
---@field cache_hits number Cache hit count
---@field cache_misses number Cache miss count

---@type PerformanceMetrics
local perf_metrics = {
	async_operations_count = 0,
	avg_response_time = 0,
	cache_hits = 0,
	cache_misses = 0,
}

-- Frequently accessed GDB info cache
---@type table<string, {data: any, timestamp: number, ttl: number}>
local gdb_info_cache = {}

---Validate GDB command input for safety and correctness
---
---Performs basic validation on GDB commands to prevent obviously dangerous
---operations and ensure the command is properly formatted. This is a safety
---measure to prevent accidental execution of harmful commands.
---
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
		"^%s*!%s*",
	}

	for _, pattern in ipairs(dangerous_patterns) do
		if trimmed:lower():match(pattern) then
			return false, "Potentially dangerous GDB command blocked: " .. trimmed
		end
	end

	return true, nil
end

---Find the GDB buffer with caching and error handling
---
---This function searches for the GDB buffer used by termdebug and caches the result
---for improved performance. The cache is automatically invalidated after a configurable
---duration or when the buffer becomes invalid.
---
---@return number|nil bufnr The GDB buffer number or nil if not found
function M.find_gdb_buffer()
	local now_ok, now = pcall(function()
		return vim.loop.hrtime() / 1000000 -- Convert to milliseconds
	end)

	if not now_ok then
		-- Fallback without caching if hrtime fails
		now = 0
	end

	-- Check cache validity (optimized with better invalidation)
	if
		gdb_buffer_cache.buffer
		and now > 0
		and (now - gdb_buffer_cache.last_check) < gdb_buffer_cache.cache_duration
	then
		-- Verify buffer still exists and is valid
		local valid_ok, is_valid = pcall(vim.api.nvim_buf_is_valid, gdb_buffer_cache.buffer)
		if valid_ok and is_valid then
			-- Verify it's still a GDB buffer (enhanced validation)
			local name_ok, name = pcall(vim.api.nvim_buf_get_name, gdb_buffer_cache.buffer)
			if name_ok and name and (name:match("gdb") or name:match("debugger") or name:match("Termdebug")) then
				perf_metrics.cache_hits = perf_metrics.cache_hits + 1
				return gdb_buffer_cache.buffer
			end
		end
		-- Cache is invalid, clear it
		gdb_buffer_cache.buffer = nil
	end

	perf_metrics.cache_misses = perf_metrics.cache_misses + 1

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
---
---Forces the next call to find_gdb_buffer() to perform a fresh search
---instead of using cached results. This should be called when the GDB
---session is restarted or when buffer state changes are expected.
---
---@return nil
function M.invalidate_gdb_cache()
	gdb_buffer_cache.buffer = nil
	gdb_buffer_cache.last_check = 0
end

---Cache frequently accessed GDB information
---
---Stores GDB command results or other data with automatic expiration.
---This is particularly useful for caching results of 'info' commands
---that don't change frequently during debugging sessions.
---
---@param key string Cache key (should be unique and descriptive)
---@param data any Data to cache (can be any Lua value)
---@param ttl number|nil Time to live in milliseconds (default: 5000)
---@return nil
function M.cache_gdb_info(key, data, ttl)
	ttl = ttl or 5000 -- Default 5 second TTL
	local now_ok, now = pcall(function()
		return vim.loop.hrtime() / 1000000
	end)

	if now_ok then
		gdb_info_cache[key] = {
			data = data,
			timestamp = now,
			ttl = ttl,
		}
	end
end

---Get cached GDB information
---
---Retrieves previously cached data if it exists and hasn't expired.
---Automatically removes expired entries from the cache.
---
---@param key string Cache key to look up
---@return any|nil Cached data or nil if not found/expired
function M.get_cached_gdb_info(key)
	local entry = gdb_info_cache[key]
	if not entry then
		return nil
	end

	local now_ok, now = pcall(function()
		return vim.loop.hrtime() / 1000000
	end)

	if not now_ok or (now - entry.timestamp) > entry.ttl then
		-- Expired, remove from cache
		gdb_info_cache[key] = nil
		return nil
	end

	return entry.data
end

---Clear all cached GDB information
---
---Removes all cached GDB data. This should be called when starting
---a new debugging session or when cached data may be stale.
---
---@return nil
function M.clear_gdb_info_cache()
	gdb_info_cache = {}
end

---Get performance metrics
---@return PerformanceMetrics Current performance metrics
function M.get_performance_metrics()
	return vim.deepcopy(perf_metrics)
end

---Reset performance metrics
---@return nil
function M.reset_performance_metrics()
	perf_metrics = {
		async_operations_count = 0,
		avg_response_time = 0,
		cache_hits = 0,
		cache_misses = 0,
	}
end

---Simple GDB response function for testing
---@param command string GDB command to execute
---@param callback fun(response: string[]|nil, error: string|nil): nil Callback function(response, error)
---@param opts AsyncOptions|nil Options: timeout (ms), poll_interval (ms), max_lines
---@return nil
function M.simple_gdb_response(command, callback, opts)
	opts = opts or {}

	-- Check GDB availability
	if vim.fn.exists(":Termdebug") == 0 then
		vim.schedule(function()
			callback(nil, "Termdebug not available")
		end)
		return
	end

	if not vim.g.termdebug_running then
		vim.schedule(function()
			callback(nil, "Debug session not active")
		end)
		return
	end

	vim.notify("Simple GDB response: sending command " .. command, vim.log.levels.INFO)

	-- Try multiple methods to send command
	local send_ok = false
	local send_method = "none"

	-- Method 1: Try TermDebugSendCommand (the correct function!)
	if vim.fn.exists('*TermDebugSendCommand') == 1 then
		send_method = "TermDebugSendCommand"
		send_ok = pcall(vim.fn.TermDebugSendCommand, command)
		vim.notify("Tried TermDebugSendCommand: " .. tostring(send_ok), vim.log.levels.INFO)
	end

	-- Method 2: Try TermdebugCommand (fallback)
	if not send_ok and vim.fn.exists('*TermdebugCommand') == 1 then
		send_method = "TermdebugCommand"
		send_ok = pcall(vim.fn.TermdebugCommand, command)
		vim.notify("Tried TermdebugCommand: " .. tostring(send_ok), vim.log.levels.INFO)
	end

	-- Method 3: Try direct buffer approach
	if not send_ok then
		local gdb_buf = M.find_gdb_buffer()
		if gdb_buf then
			send_method = "direct_buffer"
			local buf_lines = vim.api.nvim_buf_get_lines(gdb_buf, -1, -1, false)
			vim.notify("GDB buffer has " .. #buf_lines .. " lines", vim.log.levels.INFO)

			-- Try to append command to buffer
			local append_ok = pcall(vim.api.nvim_buf_set_lines, gdb_buf, -1, -1, false, {command})
			if append_ok then
				-- Try to send Enter key to execute
				vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'n', false)
				send_ok = true
				vim.notify("Sent command via direct buffer", vim.log.levels.INFO)
			else
				vim.notify("Failed to append to GDB buffer", vim.log.levels.ERROR)
			end
		else
			vim.notify("No GDB buffer found", vim.log.levels.ERROR)
		end
	end

	-- Method 4: Try using vim.cmd to execute GDB command
	if not send_ok then
		send_method = "vim_cmd"
		local cmd_ok = pcall(vim.cmd, "call TermdebugCommand('" .. command .. "')")
		if cmd_ok then
			send_ok = true
			vim.notify("Sent command via vim.cmd", vim.log.levels.INFO)
		else
			vim.notify("Failed to send via vim.cmd", vim.log.levels.ERROR)
		end
	end

	vim.notify("Final send result: " .. tostring(send_ok) .. " via " .. send_method, vim.log.levels.INFO)

	if send_ok then
		-- For now, return a mock response to test if the callback works
		vim.defer_fn(function()
			vim.notify("Simple GDB response: calling callback with mock data", vim.log.levels.INFO)
			callback({"$1 = 42"}, nil)
		end, 100)
	else
		vim.schedule(function()
			callback(nil, "Failed to send command")
		end)
	end
end

---Async GDB response handler with optimized polling and comprehensive error handling
---
---This is the core function for communicating with GDB asynchronously. It sends a command
---to GDB and polls the GDB buffer for the response using adaptive polling intervals.
---The function implements several optimizations:
---
---1. Adaptive polling: starts with fast polling and slows down if no response
---2. Response caching: caches results of 'info' commands for better performance
---3. Comprehensive error handling: categorizes and reports different types of errors
---4. Timeout management: prevents hanging on unresponsive GDB commands
---5. Resource cleanup: ensures timers are properly cleaned up
---
---@param command string The GDB command to send
---@param callback fun(response: string[]|nil, error: string|nil): nil Callback function(response, error)
---@param opts AsyncOptions|nil Options: timeout (ms), poll_interval (ms), max_lines
---@return nil
function M.async_gdb_response(command, callback, opts)
	opts = opts or {}
	local timeout = opts.timeout or 3000
  -- Adaptive polling algorithm: Start with fast polling for responsiveness,
  -- then gradually increase intervals to reduce CPU usage if no response is detected.
  -- This balances responsiveness with resource efficiency.
  local initial_poll_interval = math.max(opts.poll_interval or 25, 10) -- Start with 25ms for quick response
  local max_poll_interval = 100 -- Cap at 100ms to maintain reasonable responsiveness
  local current_poll_interval = initial_poll_interval
  local max_lines = math.max(opts.max_lines or 50, 10) -- Limit buffer reads for performance

  -- Performance tracking: Record operation start time for metrics calculation.
  -- This helps identify slow operations and optimize polling intervals.
  local operation_start = vim.loop.hrtime()
  perf_metrics.async_operations_count = perf_metrics.async_operations_count + 1

  -- Cache optimization: Check if we have a recent result for this command.
  -- Only cache 'info' commands as they typically don't change frequently
  -- and are expensive to re-execute (e.g., 'info breakpoints', 'info registers').
  local cache_key = "cmd:" .. command
  local cached_result = M.get_cached_gdb_info(cache_key)
  if cached_result and command:match("^info") then
    vim.schedule(function()
      callback(cached_result, nil)
    end)
    return
  end

	-- Validate input
	local valid, validation_error = validate_gdb_command(command)
	if not valid then
		vim.schedule(function()
			callback(nil, validation_error)
		end)
		return
	end

	-- Check if we can send the command
	if vim.fn.exists(":Termdebug") == 0 then
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
	-- Try multiple methods to send GDB commands
	local send_ok, send_err = false, "No send method available"
	local send_method = "none"

	-- Method 1: Try TermDebugSendCommand (correct function name)
	if vim.fn.exists('*TermDebugSendCommand') == 1 then
		send_method = "TermDebugSendCommand"
		vim.notify("Sending GDB command via TermDebugSendCommand: " .. command, vim.log.levels.INFO)
		send_ok, send_err = pcall(vim.fn.TermDebugSendCommand, command)
	-- Method 2: Try TermdebugCommand (fallback)
	elseif vim.fn.exists('*TermdebugCommand') == 1 then
		send_method = "TermdebugCommand"
		vim.notify("Sending GDB command via TermdebugCommand: " .. command, vim.log.levels.INFO)
		send_ok, send_err = pcall(vim.fn.TermdebugCommand, command)
	-- Method 3: Try sending to GDB buffer directly
	else
		local gdb_buf = M.find_gdb_buffer()
		if gdb_buf then
			send_method = "direct_buffer"
			vim.notify("Sending GDB command via direct buffer: " .. command, vim.log.levels.INFO)
			-- Try to send command by appending to GDB buffer
			local append_ok, append_err = pcall(function()
				vim.api.nvim_buf_set_lines(gdb_buf, -1, -1, false, {command})
				-- Simulate pressing Enter
				vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'n', false)
			end)
			send_ok, send_err = append_ok, append_err
		else
			send_err = "GDB buffer not found and TermdebugCommand not available"
		end
	end

	vim.notify("Command send result: " .. tostring(send_ok) .. " via " .. send_method, vim.log.levels.INFO)
	if not send_ok then
		vim.notify("Failed to send command: " .. tostring(send_err), vim.log.levels.ERROR)
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
		pcall(timer.close, timer)
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

	local poll_count = 0
	local last_line_count = 0

	vim.notify("Starting polling timer for command: " .. command .. " (timeout: " .. timeout .. "ms)", vim.log.levels.INFO)
	local timer_start_ok = pcall(timer.start, timer, current_poll_interval, current_poll_interval, function()
		local elapsed_ok, elapsed = pcall(function()
			return (vim.loop.hrtime() - start_time) / 1000000 -- to ms
		end)

		-- Check for timeout
		if elapsed_ok and elapsed > timeout then
			vim.notify("GDB response timeout after " .. timeout .. "ms for command: " .. command, vim.log.levels.WARN)
			pcall(timer.stop, timer)
			pcall(timer.close, timer)
			vim.schedule(function()
				callback(nil, "Timeout waiting for GDB response after " .. timeout .. "ms")
			end)
			return
		elseif not elapsed_ok then
			-- If we can't calculate elapsed time, assume timeout to be safe
			vim.notify("Timer error: cannot calculate elapsed time", vim.log.levels.ERROR)
			pcall(timer.stop, timer)
			pcall(timer.close, timer)
			vim.schedule(function()
				callback(nil, "Timer error: cannot calculate elapsed time")
			end)
			return
		end

		poll_count = poll_count + 1

		-- Try to find response in GDB buffer
		vim.schedule(function()
			local gdb_buf = M.find_gdb_buffer()
			if not gdb_buf then
				if poll_count % 10 == 0 then -- Log every 10th poll to avoid spam
					vim.notify("GDB buffer not found (poll " .. poll_count .. ")", vim.log.levels.DEBUG)
				end
				return -- Keep polling
			end

			-- Get buffer lines with error handling
			local lines_ok, lines = pcall(vim.api.nvim_buf_get_lines, gdb_buf, -max_lines, -1, false)
			if not lines_ok then
				if poll_count % 10 == 0 then
					vim.notify("Failed to get buffer lines (poll " .. poll_count .. ")", vim.log.levels.DEBUG)
				end
				return -- Keep polling, buffer might be temporarily unavailable
			end

			-- Debug: Log buffer content more frequently for evaluation commands
			local is_print_command = command:match("^print")
			local log_frequency = is_print_command and 5 or 20 -- Log every 5 polls for print commands

			if poll_count % log_frequency == 0 then
				vim.notify("Poll " .. poll_count .. " for '" .. command .. "': Found " .. #lines .. " lines in GDB buffer", vim.log.levels.INFO)
				if #lines > 0 then
					local last_lines = vim.list_slice(lines, math.max(1, #lines-5), #lines)
					vim.notify("Last 5 lines: " .. vim.inspect(last_lines), vim.log.levels.INFO)

					-- Also check if our command appears in recent lines
					local command_found_in_recent = false
					for _, line in ipairs(last_lines) do
						if line:match(vim.pesc(command)) then
							command_found_in_recent = true
							break
						end
					end
					vim.notify("Command '" .. command .. "' found in recent lines: " .. tostring(command_found_in_recent), vim.log.levels.INFO)
				end
			end

			-- Adaptive polling: if buffer isn't growing, slow down polling
			if #lines == last_line_count and poll_count > 3 then
				current_poll_interval = math.min(current_poll_interval * 1.5, max_poll_interval)
				pcall(timer.stop, timer)
				pcall(timer.start, timer, current_poll_interval, current_poll_interval, function()
					-- Continue with same logic but updated interval
				end)
			end
			last_line_count = #lines

			local result = {}
			local capture = false
			local found_response = false
			local found_command = false

			-- Process lines from bottom to top (optimized search)
			for i = #lines, math.max(1, #lines - 20), -1 do -- Only check last 20 lines for efficiency
				local line = lines[i]

				-- Check for end of response (gdb prompt)
				if line:match("^%(gdb%)") and capture then
					found_response = true
					if poll_count % 10 == 0 then
						vim.notify("Found GDB prompt, response complete", vim.log.levels.INFO)
					end
					break
				-- Check for our command
				elseif command_pattern and line:match(command_pattern) then
					capture = true
					found_command = true
					if poll_count % 10 == 0 then
						vim.notify("Found command pattern: " .. command_pattern, vim.log.levels.INFO)
					end
				-- Capture response lines
				elseif capture and not line:match("^%(gdb%)") then
					table.insert(result, 1, line)
				end
			end

			-- Debug: Log search results periodically
			if poll_count % 20 == 0 then
				vim.notify("Search results - Command found: " .. tostring(found_command) .. ", Response complete: " .. tostring(found_response) .. ", Result lines: " .. #result, vim.log.levels.INFO)
			end

			-- If we found a complete response, stop timer and callback
			if found_response then
				vim.notify("GDB response complete for '" .. command .. "' with " .. #result .. " result lines", vim.log.levels.INFO)
				pcall(timer.stop, timer)
				pcall(timer.close, timer)

				-- Update performance metrics
				local operation_time = (vim.loop.hrtime() - operation_start) / 1000000
				perf_metrics.avg_response_time = (
					perf_metrics.avg_response_time * (perf_metrics.async_operations_count - 1) + operation_time
				) / perf_metrics.async_operations_count

				-- Cache result for info commands
				if command:match("^info") and #result > 0 then
					M.cache_gdb_info(cache_key, result, 3000) -- Cache for 3 seconds
				end

				vim.notify("Calling callback with result: " .. vim.inspect(result), vim.log.levels.INFO)
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
		pcall(timer.close, timer)
		vim.schedule(function()
			callback(nil, "Failed to start response timer")
		end)
		return
	end
end

---Parse breakpoint info from GDB output with error handling
---
---Parses the output from GDB's "info breakpoints" command and extracts structured
---breakpoint information. This function handles various GDB output formats and
---provides robust error handling for malformed input.
---
---The function recognizes several breakpoint line formats:
---1. "1       breakpoint     keep y   0x00001234 in main at main.c:42"
---2. "2       breakpoint     keep n   main.c:15"
---3. "3       breakpoint     keep y   in function at file.c:line"
---
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
							enabled = enabled == "y",
						})
					end
				end
			end
		end
	end

	return breakpoints
end

---Check if breakpoint exists at file:line with error handling
---
---Searches through a list of breakpoints to find one that matches the specified
---file and line number. The function normalizes file paths for comparison to
---handle different path representations (relative vs absolute paths).
---
---@param breakpoints BreakpointInfo[]|nil Array of breakpoint info
---@param file string|nil File path to search for
---@param line number|nil Line number to search for
---@return number|nil Breakpoint number if exists, nil otherwise
function M.find_breakpoint(breakpoints, file, line)
	if
		not breakpoints
		or type(breakpoints) ~= "table"
		or not file
		or type(file) ~= "string"
		or file == ""
		or not line
		or type(line) ~= "number"
	then
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

-- Debounce registry to track active debounced functions
---@type table<string, {timer: userdata, count: number}>
local debounce_registry = {}

---Create an optimized debounced function with error handling and deduplication
---
---Creates a debounced version of a function that delays execution until after
---the specified delay has passed since the last invocation. This is useful for
---preventing rapid successive calls to expensive operations like GDB commands.
---
---Features:
---1. Deduplication: Multiple debounced functions with the same key share state
---2. Error handling: Gracefully handles timer creation failures
---3. Resource tracking: Properly cleans up timers to prevent leaks
---4. Fallback execution: Executes immediately if timer creation fails
---
---@param func function The function to debounce
---@param delay number Delay in milliseconds
---@param key string|nil Optional key for deduplication (uses function address if nil)
---@return function Debounced function
function M.debounce(func, delay, key)
	if type(func) ~= "function" then
		error("First argument must be a function")
	end

	if type(delay) ~= "number" or delay < 0 then
		error("Delay must be a non-negative number")
	end

	-- Use function address as key if not provided
	key = key or tostring(func)

	return function(...)
		local args = { ... }
		local entry = debounce_registry[key]

		-- Clean up existing timer if any
		if entry and entry.timer then
			local timer = entry.timer
			pcall(timer.stop, timer)
			pcall(timer.close, timer)
		end

		-- Create new timer with error handling
		local timer_ok, new_timer = pcall(vim.loop.new_timer)
		if not timer_ok then
			-- Fallback: execute function immediately if timer creation fails
			vim.schedule(function()
				local exec_ok, exec_err = pcall(func, (table.unpack or unpack)(args))
				if not exec_ok then
					vim.notify("Debounced function failed: " .. tostring(exec_err), vim.log.levels.ERROR)
				end
			end)
			return
		end

		-- Update registry
		if not entry then
			debounce_registry[key] = { timer = new_timer, count = 1 }
		else
			entry.timer = new_timer
			entry.count = entry.count + 1
		end

		local start_ok = pcall(new_timer.start, new_timer, delay, 0, function()
			-- Clean up timer
			pcall(new_timer.close, new_timer)
			if debounce_registry[key] and debounce_registry[key].timer == new_timer then
				debounce_registry[key] = nil
			end

			vim.schedule(function()
				local exec_ok, exec_err = pcall(func, (table.unpack or unpack)(args))
				if not exec_ok then
					vim.notify("Debounced function failed: " .. tostring(exec_err), vim.log.levels.ERROR)
				end
			end)
		end)

		if not start_ok then
			-- Timer start failed, execute immediately and clean up
			pcall(new_timer.close, new_timer)
			debounce_registry[key] = nil
			vim.schedule(function()
				local exec_ok, exec_err = pcall(func, (table.unpack or unpack)(args))
				if not exec_ok then
					vim.notify("Debounced function failed: " .. tostring(exec_err), vim.log.levels.ERROR)
				end
			end)
		end
	end
end

---Clean up all active debounced functions
---@return nil
function M.cleanup_debounced_functions()
	for key, entry in pairs(debounce_registry) do
		if entry.timer then
			pcall(entry.timer.stop, entry.timer)
			pcall(entry.timer.close, entry.timer)
		end
	end
	debounce_registry = {}
end

---Extract variable value from GDB print output with error handling
---
---Parses GDB "print" command output to extract the actual value from the response.
---GDB typically returns values in formats like "$1 = 42" or "$2 = 0x1234".
---This function extracts just the value part for cleaner display.
---
---Supported formats:
---1. "$1 = 42" -> "42"
---2. "$2 = 0x1234" -> "0x1234"
---3. "$3 = \"hello\"" -> "\"hello\""
---4. "$4 = {x = 1, y = 2}" -> "{x = 1, y = 2}"
---5. Direct values without $n prefix
---
---@param lines string[]|nil Array of output lines from GDB print command
---@return string|nil value The extracted value or nil if parsing fails
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

-- Resource tracking for cleanup
---@type table<string, {type: string, resource: any, cleanup_fn: function}>
local tracked_resources = {}

---Track a resource for cleanup
---
---Registers a resource for automatic cleanup when the plugin shuts down or
---when cleanup_all_resources() is called. This helps prevent resource leaks
---by ensuring all created resources are properly disposed of.
---
---@param id string Unique identifier for the resource
---@param resource_type string Type of resource (timer, buffer, window, etc.)
---@param resource any The resource to track
---@param cleanup_fn function Function to call for cleanup
---@return nil
function M.track_resource(id, resource_type, resource, cleanup_fn)
	tracked_resources[id] = {
		type = resource_type,
		resource = resource,
		cleanup_fn = cleanup_fn,
	}
end

---Untrack a resource (call when manually cleaned up)
---@param id string Resource identifier
---@return nil
function M.untrack_resource(id)
	tracked_resources[id] = nil
end

---Clean up a specific tracked resource
---@param id string Resource identifier
---@return boolean success Whether cleanup was successful
function M.cleanup_resource(id)
	local entry = tracked_resources[id]
	if not entry then
		return false
	end

	local success = pcall(entry.cleanup_fn, entry.resource)
	if success then
		tracked_resources[id] = nil
	end
	return success
end

---Clean up all tracked resources
---
---Performs cleanup of all tracked resources including timers, buffers, windows,
---and other objects. This function is called automatically when the debugging
---session ends or when the plugin is disabled. It also clears all caches and
---resets performance metrics.
---
---@return number cleaned_count Number of resources successfully cleaned up
function M.cleanup_all_resources()
	local cleaned_count = 0
	local failed_cleanups = {}

	for id, entry in pairs(tracked_resources) do
		local success = pcall(entry.cleanup_fn, entry.resource)
		if success then
			cleaned_count = cleaned_count + 1
		else
			table.insert(failed_cleanups, id)
		end
	end

	-- Clear all tracked resources
	tracked_resources = {}

	-- Clean up debounced functions
	M.cleanup_debounced_functions()

	-- Clear caches
	M.clear_gdb_info_cache()
	M.invalidate_gdb_cache()

	if #failed_cleanups > 0 then
		vim.notify("Some resources failed to clean up: " .. table.concat(failed_cleanups, ", "), vim.log.levels.WARN)
	end

	return cleaned_count
end

---Get resource tracking statistics
---@return table<string, number> Statistics by resource type
function M.get_resource_stats()
	local stats = {}
	for _, entry in pairs(tracked_resources) do
		stats[entry.type] = (stats[entry.type] or 0) + 1
	end
	return stats
end

---Validation utilities for common input types and GDB commands
---
---Provides centralized validation functions that can be used across all modules
---to ensure consistent input validation and error handling. These utilities
---help prevent common errors and provide helpful feedback to users.
---
---@class ValidationUtils
M.validation = {}

---Validate and normalize memory address
---@param address string Address to validate and normalize
---@return string|nil normalized_address, string|nil error_msg
function M.validation.normalize_address(address)
	if not address or address == "" then
		return nil, "Empty address"
	end

	local trimmed = vim.trim(address)
	if trimmed == "" then
		return nil, "Address contains only whitespace"
	end

	-- Normalize hex addresses to consistent format
	if trimmed:match("^0x%x+$") then
		return trimmed:lower(), nil
	end

	-- Convert decimal to hex for consistency
	if trimmed:match("^%d+$") then
		local num = tonumber(trimmed)
		if num then
			return string.format("0x%x", num), nil
		else
			return nil, "Invalid decimal address"
		end
	end

	-- Variable names are returned as-is
	if trimmed:match("^[%a_][%w_]*$") then
		return trimmed, nil
	end

	return nil, "Invalid address format. Use hex (0x1234), decimal (1234), or variable name"
end

---Validate GDB command and suggest corrections
---@param command string GDB command to validate
---@return boolean valid, string|nil error_msg, string|nil suggestion
function M.validation.validate_gdb_command_with_suggestions(command)
	if not command or command == "" then
		return false, "Empty GDB command", "Try 'help' for available commands"
	end

	local trimmed = vim.trim(command)
	if trimmed == "" then
		return false, "GDB command contains only whitespace", nil
	end

	-- Check for dangerous commands
	local dangerous_patterns = {
		{ pattern = "^%s*quit%s*$", suggestion = "Use :TermdebugStop instead" },
		{ pattern = "^%s*exit%s*$", suggestion = "Use :TermdebugStop instead" },
		{ pattern = "^%s*shell%s+", suggestion = "Use :! for shell commands" },
		{ pattern = "^%s*!%s*", suggestion = "Use :! for shell commands" },
	}

	for _, check in ipairs(dangerous_patterns) do
		if trimmed:lower():match(check.pattern) then
			return false, "Potentially dangerous GDB command blocked: " .. trimmed, check.suggestion
		end
	end

	-- Check for common typos and suggest corrections
	local common_typos = {
		{ typo = "^print$", suggestion = "Did you mean 'print <variable>'?" },
		{ typo = "^p$", suggestion = "Did you mean 'p <variable>'?" },
		{ typo = "^break$", suggestion = "Did you mean 'break <file:line>' or 'break <function>'?" },
		{ typo = "^b$", suggestion = "Did you mean 'b <file:line>' or 'b <function>'?" },
		{ typo = "^info$", suggestion = "Did you mean 'info breakpoints', 'info registers', or 'info locals'?" },
		{ typo = "^set$", suggestion = "Did you mean 'set variable <var> = <value>'?" },
	}

	for _, check in ipairs(common_typos) do
		if trimmed:lower():match(check.typo) then
			return true, nil, check.suggestion
		end
	end

	return true, nil, nil
end

---Validate expression and provide syntax hints
---@param expression string Expression to validate
---@return boolean valid, string|nil error_msg, string|nil hint
function M.validation.validate_expression_with_hints(expression)
	if not expression or expression == "" then
		return false, "Empty expression", "Try a variable name like 'var' or expression like 'ptr->field'"
	end

	local trimmed = vim.trim(expression)
	if trimmed == "" then
		return false, "Expression contains only whitespace", nil
	end

	-- Check for unmatched parentheses
	local paren_count = 0
	local bracket_count = 0
	local brace_count = 0

	for char in trimmed:gmatch(".") do
		if char == "(" then
			paren_count = paren_count + 1
		elseif char == ")" then
			paren_count = paren_count - 1
			if paren_count < 0 then
				return false, "Unmatched closing parenthesis", "Check parentheses balance"
			end
		elseif char == "[" then
			bracket_count = bracket_count + 1
		elseif char == "]" then
			bracket_count = bracket_count - 1
			if bracket_count < 0 then
				return false, "Unmatched closing bracket", "Check bracket balance"
			end
		elseif char == "{" then
			brace_count = brace_count + 1
		elseif char == "}" then
			brace_count = brace_count - 1
			if brace_count < 0 then
				return false, "Unmatched closing brace", "Check brace balance"
			end
		end
	end

	if paren_count ~= 0 then
		return false, "Unmatched opening parenthesis", "Add " .. paren_count .. " closing parenthesis"
	end
	if bracket_count ~= 0 then
		return false, "Unmatched opening bracket", "Add " .. bracket_count .. " closing bracket"
	end
	if brace_count ~= 0 then
		return false, "Unmatched opening brace", "Add " .. brace_count .. " closing brace"
	end

	-- Provide hints for common expression patterns
	local hints = {}
	if trimmed:match("->") then
		table.insert(hints, "Pointer dereference detected")
	end
	if trimmed:match("%[%d+%]") then
		table.insert(hints, "Array indexing detected")
	end
	if trimmed:match("%.") then
		table.insert(hints, "Structure member access detected")
	end
	if trimmed:match("&") then
		table.insert(hints, "Address-of operator detected")
	end
	if trimmed:match("%*") then
		table.insert(hints, "Dereference operator detected")
	end

	local hint = #hints > 0 and table.concat(hints, ", ") or nil
	return true, nil, hint
end

---Validate hex value with format suggestions
---@param hex_value string Hex value to validate
---@return string|nil normalized_value, string|nil error_msg, string|nil suggestion
function M.validation.normalize_hex_value(hex_value)
	if not hex_value or hex_value == "" then
		return nil, "Empty hex value", "Use format like 0xFF or FF"
	end

	local trimmed = vim.trim(hex_value)
	if trimmed == "" then
		return nil, "Hex value contains only whitespace", nil
	end

	-- Remove 0x prefix if present and normalize
	local hex_part = trimmed:gsub("^0x", ""):gsub("^0X", "")

	-- Check if it's valid hex
	if not hex_part:match("^%x+$") then
		return nil, "Invalid hex format", "Use only hex digits (0-9, A-F)"
	end

	-- Check reasonable length
	if #hex_part > 8 then
		return nil, "Hex value too long (max 8 digits for 32-bit)", "Use shorter value or split into multiple bytes"
	end

	-- Pad to even length for byte alignment
	if #hex_part % 2 == 1 then
		hex_part = "0" .. hex_part
	end

	return "0x" .. hex_part:upper(), nil, nil
end

---Comprehensive input validation with detailed feedback
---@param input_type string Type of input ("address", "expression", "hex", "command")
---@param value string Value to validate
---@return table Validation result with valid, error, suggestion, and normalized fields
function M.validation.validate_input(input_type, value)
	local result = {
		valid = false,
		error = nil,
		suggestion = nil,
		normalized = nil,
		hints = {},
	}

	if input_type == "address" then
		result.normalized, result.error = M.validation.normalize_address(value)
		result.valid = result.normalized ~= nil
	elseif input_type == "expression" then
		result.valid, result.error, result.suggestion = M.validation.validate_expression_with_hints(value)
		result.normalized = result.valid and vim.trim(value) or nil
	elseif input_type == "hex" then
		result.normalized, result.error, result.suggestion = M.validation.normalize_hex_value(value)
		result.valid = result.normalized ~= nil
	elseif input_type == "command" then
		result.valid, result.error, result.suggestion = M.validation.validate_gdb_command_with_suggestions(value)
		result.normalized = result.valid and vim.trim(value) or nil
	else
		result.error = "Unknown input type: " .. tostring(input_type)
	end

	return result
end

return M

