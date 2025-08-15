---@class MemoryState
---@field address string|nil Current memory address
---@field size number Number of bytes to display
---@field variable string|nil Variable name if applicable
---@field format string Current display format

---@class MemoryError
---@field type string Error type (invalid_address, access_denied, gdb_unavailable, timeout)
---@field message string Human-readable error message
---@field address string|nil The address that caused the error

---@class termdebug-enhanced.memory
local M = {}

local utils = require("termdebug-enhanced.utils")
local config = require("termdebug-enhanced.config")

-- State management
local current_memory = {
	address = nil,
	size = 256,
	variable = nil,
	format = "hex",
}

-- Window handles
local memory_win, memory_buf = nil, nil
local popup_win, popup_buf = nil, nil

local VALID_FORMATS = { "hex", "decimal", "binary", "base64" }

-- Validation functions
local validators = {
	gdb_available = function()
		if vim.fn.exists(":Termdebug") == 0 then
			return false, "Termdebug not available. Run :packadd termdebug"
		end
		if not vim.g.termdebug_running then
			return false, "Debug session not active. Start debugging first"
		end
		return true, nil
	end,

	valid_address = function(addr)
		if not addr or vim.trim(addr) == "" then
			return false, "Empty address"
		end
		local trimmed = vim.trim(addr)
		if trimmed:match("^0x%x+$") or trimmed:match("^%d+$") or trimmed:match("^[%a_][%w_]*$") then
			return true, nil
		end
		return false, "Invalid address format. Use hex (0x1234), decimal (1234), or variable name"
	end,

	valid_format = function(format)
		for _, valid_fmt in ipairs(VALID_FORMATS) do
			if format == valid_fmt then
				return true, nil
			end
		end
		return false, "Invalid format: " .. format .. ". Valid formats: " .. table.concat(VALID_FORMATS, ", ")
	end,

	has_active_memory = function()
		if not current_memory.address then
			return false, "No memory view active"
		end
		return true, nil
	end,
}

---Show error to user with optional window display
---@param message string Error message
---@param context? string Error context
local function show_error(message, context)
	local full_message = context and (context .. ": " .. message) or message
	vim.notify(full_message, vim.log.levels.ERROR)
end

---Execute operation with validation and error handling
---@param validations table List of validation functions
---@param operation function Operation to execute
---@param error_context? string Context for error messages
---@return any|nil
local function with_validation(validations, operation, error_context)
	for _, validation in ipairs(validations) do
		local ok, error_msg = validation()
		if not ok then
			show_error(error_msg, error_context)
			return nil
		end
	end
	return operation()
end

---Show error in window format
---@param error_info MemoryError
---@param window_type? string "popup" or "split"
local function show_error_window(error_info, window_type)
	window_type = window_type or "split"

	local content = {
		"❌ Memory Error",
		string.rep("─", 50),
	}

	if error_info.address then
		table.insert(content, "Address: " .. error_info.address)
		table.insert(content, "")
	end

	table.insert(content, "Error: " .. (error_info.message or "Unknown error"))

	-- Add contextual hints
	local hints = {
		invalid_address = "💡 Hint: Check address format (0x1234 or variable name)",
		access_denied = "💡 Hint: Address may be protected or invalid",
		gdb_unavailable = "💡 Hint: Start debugging session first",
		timeout = "💡 Hint: Memory operation timed out",
	}

	if hints[error_info.type] then
		table.insert(content, "")
		table.insert(content, hints[error_info.type])
	end

	if window_type == "popup" then
		create_popup_window(content, {}, true)
	else
		create_memory_window(content, config.get_memory_viewer(), true)
	end
end

-- Helper functions for GDB response parsing
---Parse GDB response for a specific pattern
---@param response table|nil GDB response lines
---@param pattern string Lua pattern to match
---@return string|nil Matched value or nil
local function parse_gdb_value(response, pattern)
	if not response or #response == 0 then
		return nil
	end
	for _, line in ipairs(response) do
		local match = line:match(pattern)
		if match then
			return match
		end
	end
	return nil
