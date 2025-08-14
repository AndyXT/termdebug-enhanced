---@class GdbEvaluationError
---@field type string Error type (syntax, gdb_unavailable, timeout, expression_invalid)
---@field message string Human-readable error message
---@field expression string|nil The expression that failed

---@class termdebug-enhanced.evaluate
---@field evaluate_under_cursor function Evaluate expression under cursor
---@field evaluate_selection function Evaluate visual selection
---@field evaluate_custom function Evaluate custom expression
local M = {}

local utils = require("termdebug-enhanced.utils")

-- Cache for the floating window with resource tracking
---@type number|nil
local float_win = nil
---@type number|nil
local float_buf = nil

-- Resource tracking ID counter
local resource_counter = 0

---Get plugin configuration safely with fallback defaults
---
---Attempts to load the main plugin configuration, falling back to sensible
---defaults if the configuration is not available or not yet initialized.
---This prevents errors during module loading or early initialization.
---
---@return table Configuration object with popup settings
local function get_config()
  local ok, main = pcall(require, "termdebug-enhanced")
  if ok and main and type(main) == "table" and main.config and type(main.config) == "table" then
    return main.config
  end
	-- Return default config if not initialized
	return {
		popup = { border = "rounded", width = 60, height = 10 },
	}
end

---Validate expression syntax for GDB evaluation
---
---Performs basic syntax validation on expressions before sending them to GDB.
---This helps catch obvious syntax errors early and provides better error messages
---to the user. The validation includes checks for:
---
---1. Empty or whitespace-only expressions
---2. Unmatched parentheses
---3. Invalid brace syntax
---4. Other basic syntax issues
---
---@param expr string Expression to validate
---@return boolean valid, string|nil error_msg
local function validate_expression(expr)
	if not expr or expr == "" then
		return false, "Empty expression"
	end

	-- Basic syntax validation
	local trimmed = vim.trim(expr)
	if trimmed == "" then
		return false, "Expression contains only whitespace"
	end

	-- Check for obviously invalid characters that could cause issues
	if trimmed:match("[{}]") and not trimmed:match("^{.*}$") then
		return false, "Invalid brace syntax"
	end

	-- Check for unmatched parentheses
	local paren_count = 0
	for char in trimmed:gmatch(".") do
		if char == "(" then
			paren_count = paren_count + 1
		elseif char == ")" then
			paren_count = paren_count - 1
			if paren_count < 0 then
				return false, "Unmatched closing parenthesis"
			end
		end
	end

	if paren_count ~= 0 then
		return false, "Unmatched opening parenthesis"
	end

	return true, nil
end

---Check if GDB is available and ready for evaluation commands
---
---Verifies that the termdebug plugin is loaded and that a debugging session
---is currently active. This prevents attempting to send evaluation commands
---when GDB is not available or not running.
---
---@return boolean available, string|nil error_msg
local function check_gdb_availability()
	if vim.fn.exists(":Termdebug") == 0 then
		return false, "Termdebug not available. Run :packadd termdebug"
	end

	if not vim.g.termdebug_running then
		return false, "Debug session not active. Start debugging first"
	end

	return true, nil
end

---Create formatted error display content for evaluation errors
---
---Generates user-friendly error messages with helpful hints based on the error type.
---The content is formatted for display in floating windows and includes contextual
---information to help users understand and resolve the issue.
---
---@param error_info GdbEvaluationError Error information with type, message, and expression
---@return string[] Formatted error content lines for display
local function create_error_content(error_info)
	local content = {
		"❌ Evaluation Error",
		string.rep("─", 40),
	}

	if error_info.expression then
		table.insert(content, "Expression: " .. error_info.expression)
		table.insert(content, "")
	end

	local message = error_info.message or "Unknown error"
	table.insert(content, "Error: " .. message)

	-- Add helpful hints based on error type
	if error_info.type == "syntax" then
		table.insert(content, "")
		table.insert(content, "💡 Hint: Check expression syntax")
	elseif error_info.type == "gdb_unavailable" then
		table.insert(content, "")
		table.insert(content, "💡 Hint: Start debugging session first")
	elseif error_info.type == "timeout" then
		table.insert(content, "")
		table.insert(content, "💡 Hint: Expression may be too complex")
	elseif error_info.type == "expression_invalid" then
		table.insert(content, "")
		table.insert(content, "💡 Hint: Variable may not be in scope")
	end

	return content
end