end

-- Memory operations
local memory_ops = {
	---Get memory data from GDB
	---@param address string
	---@param size number
	---@param callback function
	get_data = function(address, size, callback)
		local cmd = string.format("x/%dxb %s", size, address)
		utils.async_gdb_response(cmd, callback, { timeout = 5000 })
	end,

	---Resolve variable to address
	---@param variable string
	---@param callback function
	resolve_address = function(variable, callback)
		utils.async_gdb_response("print &" .. variable, function(response, error)
			if error then
				callback(nil, error)
				return
			end

			local addr = parse_gdb_value(response, "0x%x+")
			callback(addr, addr and nil or "Could not resolve variable address")
		end, { timeout = 3000 })
	end,

	---Get variable size
	---@param variable string
	---@param callback function
	get_variable_size = function(variable, callback)
		utils.async_gdb_response("print sizeof(" .. variable .. ")", function(response, error)
			if error then
				callback(nil, error)
				return
			end

			local size_str = parse_gdb_value(response, "= (%d+)")
			local size = size_str and tonumber(size_str) or nil
			callback(size, size and nil or "Could not get variable size")
		end, { timeout = 2000 })
	end,
}

-- Format handling
local format_handlers = {
	hex = function(bytes)
		return table.concat(
			vim.tbl_map(function(b)
				return string.format("0x%02x", b)
			end, bytes),
			" "
		)
	end,

	decimal = function(bytes)
		return table.concat(
			vim.tbl_map(function(b)
				return string.format("%3d", b)
			end, bytes),
			" "
		)
	end,

	binary = function(bytes)
		return table.concat(
			vim.tbl_map(function(b)
				local binary = ""
				for bit = 7, 0, -1 do
					local bit_val = math.floor(b / (2 ^ bit)) % 2
					binary = binary .. tostring(bit_val)
				end
				return binary
			end, bytes),
			" "
		)
	end,

	base64 = function(bytes)
		-- Simple base64 implementation
		local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
		local result = ""
		local i = 1

		while i <= #bytes do
			local b1, b2, b3 = bytes[i] or 0, bytes[i + 1] or 0, bytes[i + 2] or 0
			local n = (b1 * 65536) + (b2 * 256) + b3

			local c1 = chars:sub(math.floor(n / 262144) + 1, math.floor(n / 262144) + 1)
			local c2 = chars:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
			local c3 = i + 1 <= #bytes and chars:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1) or "="
			local c4 = i + 2 <= #bytes and chars:sub(n % 64 + 1, n % 64 + 1) or "="

			result = result .. c1 .. c2 .. c3 .. c4
			i = i + 3
		end

		return result
	end,
}

---Format memory response based on format
---@param response table GDB response lines
---@param format string Format type
---@param address string Memory address
---@param size number Number of bytes
---@return table Formatted content lines
local function format_memory_response(response, format, address, size)
	local formatted = {
		string.format("✓ Memory at %s (%d bytes, %s format):", address, size, format),
		string.rep("─", 70),
	}

	if format == "base64" then
		-- Extract all bytes for base64
		local all_bytes = {}
		for _, line in ipairs(response) do
			if line and not line:match("^%(gdb%)") then
				for hex_byte in line:gmatch("0x(%x%x)") do
					local byte_val = tonumber(hex_byte, 16)
					if byte_val then
						table.insert(all_bytes, byte_val)
					end
				end
			end
		end

		local base64_str = format_handlers.base64(all_bytes)
		for i = 1, #base64_str, 64 do
			local chunk = base64_str:sub(i, i + 63)
			table.insert(formatted, string.format("%04d: %s", i - 1, chunk))
		end

		return formatted
	end

	-- Format line by line for other formats
	for _, line in ipairs(response) do
		if line and not line:match("^%(gdb%)") then
			local addr_match = line:match("(0x%x+):")
			if addr_match then
				local data_part = line:match("0x%x+:%s*(.+)")
				if data_part then
					local bytes = {}
					for hex_byte in data_part:gmatch("0x(%x%x)") do
						local byte_val = tonumber(hex_byte, 16)
						if byte_val then
							table.insert(bytes, byte_val)
						end
					end

					local formatted_values = format_handlers[format](bytes)
					local ascii = table.concat(vim.tbl_map(function(b)
						return (b >= 32 and b <= 126) and string.char(b) or "."
					end, bytes))

					local formatted_line = string.format("%-18s %-48s |%s|", addr_match .. ":", formatted_values, ascii)
					table.insert(formatted, formatted_line)
				end
			end
		end
	end

	return formatted