---Clean up floating window resources with proper tracking
---
---Safely closes and deletes the evaluation floating window and its buffer.
---Includes error handling to prevent crashes if resources are already cleaned up
---or if cleanup operations fail. Also unregisters resources from the tracking system.
---
---@return nil
local function cleanup_float_window()
	if float_win and vim.api.nvim_win_is_valid(float_win) then
		local ok, err = pcall(vim.api.nvim_win_close, float_win, true)
		if not ok then
			vim.notify("Failed to close evaluation window: " .. tostring(err), vim.log.levels.WARN)
		end
		pcall(utils.untrack_resource, "eval_win_" .. tostring(float_win))
	end
	if float_buf and vim.api.nvim_buf_is_valid(float_buf) then
		local ok, err = pcall(vim.api.nvim_buf_delete, float_buf, { force = true })
		if not ok then
			vim.notify("Failed to delete evaluation buffer: " .. tostring(err), vim.log.levels.WARN)
		end
		pcall(utils.untrack_resource, "eval_buf_" .. tostring(float_buf))
	end
	float_win = nil
	float_buf = nil
end

---Create floating window for evaluation results
---@param content string[]|string Content to display
---@param opts table|nil Window options
---@param is_error boolean|nil Whether this is an error display
---@return number|nil, number|nil Window and buffer handles
local function create_float_window(content, opts, is_error)
	opts = opts or {}
	is_error = is_error or false

	-- Debug: Log function entry with more detail
	local content_type = type(content)
	local content_length = 0
	if content_type == "table" then
		content_length = #content
	elseif content_type == "string" then
		content_length = #vim.split(content, "\n")
	end
	vim.notify("create_float_window called with " .. content_length .. " lines (type: " .. content_type .. ")", vim.log.levels.INFO)

	-- Close existing window if any
	cleanup_float_window()

	-- Create buffer for content
	local ok, buf = pcall(vim.api.nvim_create_buf, false, true)
	if not ok then
		vim.notify("Failed to create evaluation buffer: " .. tostring(buf), vim.log.levels.ERROR)
		return nil, nil
	end
	float_buf = buf
	vim.notify("Created buffer: " .. buf, vim.log.levels.INFO)

	-- Track buffer for cleanup (with safe loading)
	resource_counter = resource_counter + 1
	local track_buf_ok = pcall(function()
		utils.track_resource("eval_buf_" .. tostring(buf), "buffer", buf, function(b)
			if vim.api.nvim_buf_is_valid(b) then
				vim.api.nvim_buf_delete(b, { force = true })
			end
		end)
	end)
	if not track_buf_ok then
		-- Fallback: manual cleanup will be handled by cleanup_float_window function
		vim.notify("Resource tracking unavailable for evaluation buffer", vim.log.levels.DEBUG)
	end

	-- Process content into lines
	local lines = {}
	if type(content) == "string" then
		lines = vim.split(content, "\n")
	elseif type(content) == "table" then
		lines = content
	else
		lines = {"No content provided"}
	end

	vim.notify("Setting buffer content: " .. vim.inspect(lines), vim.log.levels.INFO)
	local set_ok, set_err = pcall(vim.api.nvim_buf_set_lines, float_buf, 0, -1, false, lines)
	if not set_ok then
		vim.notify("Failed to set buffer content: " .. tostring(set_err), vim.log.levels.ERROR)
		cleanup_float_window()
		return nil, nil
	end

	-- Calculate window size based on content
	local max_line_length = 0
	for _, line in ipairs(lines) do
		max_line_length = math.max(max_line_length, vim.fn.strdisplaywidth(line))
	end

	-- Dynamic width: at least 40, at most 120, or content width + padding
	local width = math.min(120, math.max(40, max_line_length + 4))

	-- Dynamic height: at least 3, at most 20, or content height + padding
	local height = math.min(20, math.max(3, #lines + 2))

	-- Get cursor position for better positioning
	local cursor_pos = vim.api.nvim_win_get_cursor(0)
	local cursor_row = cursor_pos[1]
	local cursor_col = cursor_pos[2]

	-- Calculate position to avoid going off screen
	local screen_height = vim.o.lines
	local screen_width = vim.o.columns

	-- Position below cursor, but move up if it would go off screen
	local row = 1
	if cursor_row + height + 3 > screen_height then
		row = -(height + 1) -- Position above cursor instead
	end

	-- Position at cursor column, but adjust if it would go off screen
	local col = 0
	if cursor_col + width > screen_width then
		col = -(width - 10) -- Move left to fit on screen
	end

	-- Use cursor-relative positioning for better reliability
	local win_opts = {
		relative = "cursor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = opts.border or "rounded",
		noautocmd = true,
		focusable = true,  -- Make it focusable for scrolling
		zindex = 50,  -- Ensure it appears above other windows
	}

	vim.notify("Creating window with opts: " .. vim.inspect(win_opts), vim.log.levels.INFO)
	local win_ok, win = pcall(vim.api.nvim_open_win, float_buf, false, win_opts)
	if not win_ok then
		vim.notify("Failed to create evaluation window: " .. tostring(win), vim.log.levels.ERROR)
		cleanup_float_window()
		return nil, nil
	end
	float_win = win
	vim.notify("Created window: " .. win, vim.log.levels.INFO)

	-- Track window for cleanup (with safe loading)
	local track_win_ok = pcall(function()
		utils.track_resource("eval_win_" .. tostring(win), "window", win, function(w)
			if vim.api.nvim_win_is_valid(w) then
				vim.api.nvim_win_close(w, true)
			end
		end)
	end)
	if not track_win_ok then
		-- Fallback: manual cleanup will be handled by cleanup_float_window function
		vim.notify("Resource tracking unavailable for evaluation window", vim.log.levels.DEBUG)
	end

	-- Set buffer options (using modern API with error handling)
	pcall(function()
		vim.bo[float_buf].bufhidden = "wipe"
		vim.bo[float_buf].filetype = is_error and "text" or "gdb"
		vim.bo[float_buf].modifiable = false
		vim.bo[float_buf].readonly = true
		vim.bo[float_buf].buftype = "nofile"
		vim.bo[float_buf].swapfile = false
		vim.bo[float_buf].wrap = true  -- Enable word wrap for long lines
		vim.bo[float_buf].linebreak = true  -- Break at word boundaries
	end)

	-- Add syntax highlighting for GDB output
	pcall(function()
		local highlight = is_error and "Normal:ErrorMsg,FloatBorder:ErrorMsg"
			or "Normal:NormalFloat,FloatBorder:FloatBorder"
		vim.wo[float_win].winhl = highlight
	end)

	-- Add scrolling keymaps to the popup window
	pcall(function()
		local opts_map = { noremap = true, silent = true }

		-- Scrolling keymaps
		vim.api.nvim_buf_set_keymap(float_buf, "n", "j", "<C-e>", opts_map)  -- Scroll down
		vim.api.nvim_buf_set_keymap(float_buf, "n", "k", "<C-y>", opts_map)  -- Scroll up
		vim.api.nvim_buf_set_keymap(float_buf, "n", "<Down>", "<C-e>", opts_map)
		vim.api.nvim_buf_set_keymap(float_buf, "n", "<Up>", "<C-y>", opts_map)
		vim.api.nvim_buf_set_keymap(float_buf, "n", "<PageDown>", "<C-f>", opts_map)
		vim.api.nvim_buf_set_keymap(float_buf, "n", "<PageUp>", "<C-b>", opts_map)

		-- Close keymaps
		vim.api.nvim_buf_set_keymap(float_buf, "n", "q", ":close<CR>", opts_map)
		vim.api.nvim_buf_set_keymap(float_buf, "n", "<Esc>", ":close<CR>", opts_map)
		vim.api.nvim_buf_set_keymap(float_buf, "n", "<CR>", ":close<CR>", opts_map)
	end)

	-- Close on cursor move or insert mode (with error handling)
	-- Add a small delay to prevent immediate closure
	vim.defer_fn(function()
		pcall(vim.api.nvim_create_autocmd, { "CursorMoved", "InsertEnter", "BufLeave" }, {
			once = true,
			callback = function()
				cleanup_float_window()
			end,
		})
	end, 100)  -- 100ms delay

	-- Add keybinding to close with Esc (with error handling)
	pcall(vim.api.nvim_buf_set_keymap, float_buf, "n", "<Esc>", "", {
		callback = function()
			cleanup_float_window()
		end,
		noremap = true,
		silent = true,
	})

	return float_win, float_buf
end

---Get GDB response using async polling with comprehensive error handling
---@param command string GDB command to execute
---@param expression string Original expression for error reporting
---@param callback fun(lines: string[]|nil, error_info: GdbEvaluationError|nil): nil Callback function
---@return nil
local function get_gdb_response(command, expression, callback)
	-- Check GDB availability first
	local available, availability_error = check_gdb_availability()
	if not available then
		callback(nil, {
			type = "gdb_unavailable",
			message = availability_error or "GDB not available",
			expression = expression,
		})
		return
	end

	utils.async_gdb_response(command, function(response, error)
		if error then
			local error_type = "expression_invalid"
			local error_msg = error

			-- Categorize error types
			if error:match("[Tt]imeout") then
				error_type = "timeout"
				error_msg = "GDB response timeout - expression may be too complex"
			elseif error:match("[Nn]ot available") or error:match("[Nn]ot active") then
				error_type = "gdb_unavailable"
			elseif error:match("[Ss]yntax") or error:match("[Ii]nvalid") then
				error_type = "syntax"
			end

			callback(nil, {
				type = error_type,
				message = error_msg,
				expression = expression,
			})
		else
			-- Check if response indicates an error
			if response and #response > 0 then
				local response_text = table.concat(response, " ")
				if
					response_text:match("[Nn]o symbol")
					or response_text:match("[Uu]ndefined")
					or response_text:match("[Ee]rror")
				then
					callback(nil, {
						type = "expression_invalid",
						message = "Expression not found or not in scope: " .. response_text,
						expression = expression,
					})
					return
				end
			end

			callback(response, nil)
		end
	end, { timeout = 3000, poll_interval = 50 })
end

---Test function to verify popup creation works
---@return nil
function M.test_popup()
	vim.notify("Testing popup creation...", vim.log.levels.INFO)
	local config = get_config()
	local test_content = {
		"✓ Test Popup",
		"─────────────",
		"",
		"This is a test popup to verify",
		"that the floating window creation",
		"is working correctly.",
		"",
		"If you see this, the popup",
		"functionality is working!"
	}

	local win, _ = create_float_window(test_content, config.popup, false)
	if win then
		vim.notify("Test popup created successfully!", vim.log.levels.INFO)
	else
		vim.notify("Test popup creation failed!", vim.log.levels.ERROR)
	end
end

---Diagnose available GDB functions and commands
---@return nil
function M.diagnose_gdb_functions()
	vim.notify("=== GDB Function Diagnostics ===", vim.log.levels.INFO)

	-- Check basic termdebug availability
	vim.notify("Termdebug command exists: " .. tostring(vim.fn.exists(":Termdebug") == 1), vim.log.levels.INFO)
	vim.notify("Termdebug running: " .. tostring(vim.g.termdebug_running or false), vim.log.levels.INFO)

	-- Check for various GDB command functions
	local functions_to_check = {
		"TermdebugCommand",
		"TermDebugSendCommand",
		"TermdebugSendCommand",
		"TermDebugCommand",
		"Evaluate",
		"Gdb",
		"TermdebugEvaluate"
	}

	for _, func_name in ipairs(functions_to_check) do
		local exists = vim.fn.exists('*' .. func_name) == 1
		vim.notify("Function " .. func_name .. " exists: " .. tostring(exists), vim.log.levels.INFO)
	end

	-- Check for termdebug commands
	local commands_to_check = {
		"Continue",
		"Over",
		"Step",
		"Finish",
		"Stop",
		"Run",
		"Break",
		"Clear",
		"Evaluate"
	}

	vim.notify("--- Checking Termdebug Commands ---", vim.log.levels.INFO)
	for _, cmd_name in ipairs(commands_to_check) do
		local exists = vim.fn.exists(':' .. cmd_name) == 1
		vim.notify("Command :" .. cmd_name .. " exists: " .. tostring(exists), vim.log.levels.INFO)
	end

	-- Check for GDB buffer
	local gdb_buf = utils.find_gdb_buffer()
	vim.notify("GDB buffer found: " .. tostring(gdb_buf ~= nil), vim.log.levels.INFO)
	if gdb_buf then
		vim.notify("GDB buffer ID: " .. gdb_buf, vim.log.levels.INFO)
		local buf_name = vim.api.nvim_buf_get_name(gdb_buf)
		vim.notify("GDB buffer name: " .. buf_name, vim.log.levels.INFO)
	end

	-- Check global variables
	local gdb_vars = {
		"termdebug_running",
		"termdebugger",
		"termdebug_wide",
		"gdb_channel"
	}

	for _, var_name in ipairs(gdb_vars) do
		local value = vim.g[var_name]
		vim.notify("vim.g." .. var_name .. " = " .. vim.inspect(value), vim.log.levels.INFO)
	end

	vim.notify("=== End GDB Diagnostics ===", vim.log.levels.INFO)
end

---Test F10 keymap functionality
---@return nil
function M.test_f10_keymap()
	vim.notify("=== Testing F10 Keymap ===", vim.log.levels.INFO)

	-- Check if F10 is mapped
	local f10_mapping = vim.fn.maparg("<F10>", "n")
	vim.notify("F10 mapping: " .. vim.inspect(f10_mapping), vim.log.levels.INFO)

	-- Test the Over command directly
	vim.notify("Testing :Over command directly...", vim.log.levels.INFO)
	local over_ok, over_err = pcall(vim.cmd, "Over")
	vim.notify("Over command result: " .. tostring(over_ok) .. ", error: " .. tostring(over_err), vim.log.levels.INFO)

	-- Test sending "next" command directly to GDB
	vim.notify("Testing direct GDB 'next' command...", vim.log.levels.INFO)
	if vim.fn.exists('*TermDebugSendCommand') == 1 then
		local send_ok, send_err = pcall(vim.fn.TermDebugSendCommand, "next")
		vim.notify("Direct 'next' command result: " .. tostring(send_ok) .. ", error: " .. tostring(send_err), vim.log.levels.INFO)
	else
		vim.notify("TermDebugSendCommand not available", vim.log.levels.WARN)
	end

	-- Check current keymaps
	vim.notify("Current normal mode keymaps containing F10:", vim.log.levels.INFO)
	local keymaps = vim.api.nvim_get_keymap("n")
	for _, keymap in ipairs(keymaps) do
		if keymap.lhs and keymap.lhs:match("F10") then
			vim.notify("Found F10 keymap: " .. vim.inspect(keymap), vim.log.levels.INFO)
		end
	end

	vim.notify("=== End F10 Test ===", vim.log.levels.INFO)
end

---Test evaluation with direct GDB buffer reading
---@return nil
function M.test_direct_evaluation()
	vim.notify("=== Testing Direct Evaluation ===", vim.log.levels.INFO)

	local word = vim.fn.expand("<cword>")
	if word == "" then
		word = "test_var"
	end

	vim.notify("Testing evaluation of: " .. word, vim.log.levels.INFO)

	-- Send command directly and read buffer immediately
	if vim.fn.exists('*TermDebugSendCommand') == 1 then
		local send_ok = pcall(vim.fn.TermDebugSendCommand, "print " .. word)
		vim.notify("Command sent: " .. tostring(send_ok), vim.log.levels.INFO)

		if send_ok then
			-- Wait a moment then read the GDB buffer directly
			vim.defer_fn(function()
				local gdb_buf = utils.find_gdb_buffer()
				if gdb_buf then
					-- Get more lines to ensure we capture the response
					local lines = vim.api.nvim_buf_get_lines(gdb_buf, -50, -1, false)
					vim.notify("Recent GDB buffer lines (" .. #lines .. " lines): " .. vim.inspect(lines), vim.log.levels.INFO)

					-- Try multiple approaches to find the response
					local response_lines = {}

					-- Approach 1: Look for $N = value pattern and capture multi-line response
					local found_start = false
					local start_index = nil

					-- First, find where the response starts (the $N = line)
					for i = #lines, 1, -1 do
						local line = lines[i]
						if line:match("%$%d+%s*=") then
							start_index = i
							found_start = true
							vim.notify("Found $N = pattern at line " .. i .. ": " .. line, vim.log.levels.INFO)
							break
						end
					end

					-- If we found the start, capture all lines until the next (gdb) prompt
					if found_start and start_index then
						for i = start_index, #lines do
							local line = lines[i]
							if line:match("^%(gdb%)") then
								-- Stop at the next GDB prompt
								break
							else
								table.insert(response_lines, line)
								vim.notify("Captured response line: " .. line, vim.log.levels.INFO)
							end
						end
					end

					-- Approach 2: If no $N pattern, look for lines after our print command
					if #response_lines == 0 then
						local found_print = false
						for i = #lines, 1, -1 do
							local line = lines[i]
							if line:match("^%(gdb%)") and found_print then
								break
							elseif line:match("print") and line:match(vim.pesc(word)) then
								found_print = true
								vim.notify("Found print command: " .. line, vim.log.levels.INFO)
							elseif found_print and not line:match("^%(gdb%)") and line ~= "" then
								table.insert(response_lines, 1, line)
								vim.notify("Found response line: " .. line, vim.log.levels.INFO)
							end
						end
					end

					-- Approach 3: If still nothing, look for any non-empty, non-gdb-prompt lines
					if #response_lines == 0 then
						vim.notify("No response found with standard patterns, checking all recent lines...", vim.log.levels.INFO)
						for i = math.max(1, #lines - 5), #lines do
							local line = lines[i]
							if line and line ~= "" and not line:match("^%(gdb%)") and not line:match("^print") then
								table.insert(response_lines, line)
								vim.notify("Found potential response: " .. line, vim.log.levels.INFO)
							end
						end
					end

					vim.notify("Final extracted response: " .. vim.inspect(response_lines), vim.log.levels.INFO)

					if #response_lines > 0 then
						-- Create popup with the response
						local config = get_config()
						local content = {
							"✓ Direct Evaluation: " .. word,
							string.rep("─", math.max(30, #word + 20)),
							"",
							"Response found:",
							""
						}

						-- Format response lines with proper wrapping
						for _, line in ipairs(response_lines) do
							-- Split very long lines for better display
							if #line > 80 then
								local wrapped_lines = {}
								for i = 1, #line, 80 do
									table.insert(wrapped_lines, line:sub(i, i + 79))
								end
								for _, wrapped_line in ipairs(wrapped_lines) do
									table.insert(content, "  " .. wrapped_line)
								end
							else
								table.insert(content, "  " .. line)
							end
						end

						table.insert(content, "")
						table.insert(content, "Use j/k or ↑/↓ to scroll, q/Esc to close")

						local win, _ = create_float_window(content, config.popup, false)
						if win then
							vim.notify("Direct evaluation popup created!", vim.log.levels.INFO)
						else
							vim.notify("Failed to create popup", vim.log.levels.ERROR)
						end
					else
						vim.notify("No response found in buffer", vim.log.levels.WARN)
					end
				else
					vim.notify("GDB buffer not found", vim.log.levels.ERROR)
				end
			end, 500) -- Wait 500ms for response
		end
	else
		vim.notify("TermDebugSendCommand not available", vim.log.levels.ERROR)
	end

	vim.notify("=== End Direct Evaluation Test ===", vim.log.levels.INFO)
end

---Debug all buffers to find where GDB output is going
---@return nil
function M.debug_all_buffers()
	vim.notify("=== Debugging All Buffers ===", vim.log.levels.INFO)

	local buffers = vim.api.nvim_list_bufs()
	vim.notify("Found " .. #buffers .. " total buffers", vim.log.levels.INFO)

	for _, buf in ipairs(buffers) do
		if vim.api.nvim_buf_is_valid(buf) then
			local name = vim.api.nvim_buf_get_name(buf)
			local lines = vim.api.nvim_buf_get_lines(buf, -10, -1, false)

			-- Check if this buffer contains GDB-like content
			local has_gdb_content = false
			for _, line in ipairs(lines) do
				if line:match("%(gdb%)") or line:match("%$%d+%s*=") or line:match("print") then
					has_gdb_content = true
					break
				end
			end

			if has_gdb_content or name:match("[Gg]db") or name:match("[Dd]ebug") then
				vim.notify("Buffer " .. buf .. " (" .. name .. ") - GDB content detected:", vim.log.levels.INFO)
				vim.notify("Last 10 lines: " .. vim.inspect(lines), vim.log.levels.INFO)
			else
				vim.notify("Buffer " .. buf .. " (" .. name .. ") - No GDB content", vim.log.levels.DEBUG)
			end
		end
	end

	-- Also check what find_gdb_buffer returns
	local gdb_buf = utils.find_gdb_buffer()
	vim.notify("utils.find_gdb_buffer() returned: " .. tostring(gdb_buf), vim.log.levels.INFO)

	vim.notify("=== End Buffer Debug ===", vim.log.levels.INFO)
end

---Test function to verify GDB response mechanism
---@return nil
function M.test_gdb_response()
	vim.notify("Testing GDB response mechanism...", vim.log.levels.INFO)

	-- First run diagnostics
	M.diagnose_gdb_functions()

	-- Check if GDB is available
	local available, availability_error = check_gdb_availability()
	if not available then
		vim.notify("GDB not available: " .. (availability_error or "unknown"), vim.log.levels.WARN)
		return
	end

	vim.notify("GDB is available, testing response...", vim.log.levels.INFO)

	-- Use simple GDB response for testing
	utils.simple_gdb_response("print 42", function(response_lines, error_msg)
		if error_msg then
			vim.notify("GDB response test failed: " .. error_msg, vim.log.levels.ERROR)
		else
			vim.notify("GDB response test succeeded! Lines: " .. vim.inspect(response_lines), vim.log.levels.INFO)

			-- Now test popup creation with the response
			local config = get_config()
			local test_content = {
				"✓ GDB Response Test",
				"─────────────────────",
				"",
				"Command: print 42",
				"Response received successfully:",
			}

			if response_lines and #response_lines > 0 then
				for _, line in ipairs(response_lines) do
					table.insert(test_content, "  " .. line)
				end
			else
				table.insert(test_content, "  (no response lines)")
			end

			table.insert(test_content, "")
			table.insert(test_content, "This proves GDB communication works!")

			local win, _ = create_float_window(test_content, config.popup, false)
			if win then
				vim.notify("GDB response popup created successfully!", vim.log.levels.INFO)
			else
				vim.notify("Failed to create popup with GDB response!", vim.log.levels.ERROR)
			end
		end
	end)
end

---Evaluate expression under cursor and show in popup
---
---Evaluates the variable or expression under the cursor and displays the result
---in a floating popup window. This function mimics the behavior of LSP hover
---functionality but for debugging contexts.
---
---The function first tries to get a C expression under the cursor using <cexpr>,
---falling back to <cword> if no expression is found. It performs syntax validation
---before sending the expression to GDB for evaluation.
---
---Features:
---- Automatic expression detection under cursor
---- Syntax validation with helpful error messages
---- Formatted popup display with value extraction
---- Error handling with categorized error types
---
---@return nil
function M.evaluate_under_cursor()
	-- Debug: Add notification to verify function is called
	vim.notify("evaluate_under_cursor called", vim.log.levels.INFO)

	local word = vim.fn.expand("<cexpr>")
	if word == "" then
		word = vim.fn.expand("<cword>")
	end

	if word == "" then
		vim.notify("No expression under cursor", vim.log.levels.WARN)
		return
	end

	vim.notify("Evaluating word: " .. word, vim.log.levels.INFO)

	-- Validate expression syntax
	local valid, syntax_error = validate_expression(word)
	if not valid then
		local error_content = create_error_content({
			type = "syntax",
			message = syntax_error or "Invalid expression syntax",
			expression = word,
		})
		local config = get_config()
		create_float_window(error_content, config.popup, true)
		return
	end

	-- Check if GDB is available, if not show a demo popup
	local available, availability_error = check_gdb_availability()
	if not available then
		vim.notify("GDB not available: " .. (availability_error or "unknown error"), vim.log.levels.WARN)
		vim.notify("Showing demo popup instead...", vim.log.levels.INFO)

		local config = get_config()
		local demo_content = {
			"⚠ Demo Mode - GDB Not Available",
			string.rep("─", 40),
			"",
			"Expression: " .. word,
			"",
			"GDB is not currently running.",
			"Start a debugging session to evaluate",
			"expressions properly.",
			"",
			"This popup demonstrates that the",
			"floating window functionality works."
		}

		create_float_window(demo_content, config.popup, true)
		return
	end

	-- Use the full async GDB response now that we fixed the command sending
	vim.notify("Using async GDB response with fixed command sending for: " .. word, vim.log.levels.INFO)

	-- Add a timeout to detect if callback never gets called
	local callback_called = false
	local timeout_timer = vim.defer_fn(function()
		if not callback_called then
			vim.notify("WARNING: GDB response callback never called for '" .. word .. "' - response polling may have failed", vim.log.levels.WARN)
			-- Show a fallback popup to indicate the issue
			local config = get_config()
			local fallback_content = {
				"⚠ Evaluation Timeout",
				string.rep("─", 30),
				"",
				"Expression: " .. word,
				"",
				"The GDB response was not received",
				"within the expected time.",
				"",
				"Possible causes:",
				"• GDB response polling failed",
				"• Command not recognized by GDB",
				"• Variable not in current scope"
			}
			create_float_window(fallback_content, config.popup, true)
		end
	end, 5000) -- 5 second timeout

	get_gdb_response("print " .. word, word, function(response_lines, error_info)
		callback_called = true
		-- Cancel the timeout timer since callback was called
		if timeout_timer then
			pcall(timeout_timer.close, timeout_timer)
		end
		local config = get_config()

		-- Debug: Add notification to verify callback is called
		vim.notify("Evaluate callback called for: " .. word, vim.log.levels.INFO)

		if error_info then
			-- Show error in popup
			local error_content = create_error_content(error_info)
			vim.notify("Creating error popup for: " .. (error_info.message or "unknown error"), vim.log.levels.INFO)
			create_float_window(error_content, config.popup, true)
			return
		end

		-- Enhanced formatting with better value extraction and display
		local formatted = {}
		table.insert(formatted, "✓ Expression: " .. word)
		table.insert(formatted, string.rep("─", math.max(40, #word + 15)))

		if response_lines and #response_lines > 0 then
			vim.notify("Got GDB response with " .. #response_lines .. " lines: " .. vim.inspect(response_lines), vim.log.levels.INFO)
			local value = utils.extract_value(response_lines)
			if value then
				-- Format value based on type detection
				local formatted_value = value

				-- Detect and format different value types
				if value:match("^0x%x+$") then
					-- Hex value - show both hex and decimal
					local hex_num = tonumber(value:sub(3), 16)
					if hex_num then
						formatted_value = string.format("%s (%d)", value, hex_num)
					end
				elseif value:match("^%-?%d+$") then
					-- Integer - show hex representation if > 255
					local num = tonumber(value)
					if num and math.abs(num) > 255 then
						formatted_value = string.format("%s (0x%x)", value, num)
					end
				elseif value:match("^{.*}$") then
					-- Structure - format with proper indentation
					formatted_value = value:gsub(", ", ",\n  ")
				end

				table.insert(formatted, "")
				table.insert(formatted, "Value: " .. formatted_value)

				-- Add type information if available from GDB response
				local full_response = table.concat(response_lines, " ")
				local type_info = full_response:match("%(([^%)]+)%)")
				if type_info and not type_info:match("gdb") then
					table.insert(formatted, "Type:  " .. type_info)
				end
			else
				-- Show raw response if value extraction fails
				table.insert(formatted, "")
				for _, line in ipairs(response_lines) do
					if line and line ~= "" and not line:match("^%(gdb%)") then
						table.insert(formatted, line)
					end
				end
			end
		else
			vim.notify("No response lines from GDB", vim.log.levels.WARN)
			table.insert(formatted, "")
			table.insert(formatted, "No output from GDB")
		end

		-- Debug: Notify before creating popup
		vim.notify("Creating popup with " .. #formatted .. " lines: " .. vim.inspect(formatted), vim.log.levels.INFO)

		-- Show in floating window
		local win, buf = create_float_window(formatted, config.popup, false)
		if win then
			vim.notify("Popup created successfully: win=" .. win .. ", buf=" .. (buf or "nil"), vim.log.levels.INFO)
		else
			vim.notify("Failed to create popup window", vim.log.levels.ERROR)
		end
	end)
end

---Evaluate visual selection and show in popup
---
---Evaluates the currently selected text in visual mode and displays the result
---in a floating popup window. This allows evaluation of complex expressions
---that span multiple lines or contain special characters.
---
---The function handles both single-line and multi-line selections, properly
---extracting the selected text and joining multi-line selections with spaces.
---It includes comprehensive error handling for selection retrieval and validation.
---
---Features:
---- Single and multi-line selection support
---- Proper text extraction from visual selection
---- Syntax validation before evaluation
---- Error handling for invalid selections
---
---@return nil
function M.evaluate_selection()
	-- Get visual selection with error handling
	local start_pos_ok, start_pos = pcall(vim.fn.getpos, "'<")
	local end_pos_ok, end_pos = pcall(vim.fn.getpos, "'>")

	if not start_pos_ok or not end_pos_ok then
		vim.notify("Could not get visual selection", vim.log.levels.ERROR)
		return
	end

	local selection_lines_ok, selection_lines =
		pcall(vim.api.nvim_buf_get_lines, 0, start_pos[2] - 1, end_pos[2], false)
	if not selection_lines_ok or #selection_lines == 0 then
		vim.notify("No text selected", vim.log.levels.WARN)
		return
	end

	local expr = ""
	if #selection_lines == 1 then
		-- Single line selection
		local line = selection_lines[1]
		local start_col = math.max(1, start_pos[3])
		local end_col = math.min(#line, end_pos[3])
		expr = line:sub(start_col, end_col)
	else
		-- Multi-line selection
		selection_lines[1] = selection_lines[1]:sub(start_pos[3])
		selection_lines[#selection_lines] = selection_lines[#selection_lines]:sub(1, end_pos[3])
		expr = table.concat(selection_lines, " ")
	end

	-- Clean up expression
	expr = vim.trim(expr)
	if expr == "" then
		vim.notify("No expression selected", vim.log.levels.WARN)
		return
	end

	-- Validate expression syntax
	local valid, syntax_error = validate_expression(expr)
	if not valid then
		local error_content = create_error_content({
			type = "syntax",
			message = syntax_error or "Invalid expression syntax",
			expression = expr,
		})
		local config = get_config()
		create_float_window(error_content, config.popup, true)
		return
	end

	get_gdb_response("print " .. expr, expr, function(response_lines, error_info)
		local config = get_config()

		if error_info then
			-- Show error in popup
			local error_content = create_error_content(error_info)
			create_float_window(error_content, config.popup, true)
			return
		end

		-- Format the output nicely
		local formatted = {}
		table.insert(formatted, "✓ Expression: " .. expr)
		table.insert(formatted, string.rep("─", 40))

		if response_lines and #response_lines > 0 then
			for _, line in ipairs(response_lines) do
				table.insert(formatted, line)
			end
		else
			table.insert(formatted, "No output")
		end

		-- Show in floating window
		create_float_window(formatted, config.popup, false)
	end)
end

---Evaluate custom expression with optional user input
---
---Evaluates a custom expression provided by the user. If no expression is provided,
---prompts the user to enter one. This function is useful for evaluating arbitrary
---expressions that are not under the cursor or in a selection.
---
---The function includes input validation and error handling, ensuring that empty
---or invalid expressions are handled gracefully with appropriate user feedback.
---
---@param expr string|nil Expression to evaluate (prompts if nil)
---@return nil
function M.evaluate_custom(expr)
	if not expr or expr == "" then
		local input_ok, input_expr = pcall(vim.fn.input, "Evaluate: ")
		if not input_ok then
			vim.notify("Failed to get input", vim.log.levels.ERROR)
			return
		end
		expr = input_expr
	end

	expr = vim.trim(expr)
	if expr == "" then
		return
	end

	-- Validate expression syntax
	local valid, syntax_error = validate_expression(expr)
	if not valid then
		local error_content = create_error_content({
			type = "syntax",
			message = syntax_error or "Invalid expression syntax",
			expression = expr,
		})
		local config = get_config()
		create_float_window(error_content, config.popup, true)
		return
	end

	get_gdb_response("print " .. expr, expr, function(response_lines, error_info)
		local config = get_config()

		if error_info then
			-- Show error in popup
			local error_content = create_error_content(error_info)
			create_float_window(error_content, config.popup, true)
			return
		end

		-- Format the output nicely
		local formatted = {}
		table.insert(formatted, "✓ Expression: " .. expr)
		table.insert(formatted, string.rep("─", 40))

		if response_lines and #response_lines > 0 then
			for _, line in ipairs(response_lines) do
				table.insert(formatted, line)
			end
		else
			table.insert(formatted, "No output")
		end

		-- Show in floating window
		create_float_window(formatted, config.popup, false)
	end)
end

---Clean up all evaluation resources
---@return nil
function M.cleanup_all_windows()
	cleanup_float_window()
end

return M