end

-- Window management unified
---@class WindowOpts
---@field window_type string "popup" or "split"
---@field border? string Border style for popup
---@field width? number Window width
---@field height? number Window height

---Create window (popup or split) with unified logic
---@param content table Content lines
---@param opts WindowOpts Window options
---@param is_error? boolean Whether this is an error display
---@return number|nil, number|nil Window and buffer handles
local function create_window(content, opts, is_error)
	opts = opts or {}
	local window_type = opts.window_type or "split"
	is_error = is_error or false

	-- Create buffer
	local buf = vim.api.nvim_create_buf(false, true)
	if not buf then
		vim.notify("Failed to create buffer", vim.log.levels.ERROR)
		return nil, nil
	end

	-- Set buffer content and options
	pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, content or {})
	pcall(function()
		vim.bo[buf].bufhidden = "wipe"
		vim.bo[buf].buftype = "nofile"
		vim.bo[buf].swapfile = false
		vim.bo[buf].modifiable = false
		vim.bo[buf].filetype = is_error and "text" or "xxd"
	end)

	local win
	if window_type == "popup" then
		win = create_popup_win(buf, opts, content)
	else
		win = create_split_win(buf, opts)
	end

	if not win then
		vim.api.nvim_buf_delete(buf, { force = true })
		return nil, nil
	end

	-- Set up keymaps
	setup_window_keymaps(buf, window_type, is_error)

	return win, buf
end

---Create popup window
---@param buf number Buffer handle
---@param opts table Options
---@param content table Content for sizing
---@return number|nil Window handle
function create_popup_win(buf, opts, content)
	-- Calculate size
	local max_width = 0
	for _, line in ipairs(content) do
		max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
	end

	local width = math.min(120, math.max(60, max_width + 4))
	local height = math.min(25, math.max(5, #content + 2))

	-- Position
	local cursor_pos = vim.api.nvim_win_get_cursor(0)
	local row = cursor_pos[1] + height + 3 > vim.o.lines and -(height + 1) or 1
	local col = cursor_pos[2] + width > vim.o.columns and -(width - 10) or 0

	local win_opts = {
		relative = "cursor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = opts.border or "rounded",
		focusable = true,
		zindex = 50,
	}

	local ok, win = pcall(vim.api.nvim_open_win, buf, false, win_opts)
	return ok and win or nil
end

---Create split window
---@param buf number Buffer handle
---@param opts table Options
---@return number|nil Window handle
function create_split_win(buf, opts)
	local height = opts.height or 20
	local ok = pcall(vim.cmd, "botright " .. height .. "split")
	if not ok then
		return nil
	end

	local win = vim.api.nvim_get_current_win()
	local ok = pcall(vim.api.nvim_win_set_buf, win, buf)
	return ok and win or nil
end

---Setup window keymaps
---@param buf number Buffer handle
---@param window_type string "popup" or "split"
---@param is_error boolean Whether this is error window
function setup_window_keymaps(buf, window_type, is_error)
	local keymaps = {
		["q"] = "close",
		["<Esc>"] = "close",
	}

	if not is_error then
		vim.tbl_extend("force", keymaps, {
			["r"] = "refresh",
			["e"] = "edit",
			["s"] = "save_register",
			["S"] = "save_buffer",
			["c"] = "compare",
			["h"] = "format_hex",
			["d"] = "format_decimal",
			["b"] = "format_binary",
			["6"] = "format_base64",
			["f"] = "cycle_format",
			["+"] = "nav_forward",
			["-"] = "nav_backward",
		})
	end

	for key, action in pairs(keymaps) do
		pcall(vim.api.nvim_buf_set_keymap, buf, "n", key, "", {
			callback = function()
				handle_keymap_action(action, window_type)
			end,
			noremap = true,
			silent = true,
		})
	end
end

---Handle keymap actions
---@param action string Action name
---@param window_type string Window type
function handle_keymap_action(action, window_type)
	local actions = {
		close = function()
			if window_type == "popup" then
				cleanup_popup_window()
			else
				cleanup_memory_window()
			end
		end,
		refresh = function()
			M.refresh_memory()
		end,
		edit = function()
			M.edit_memory_interactive()
		end,
		save_register = function()
			M.save_memory_to_register()
		end,
		save_buffer = function()
			M.save_memory_to_buffer()
		end,
		compare = function()
			M.compare_memory_with_register()
		end,
		format_hex = function()
			M.set_format("hex")
		end,
		format_decimal = function()
			M.set_format("decimal")
		end,
		format_binary = function()
			M.set_format("binary")
		end,
		format_base64 = function()
			M.set_format("base64")
		end,
		cycle_format = function()
			M.switch_format()
		end,
		nav_forward = function()
			M.navigate_memory(16)
		end,
		nav_backward = function()
			M.navigate_memory(-16)
		end,
	}

	if actions[action] then
		actions[action]()
	end
end

-- Cleanup functions
---Unified cleanup function for windows and buffers
---@param win_ref number|nil Window handle
---@param buf_ref number|nil Buffer handle
---@return nil, nil Always returns nil for both values
local function cleanup_window(win_ref, buf_ref)
	if win_ref and vim.api.nvim_win_is_valid(win_ref) then
		pcall(vim.api.nvim_win_close, win_ref, true)
	end
	if buf_ref and vim.api.nvim_buf_is_valid(buf_ref) then
		pcall(vim.api.nvim_buf_delete, buf_ref, { force = true })
	end
	return nil, nil
end

function cleanup_memory_window()
	memory_win, memory_buf = cleanup_window(memory_win, memory_buf)
end

function cleanup_popup_window()
	popup_win, popup_buf = cleanup_window(popup_win, popup_buf)
end

-- Helper functions for editing
local function edit_memory_bytes(address, bytes_str)
	local byte_list = {}
	for byte in bytes_str:gmatch("%S+") do
		-- Basic hex validation
		local normalized = byte:gsub("^0x", "")
		if normalized:match("^%x+$") and #normalized <= 2 then
			table.insert(byte_list, "0x" .. normalized)
		else
			show_error("Invalid hex value: " .. byte)
			return
		end
	end

	if #byte_list == 0 then
		return
	end

	local completed = 0
	local total = #byte_list
	local errors = {}

	for i, byte in ipairs(byte_list) do
		local addr = string.format("(char*)(%s)+%d", address, i - 1)
		utils.async_gdb_response(string.format("set *%s = %s", addr, byte), function(_, error)
			completed = completed + 1
			if error then
				table.insert(errors, string.format("Offset %d: %s", i - 1, error))
			end

			if completed == total then
				if #errors == 0 then
					vim.notify("Successfully wrote " .. total .. " bytes", vim.log.levels.INFO)
				else
					show_error(string.format("Completed with %d errors: %s", #errors, table.concat(errors, "; ")))
				end
				if current_memory.address then
					vim.defer_fn(function()
						M.refresh_memory()
					end, 200)
				end
			end
		end)
	end
end

local function edit_variable_value(variable, value)
	utils.async_gdb_response("set variable " .. variable .. " = " .. value, function(_, error)
		if error then
			show_error("Failed to set variable: " .. error)
		else
			-- Verify the change
			utils.async_gdb_response("print " .. variable, function(response, _)
				if response then
					local val = response[1] and response[1]:match("= (.+)")
					if val then
						vim.notify(variable .. " = " .. val, vim.log.levels.INFO)
					else
						vim.notify("Variable " .. variable .. " updated", vim.log.levels.INFO)
					end
				else
					vim.notify("Variable " .. variable .. " updated", vim.log.levels.INFO)
				end
			end)
		end
	end)
end

-- Simplified wrapper functions for window creation
function create_memory_window(content, opts, is_error)
	cleanup_memory_window()
	local win, buf = create_window(content, vim.tbl_extend("force", opts or {}, { window_type = "split" }), is_error)
	memory_win, memory_buf = win, buf
	return win, buf
end

function create_popup_window(content, opts, is_error)
	cleanup_popup_window()
	local win, buf = create_window(content, vim.tbl_extend("force", opts or {}, { window_type = "popup" }), is_error)
	popup_win, popup_buf = win, buf
	return win, buf
end

-- Public API - much simplified now
function M.show_memory(address, size)
	return with_validation({
		validators.gdb_available,
		function()
			return validators.valid_address(address)
		end,
	}, function()
		size = size or current_memory.size
		current_memory.address = address
		current_memory.size = size

		memory_ops.get_data(address, size, function(response, error)
			if error then
				show_error_window({ type = "access_denied", message = error, address = address })
				return
			end

			local formatted = format_memory_response(response, current_memory.format, address, size)
			create_memory_window(formatted, config.get_memory_viewer(), false)
		end)
	end, "show_memory")
end

function M.view_memory_at_cursor()
	local word = vim.fn.expand("<cexpr>")
	if word == "" then
		word = vim.fn.expand("<cword>")
	end
	if word == "" then
		local ok, input = pcall(vim.fn.input, "Memory address or variable: ")
		if not ok or input == "" then
			return
		end
		word = input
	end

	current_memory.variable = word

	if word:match("^0x%x+") or word:match("^%d+") then
		M.show_memory(word, current_memory.size)
	else
		memory_ops.resolve_address(word, function(addr, error)
			if error then
				show_error_window({ type = "access_denied", message = error, address = word })
				return
			end
			M.show_memory(addr, current_memory.size)
		end)
	end
end

function M.show_memory_popup(address, size)
	-- Similar to show_memory but uses popup window
	return with_validation({
		validators.gdb_available,
		function()
			return address and validators.valid_address(address) or true
		end,
	}, function()
		if not address then
			-- Get from cursor like view_memory_at_cursor but shorter
			local word = vim.fn.expand("<cexpr>") or vim.fn.expand("<cword>")
			if word == "" then
				vim.notify("No variable or address under cursor", vim.log.levels.WARN)
				return
			end
			address = word
		end

		size = size or 64 -- Smaller default for popups
		current_memory.address = address
		current_memory.size = size

		memory_ops.get_data(address, size, function(response, error)
			if error then
				show_error_window({ type = "access_denied", message = error, address = address }, "popup")
				return
			end

			local formatted = format_memory_response(response, current_memory.format, address, size)
			create_popup_window(formatted, {}, false)
		end)
	end, "show_memory_popup")
end

function M.set_format(format)
	return with_validation({
		function()
			return validators.valid_format(format)
		end,
		validators.has_active_memory,
	}, function()
		current_memory.format = format
		M.show_memory(current_memory.address, current_memory.size)
		vim.notify("Memory format: " .. format, vim.log.levels.INFO)
	end, "set_format")
end

function M.switch_format()
	return with_validation({ validators.has_active_memory }, function()
		local current_idx = 1
		for i, fmt in ipairs(VALID_FORMATS) do
			if current_memory.format == fmt then
				current_idx = i
				break
			end
		end
		local next_format = VALID_FORMATS[(current_idx % #VALID_FORMATS) + 1]
		M.set_format(next_format)
	end, "switch_format")
end

function M.navigate_memory(offset)
	return with_validation({ validators.has_active_memory }, function()
		local addr_num = tonumber(current_memory.address:match("0x(%x+)"), 16)
		if not addr_num then
			show_error("Cannot parse current address for navigation")
			return
		end

		local new_addr = addr_num + offset
		if new_addr < 0 then
			show_error("Cannot navigate to negative address")
			return
		end

		current_memory.address = string.format("0x%x", new_addr)
		M.show_memory(current_memory.address, current_memory.size)
	end, "navigate_memory")
end

function M.refresh_memory()
	return with_validation({ validators.has_active_memory }, function()
		M.show_memory(current_memory.address, current_memory.size)
	end, "refresh_memory")
end

function M.edit_memory_at_cursor()
	local word = vim.fn.expand("<cexpr>")
	if word == "" then
		word = vim.fn.expand("<cword>")
	end
	if word == "" then
		local ok, input = pcall(vim.fn.input, "Variable or address to edit: ")
		if not ok or input == "" then
			return
		end
		word = input
	end

	return with_validation({
		validators.gdb_available,
		function()
			return validators.valid_address(word)
		end,
	}, function()
		if word:match("^0x%x+") or word:match("^%d+") then
			-- Memory address editing
			local ok, bytes = pcall(vim.fn.input, "Enter bytes (hex, space-separated): ")
			if ok and bytes ~= "" then
				edit_memory_bytes(word, bytes)
			end
		else
			-- Variable editing
			local ok, value = pcall(vim.fn.input, "Set " .. word .. " = ")
			if ok and value ~= "" then
				edit_variable_value(word, value)
			end
		end
	end, "edit_memory")
end

function M.edit_memory_interactive()
	return with_validation({ validators.has_active_memory, validators.gdb_available }, function()
		local ok_offset, offset = pcall(vim.fn.input, "Offset from " .. current_memory.address .. ": ")
		if not ok_offset then
			return
		end
		offset = offset == "" and "0" or offset

		if not offset:match("^%-?%d+$") then
			show_error("Invalid offset format. Use a number (e.g., 0, 16, -8)")
			return
		end

		local ok_value, value = pcall(vim.fn.input, "Value (hex): 0x")
		if not ok_value or value == "" then
			return
		end

		local addr = string.format("(char*)(%s)+%s", current_memory.address, offset)
		utils.async_gdb_response(string.format("set *%s = 0x%s", addr, value), function(_, error)
			if error then
				show_error("Failed to update memory: " .. error)
			else
				vim.notify("Memory updated at offset " .. offset, vim.log.levels.INFO)
				vim.defer_fn(function()
					M.refresh_memory()
				end, 200)
			end
		end)
	end, "edit_memory_interactive")
end

function M.save_memory_to_register(register)
	return with_validation({ validators.has_active_memory }, function()
		register = register or "m"

		memory_ops.get_data(current_memory.address, current_memory.size, function(response, error)
			if error then
				show_error("Failed to get memory for saving: " .. error)
				return
			end

			local content_lines = {
				string.format(
					"Memory dump: %s (%d bytes) - %s",
					current_memory.address,
					current_memory.size,
					os.date("%Y-%m-%d %H:%M:%S")
				),
			}

			for _, line in ipairs(response) do
				if line and not line:match("^%(gdb%)") then
					table.insert(content_lines, line)
				end
			end

			vim.fn.setreg(register, table.concat(content_lines, "\n"))
			vim.notify(string.format("Memory saved to register '%s'", register), vim.log.levels.INFO)
		end)
	end, "save_memory_to_register")
end

function M.save_memory_to_buffer(buffer_name)
	return with_validation({ validators.has_active_memory }, function()
		buffer_name = buffer_name
			or string.format("memory_%s_%s.hex", current_memory.address:gsub("0x", ""), os.date("%H%M%S"))

		memory_ops.get_data(current_memory.address, current_memory.size, function(response, error)
			if error then
				show_error("Failed to get memory for saving: " .. error)
				return
			end

			local buf = vim.api.nvim_create_buf(true, false)
			if not buf then
				show_error("Failed to create buffer")
				return
			end

			local content_lines = {
				"# Memory Dump",
				"# Address: " .. current_memory.address,
				"# Size: " .. current_memory.size .. " bytes",
				"# Variable: " .. (current_memory.variable or "N/A"),
				"# Timestamp: " .. os.date("%Y-%m-%d %H:%M:%S"),
				"#",
				"",
			}

			-- Add formatted memory content
			local formatted =
				format_memory_response(response, current_memory.format, current_memory.address, current_memory.size)
			for i = 3, #formatted do -- Skip header lines
				table.insert(content_lines, formatted[i])
			end

			vim.api.nvim_buf_set_lines(buf, 0, -1, false, content_lines)
			vim.api.nvim_buf_set_name(buf, buffer_name)
			vim.bo[buf].filetype = "xxd"
			vim.bo[buf].modified = false

			vim.cmd("split")
			vim.api.nvim_win_set_buf(0, buf)

			vim.notify(string.format("Memory saved to buffer '%s'", buffer_name), vim.log.levels.INFO)
		end)
	end, "save_memory_to_buffer")
end

function M.compare_memory_with_register(register)
	return with_validation({ validators.has_active_memory }, function()
		register = register or "m"
		local saved_content = vim.fn.getreg(register)

		if not saved_content or saved_content == "" then
			show_error(string.format("Register '%s' is empty", register))
			return
		end

		memory_ops.get_data(current_memory.address, current_memory.size, function(response, error)
			if error then
				show_error("Failed to get current memory: " .. error)
				return
			end

			local current_lines =
				format_memory_response(response, current_memory.format, current_memory.address, current_memory.size)

			local buf = vim.api.nvim_create_buf(true, false)
			if not buf then
				show_error("Failed to create comparison buffer")
				return
			end

			local content = {
				string.rep("=", 60),
				"SAVED CONTENT (from register '" .. register .. "'):",
				string.rep("=", 60),
				"",
			}

			-- Add saved content
			for _, line in ipairs(vim.split(saved_content, "\n")) do
				table.insert(content, line)
			end

			-- Add current content
			table.insert(content, "")
			table.insert(content, string.rep("=", 60))
			table.insert(content, "CURRENT CONTENT:")
			table.insert(content, string.rep("=", 60))
			table.insert(content, "")

			for _, line in ipairs(current_lines) do
				table.insert(content, line)
			end

			vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
			vim.api.nvim_buf_set_name(buf, string.format("memory_comparison_%s.diff", register))
			vim.bo[buf].filetype = "diff"
			vim.bo[buf].modified = false

			vim.cmd("split")
			vim.api.nvim_win_set_buf(0, buf)

			vim.notify(string.format("Memory comparison with register '%s' opened", register), vim.log.levels.INFO)
		end)
	end, "compare_memory")
end

function M.diff_memory_buffers(buffer1, buffer2)
	local buffers = vim.api.nvim_list_bufs()
	local buf1, buf2 = nil, nil

	for _, buf in ipairs(buffers) do
		local name = vim.api.nvim_buf_get_name(buf)
		if name:match(buffer1) then
			buf1 = buf
		elseif name:match(buffer2) then
			buf2 = buf
		end
	end

	if not buf1 then
		show_error("Buffer matching '" .. buffer1 .. "' not found")
		return
	end
	if not buf2 then
		show_error("Buffer matching '" .. buffer2 .. "' not found")
		return
	end

	vim.cmd("tabnew")
	vim.api.nvim_win_set_buf(0, buf1)
	vim.cmd("diffthis")
	vim.cmd("vertical split")
	vim.api.nvim_win_set_buf(0, buf2)
	vim.cmd("diffthis")

	vim.notify("Memory buffers opened in diff mode", vim.log.levels.INFO)
end

function M.cleanup_all_windows()
	cleanup_memory_window()
	cleanup_popup_window()
end

return M

