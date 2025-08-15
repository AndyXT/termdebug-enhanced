---@class MemoryState
---@field address string|nil Current memory address
---@field size number Number of bytes to display
---@field variable string|nil Variable name if applicable

---@class MemoryError
---@field type string Error type (invalid_address, access_denied, gdb_unavailable, timeout)
---@field message string Human-readable error message
---@field address string|nil The address that caused the error

---@class termdebug-enhanced.memory
---@field view_memory_at_cursor function View memory at cursor position
---@field show_memory function Display memory in hex viewer
---@field navigate_memory function Navigate memory by offset
---@field edit_memory_at_cursor function Edit memory/variable at cursor
---@field show_memory_popup function Show memory in popup window
---@field save_memory_to_register function Save hex dump to register
---@field save_memory_to_buffer function Save hex dump to buffer
---@field compare_memory_with_register function Compare current memory with register
---@field diff_memory_buffers function Open two memory buffers in diff mode
local M = {}

local utils = require("termdebug-enhanced.utils")

---@type number|nil
local memory_win = nil
---@type number|nil
local memory_buf = nil

-- Popup window cache
---@type number|nil
local popup_win = nil
---@type number|nil
local popup_buf = nil

---Get memory viewer configuration safely with fallback defaults
---
---Attempts to load the memory viewer configuration from the main plugin config,
---falling back to sensible defaults if the configuration is not available.
---This ensures the memory viewer can function even during early initialization.
---
---@return table Memory viewer configuration with width, height, format, and bytes_per_line
local function get_config()
  local ok, main = pcall(require, "termdebug-enhanced")
  if ok and main and type(main) == "table" and main.config and type(main.config) == "table" then
    -- Check if memory_viewer config exists, otherwise use defaults
    if main.config.memory_viewer and type(main.config.memory_viewer) == "table" then
      return vim.tbl_deep_extend("force", {
        width = 80,
        height = 20,
        format = "hex",
        bytes_per_line = 16,
      }, main.config.memory_viewer)
    end
  end
  -- Return default config if not initialized
  return {
    width = 80,
    height = 20,
    format = "hex",
    bytes_per_line = 16,
  }
end

---Validate memory address format and syntax
---
---Validates that a memory address string is in a format that GDB can understand.
---Supports hexadecimal addresses (0x1234), decimal addresses (1234), and
---variable names that can be resolved to addresses.
---
---Supported formats:
---- Hexadecimal: 0x1234, 0xABCD, etc.
---- Decimal: 1234, 5678, etc.
---- Variable names: main, buffer, ptr, etc.
---
---@param addr string Address to validate
---@return boolean valid, string|nil error_msg
local function validate_address(addr)
	if not addr or addr == "" then
		return false, "Empty address"
	end

	local trimmed = vim.trim(addr)
	if trimmed == "" then
		return false, "Address contains only whitespace"
	end

	-- Check for hex address format
	if trimmed:match("^0x%x+$") then
		return true, nil
	end

	-- Check for decimal address
	if trimmed:match("^%d+$") then
		return true, nil
	end

	-- Check for variable name (basic validation)
	if trimmed:match("^[%a_][%w_]*$") then
		return true, nil
	end

	return false, "Invalid address format. Use hex (0x1234), decimal (1234), or variable name"
end

---Validate hex value for memory editing operations
---
---Validates that a hex value string is properly formatted for memory editing.
---Ensures the value contains only valid hexadecimal digits and is within
---reasonable length limits for typical memory operations.
---
---Validation includes:
---- Proper hex digit format (0-9, A-F)
---- Optional 0x prefix handling
---- Length limits (max 8 digits for 32-bit values)
---- Empty value detection
---
---@param hex_str string Hex value to validate
---@return boolean valid, string|nil error_msg
local function validate_hex_value(hex_str)
	if not hex_str or hex_str == "" then
		return false, "Empty hex value"
	end

	local trimmed = vim.trim(hex_str)
	if trimmed == "" then
		return false, "Hex value contains only whitespace"
	end

	-- Remove 0x prefix if present
	local hex_part = trimmed:gsub("^0x", "")

	-- Check if it's valid hex
	if not hex_part:match("^%x+$") then
		return false, "Invalid hex format. Use hex digits (0-9, A-F)"
	end

	-- Check reasonable length (1-8 hex digits for 32-bit values)
	if #hex_part > 8 then
		return false, "Hex value too long (max 8 digits for 32-bit)"
	end

	return true, nil
end

-- Check if GDB is available for memory operations
---@return boolean available, string|nil error_msg
local function check_memory_gdb_availability()
	if vim.fn.exists(":Termdebug") == 0 then
		return false, "Termdebug not available. Run :packadd termdebug"
	end

	if not vim.g.termdebug_running then
		return false, "Debug session not active. Start debugging first"
	end

	return true, nil
end

-- Create error display for memory operations
---@param error_info MemoryError Error information
---@return string[] Formatted error content
local function create_memory_error_content(error_info)
	local content = {
		"❌ Memory Error",
		string.rep("─", 50),
	}

	if error_info.address then
		table.insert(content, "Address: " .. error_info.address)
		table.insert(content, "")
	end

	local message = error_info.message or "Unknown memory error"
	table.insert(content, "Error: " .. message)

	-- Add helpful hints based on error type
	if error_info.type == "invalid_address" then
		table.insert(content, "")
		table.insert(content, "💡 Hint: Check address format (0x1234 or variable name)")
	elseif error_info.type == "access_denied" then
		table.insert(content, "")
		table.insert(content, "💡 Hint: Address may be protected or invalid")
	elseif error_info.type == "gdb_unavailable" then
		table.insert(content, "")
		table.insert(content, "💡 Hint: Start debugging session first")
	elseif error_info.type == "timeout" then
		table.insert(content, "")
		table.insert(content, "💡 Hint: Memory operation timed out")
	end

	return content
end

-- Clean up memory window resources with proper tracking
---@return nil
local function cleanup_memory_window()
	if memory_win and vim.api.nvim_win_is_valid(memory_win) then
		local ok, err = pcall(vim.api.nvim_win_close, memory_win, true)
		if not ok then
			vim.notify("Failed to close memory window: " .. tostring(err), vim.log.levels.WARN)
		end
		pcall(utils.untrack_resource, "mem_win_" .. tostring(memory_win))
	end
	if memory_buf and vim.api.nvim_buf_is_valid(memory_buf) then
		local ok, err = pcall(vim.api.nvim_buf_delete, memory_buf, { force = true })
		if not ok then
			vim.notify("Failed to delete memory buffer: " .. tostring(err), vim.log.levels.WARN)
		end
		pcall(utils.untrack_resource, "mem_buf_" .. tostring(memory_buf))
	end
	memory_win = nil
	memory_buf = nil
end

-- Clean up popup window resources
---@return nil
local function cleanup_popup_window()
	if popup_win and vim.api.nvim_win_is_valid(popup_win) then
		local ok, err = pcall(vim.api.nvim_win_close, popup_win, true)
		if not ok then
			vim.notify("Failed to close popup window: " .. tostring(err), vim.log.levels.WARN)
		end
		pcall(utils.untrack_resource, "popup_win_" .. tostring(popup_win))
	end
	if popup_buf and vim.api.nvim_buf_is_valid(popup_buf) then
		local ok, err = pcall(vim.api.nvim_buf_delete, popup_buf, { force = true })
		if not ok then
			vim.notify("Failed to delete popup buffer: " .. tostring(err), vim.log.levels.WARN)
		end
		pcall(utils.untrack_resource, "popup_buf_" .. tostring(popup_buf))
	end
	popup_win = nil
	popup_buf = nil
end

---Create memory viewer window
---@param content string[] Content to display
---@param opts table|nil Window options
---@param is_error boolean|nil Whether this is an error display
---@return number|nil, number|nil Window and buffer handles
local function create_memory_window(content, opts, is_error)
	opts = opts or {}
	is_error = is_error or false

	-- Close existing window if any
	cleanup_memory_window()

	-- Create buffer for content
	local buf_ok, buf = pcall(vim.api.nvim_create_buf, false, true)
	if not buf_ok then
		vim.notify("Failed to create memory buffer: " .. tostring(buf), vim.log.levels.ERROR)
		return nil, nil
	end
	memory_buf = buf

	-- Track buffer for cleanup (with safe loading)
	local track_buf_ok = pcall(function()
		utils.track_resource("mem_buf_" .. tostring(buf), "buffer", buf, function(b)
			if vim.api.nvim_buf_is_valid(b) then
				vim.api.nvim_buf_delete(b, { force = true })
			end
		end)
	end)
	if not track_buf_ok then
		-- Fallback: manual cleanup will be handled by cleanup_memory_window function
		vim.notify("Resource tracking unavailable for memory buffer", vim.log.levels.DEBUG)
	end

	local content_ok, content_err = pcall(vim.api.nvim_buf_set_lines, memory_buf, 0, -1, false, content or {})
	if not content_ok then
		vim.notify("Failed to set memory buffer content: " .. tostring(content_err), vim.log.levels.ERROR)
		cleanup_memory_window()
		return nil, nil
	end

	-- Calculate window size
	local height = opts.height or 20

	-- Create split window with error handling
	local split_ok, split_err = pcall(vim.cmd, "botright " .. height .. "split")
	if not split_ok then
		vim.notify("Failed to create memory window: " .. tostring(split_err), vim.log.levels.ERROR)
		cleanup_memory_window()
		return nil, nil
	end

	memory_win = vim.api.nvim_get_current_win()

	-- Track window for cleanup (with safe loading)
	local track_win_ok = pcall(function()
		utils.track_resource("mem_win_" .. tostring(memory_win), "window", memory_win, function(w)
			if vim.api.nvim_win_is_valid(w) then
				vim.api.nvim_win_close(w, true)
			end
		end)
	end)
	if not track_win_ok then
		-- Fallback: manual cleanup will be handled by cleanup_memory_window function
		vim.notify("Resource tracking unavailable for memory window", vim.log.levels.DEBUG)
	end

	local set_buf_ok, set_buf_err = pcall(vim.api.nvim_win_set_buf, memory_win, memory_buf)
	if not set_buf_ok then
		vim.notify("Failed to set memory window buffer: " .. tostring(set_buf_err), vim.log.levels.ERROR)
		cleanup_memory_window()
		return nil, nil
	end

	-- Set buffer options (using modern API with error handling)
	pcall(function()
		vim.bo[memory_buf].bufhidden = "wipe"
		vim.bo[memory_buf].buftype = "nofile"
		vim.bo[memory_buf].swapfile = false
		vim.bo[memory_buf].modifiable = false
	end)

	pcall(vim.api.nvim_buf_set_name, memory_buf, is_error and "Memory Error" or "Memory Viewer")

	-- Add syntax highlighting
	pcall(function()
		vim.bo[memory_buf].filetype = is_error and "text" or "xxd"
	end)

	if not is_error then
		-- Add keybindings for the memory window (only for non-error windows)
		local keymaps = {
			["q"] = function()
				cleanup_memory_window()
			end,
			["<Esc>"] = function()
				cleanup_memory_window()
			end,
			["r"] = function()
				M.refresh_memory()
			end,
			["e"] = function()
				M.edit_memory_interactive()
			end,
			["c"] = function()
				M.compare_memory_with_register()
			end,
			["+"] = function()
				M.navigate_memory(16)
			end,
			["-"] = function()
				M.navigate_memory(-16)
			end,
			["<PageDown>"] = function()
				M.navigate_memory(256)
			end,
			["<PageUp>"] = function()
				M.navigate_memory(-256)
			end,
		}

		for key, func in pairs(keymaps) do
			pcall(vim.api.nvim_buf_set_keymap, memory_buf, "n", key, "", {
				callback = func,
				noremap = true,
				silent = true,
			})
		end

		-- Add help text at the top
		local help_text = {
			"── Memory Viewer ──────────────────────────────────────────────",
			"  q/<Esc>: close | r: refresh | e: edit | c: compare | +/-: navigate",
			"  PgUp/PgDn: page",
			"───────────────────────────────────────────────────────────────",
			"",
		}
		pcall(vim.api.nvim_buf_set_lines, memory_buf, 0, 0, false, help_text)
	else
		-- For error windows, just add close keybindings
		local error_keymaps = {
			["q"] = function()
				cleanup_memory_window()
			end,
			["<Esc>"] = function()
				cleanup_memory_window()
			end,
		}

		for key, func in pairs(error_keymaps) do
			pcall(vim.api.nvim_buf_set_keymap, memory_buf, "n", key, "", {
				callback = func,
				noremap = true,
				silent = true,
			})
		end
	end

	return memory_win, memory_buf
end

-- Store current memory view state
---@type MemoryState
local current_memory = {
	address = nil,
	size = 256,
	variable = nil,
}

---Parse memory address string to number
---
---Converts various address formats to numeric values for memory operations.
---Supports hexadecimal (0x1234), decimal (1234), and direct numeric inputs.
---
---@param addr_str string|number Address string or number
---@return number|nil Parsed address as number
local function parse_address(addr_str)
	if type(addr_str) == "number" then
		return addr_str
	end

	if type(addr_str) == "string" then
		if addr_str:match("^0x") then
			local hex = addr_str:match("^0x(%x+)")
			return hex and tonumber(hex, 16) or nil
		end
		return tonumber(addr_str)
	end
	
	return nil
end

---View memory at cursor position
---
---Displays memory contents for the variable or address under the cursor in a
---dedicated memory viewer window. This function automatically detects whether
---the cursor is on a variable name or a memory address and handles both cases.
---
---For variable names, it first resolves the variable's address using GDB's
---"print &variable" command, then displays the memory at that address.
---For direct addresses, it immediately displays the memory contents.
---
---Features:
---- Automatic variable address resolution
---- Support for hex and decimal addresses
---- Interactive memory viewer with navigation
---- Error handling with helpful messages
---
---@return nil
function M.view_memory_at_cursor()
	-- Check GDB availability first
	local available, availability_error = check_memory_gdb_availability()
	if not available then
		local error_content = create_memory_error_content({
			type = "gdb_unavailable",
			message = availability_error,
			address = nil,
		})
		local config = get_config()
		create_memory_window(error_content, config, true)
		return
	end

	local word = vim.fn.expand("<cexpr>")
	if word == "" then
		word = vim.fn.expand("<cword>")
	end

	if word == "" then
		-- Ask for address with error handling
		local input_ok, input_word = pcall(vim.fn.input, "Memory address or variable: ")
		if not input_ok then
			vim.notify("Failed to get input", vim.log.levels.ERROR)
			return
		end
		word = input_word
		if word == "" then
			return
		end
	end

	-- Validate the address/variable
	local valid, validation_error = validate_address(word)
	if not valid then
		local error_content = create_memory_error_content({
			type = "invalid_address",
			message = validation_error,
			address = word,
		})
		local config = get_config()
		create_memory_window(error_content, config, true)
		return
	end

	current_memory.variable = word

	-- Get address of variable or use direct address
	if word:match("^0x%x+") or word:match("^%d+") then
		-- Direct address
		current_memory.address = word
		M.show_memory(current_memory.address, current_memory.size)
	else
		-- Variable name - get its address first
		utils.async_gdb_response("print &" .. word, function(response, error)
			if error then
				local error_content = create_memory_error_content({
					type = "access_denied",
					message = "Could not get address: " .. error,
					address = word,
				})
				local config = get_config()
				create_memory_window(error_content, config, true)
				return
			end

			-- Extract address from response
			local addr = nil
			if response and #response > 0 then
				for _, line in ipairs(response) do
					addr = line:match("0x%x+")
					if addr then
						break
					end
				end
			end

			if addr then
				current_memory.address = addr
				M.show_memory(addr, current_memory.size)
			else
				local error_content = create_memory_error_content({
					type = "access_denied",
					message = "Could not get address for variable (may not be in scope)",
					address = word,
				})
				local config = get_config()
				create_memory_window(error_content, config, true)
			end
		end, { timeout = 3000 })
		return
	end
end

---Show memory contents in hex viewer
---
---Displays memory contents at the specified address in a formatted hex viewer.
---The viewer supports different display formats (hex, decimal, binary) and
---provides an interactive interface for navigation and editing.
---
---The function sends appropriate GDB commands based on the configured format:
---- Hex format: "x/NNxb address" for hexadecimal byte display
---- Decimal format: "x/NNdb address" for decimal byte display
---- Binary format: "x/NNtb address" for binary byte display
---
---@param address string Memory address to display
---@param size number Number of bytes to show
function M.show_memory(address, size)
	if not address then
		local error_content = create_memory_error_content({
			type = "invalid_address",
			message = "No address specified",
			address = nil,
		})
		local config = get_config()
		create_memory_window(error_content, config, true)
		return
	end

	-- Validate address
	local valid, validation_error = validate_address(address)
	if not valid then
		local error_content = create_memory_error_content({
			type = "invalid_address",
			message = validation_error,
			address = address,
		})
		local config = get_config()
		create_memory_window(error_content, config, true)
		return
	end

	-- Check GDB availability
	local available, availability_error = check_memory_gdb_availability()
	if not available then
		local error_content = create_memory_error_content({
			type = "gdb_unavailable",
			message = availability_error,
			address = address,
		})
		local config = get_config()
		create_memory_window(error_content, config, true)
		return
	end

	local config = get_config()
	local format = config.format or "hex"
	size = size or current_memory.size

	-- Update current memory state immediately (before async call)
	current_memory.address = address
	current_memory.size = size

	-- Send memory examination command
	local cmd
	if format == "hex" then
		cmd = string.format("x/%dxb %s", size, address)
	elseif format == "decimal" then
		cmd = string.format("x/%ddb %s", size, address)
	else -- binary
		cmd = string.format("x/%dtb %s", size, address)
	end

	-- Use async response handler
	utils.async_gdb_response(cmd, function(response, error)
		if error then
			local error_type = "access_denied"
			local error_msg = error

			-- Categorize error types
			if error:match("[Tt]imeout") then
				error_type = "timeout"
				error_msg = "Memory read timeout - address may be invalid"
			elseif error:match("[Ii]nvalid") or error:match("[Cc]annot access") then
				error_type = "access_denied"
				error_msg = "Cannot access memory at address (may be protected or invalid)"
			end

			local error_content = create_memory_error_content({
				type = error_type,
				message = error_msg,
				address = address,
			})
			create_memory_window(error_content, config, true)
			return
		end

		if response and #response > 0 then
			-- Check if response indicates an error
			local response_text = table.concat(response, " ")
			if
				response_text:match("[Cc]annot access")
				or response_text:match("[Ii]nvalid")
				or response_text:match("[Ee]rror")
			then
				local error_content = create_memory_error_content({
					type = "access_denied",
					message = "Cannot access memory: " .. response_text,
					address = address,
				})
				create_memory_window(error_content, config, true)
				return
			end

			-- Enhanced header with more information
			local formatted = {
				string.format("✓ Memory at %s (%d bytes, %s format):", address, size, format),
				string.rep("─", 70),
			}

			-- Enhanced memory line formatting with address annotations
			local bytes_per_line = config.bytes_per_line or 16
			local current_addr = parse_address(address) or 0
			
			for _, line in ipairs(response) do
				if line and line ~= "" and not line:match("^%(gdb%)") then
					-- Try to extract address from GDB output and format consistently
					local addr_match = line:match("(0x%x+):")
					if addr_match then
						-- Format with consistent spacing and add ASCII representation for hex format
						if format == "hex" then
							local hex_part = line:match("0x%x+:%s*(.+)")
							if hex_part then
								-- Parse hex bytes and create ASCII representation
								local ascii = ""
								for hex_byte in hex_part:gmatch("0x(%x%x)") do
									local byte_val = tonumber(hex_byte, 16)
									if byte_val and byte_val >= 32 and byte_val <= 126 then
										ascii = ascii .. string.char(byte_val)
									else
										ascii = ascii .. "."
									end
								end
								
								-- Format line with proper spacing
								local formatted_line = string.format("%-18s %-48s |%s|", 
									addr_match .. ":", hex_part, ascii)
								table.insert(formatted, formatted_line)
							else
								table.insert(formatted, line)
							end
						else
							table.insert(formatted, line)
						end
					else
						table.insert(formatted, line)
					end
				end
			end

			-- Add navigation hints
			table.insert(formatted, "")
			table.insert(formatted, string.rep("─", 70))
			table.insert(formatted, "Navigation: +/- (16 bytes) | PgUp/PgDn (256 bytes) | r (refresh) | e (edit)")

			create_memory_window(formatted, config, false)
		else
			local error_content = create_memory_error_content({
				type = "access_denied",
				message = "No memory data returned (address may be invalid)",
				address = address,
			})
			create_memory_window(error_content, config, true)
		end
	end, { timeout = 5000, max_lines = 100 })
end

-- Note: parse_address function already defined above at line 376

---Navigate memory view by offset
---
---Moves the memory view by the specified byte offset from the current address.
---Positive offsets move forward in memory, negative offsets move backward.
---The function includes bounds checking to prevent navigation to invalid addresses.
---
---Common navigation patterns:
---- +16/-16: Navigate by one line (typical hex dump line)
---- +256/-256: Navigate by one page
---- +1/-1: Navigate by single byte
---
---@param offset number Byte offset to navigate (positive or negative)
---@return nil
function M.navigate_memory(offset)
	if not current_memory.address then
		vim.notify("No memory view active", vim.log.levels.WARN)
		return
	end

	-- Calculate new address with error handling
	local addr_num = parse_address(current_memory.address)

	if addr_num then
		local new_addr = addr_num + offset

		-- Check for address underflow
		if new_addr < 0 then
			vim.notify("Cannot navigate to negative address", vim.log.levels.WARN)
			return
		end

		current_memory.address = string.format("0x%x", new_addr)
		M.show_memory(current_memory.address, current_memory.size)
	else
		local error_content = create_memory_error_content({
			type = "invalid_address",
			message = "Cannot parse current address for navigation",
			address = current_memory.address,
		})
		local config = get_config()
		create_memory_window(error_content, config, true)
	end
end

---Refresh current memory view
---@return nil
function M.refresh_memory()
	if current_memory.address then
		M.show_memory(current_memory.address, current_memory.size)
	else
		local error_content = create_memory_error_content({
			type = "invalid_address",
			message = "No memory view active to refresh",
			address = nil,
		})
		local config = get_config()
		create_memory_window(error_content, config, true)
	end
end

---Edit memory or variable at cursor position
---
---Allows editing of memory contents or variable values at the cursor position.
---The function automatically detects whether the cursor is on a memory address
---or a variable name and provides appropriate editing interfaces.
---
---For memory addresses:
---- Prompts for hex bytes to write
---- Supports multiple byte editing with space-separated values
---- Validates hex input before writing
---
---For variables:
---- Prompts for new variable value
---- Uses GDB's "set variable" command
---- Shows updated value after successful change
---
---@return nil
function M.edit_memory_at_cursor()
	-- Check GDB availability first
	local available, availability_error = check_memory_gdb_availability()
	if not available then
		vim.notify(availability_error, vim.log.levels.ERROR)
		return
	end

	local word = vim.fn.expand("<cexpr>")
	if word == "" then
		word = vim.fn.expand("<cword>")
	end

	if word == "" then
		local input_ok, input_word = pcall(vim.fn.input, "Variable or address to edit: ")
		if not input_ok then
			vim.notify("Failed to get input", vim.log.levels.ERROR)
			return
		end
		word = input_word
		if word == "" then
			return
		end
	end

	-- Validate the address/variable
	local valid, validation_error = validate_address(word)
	if not valid then
		vim.notify("Invalid address/variable: " .. validation_error, vim.log.levels.ERROR)
		return
	end

	-- Check if it's an address or variable
	if word:match("^0x%x+") or word:match("^%d+") then
		-- Memory address - ask for bytes
		local bytes_ok, bytes = pcall(vim.fn.input, "Enter bytes (hex, space-separated): ")
		if not bytes_ok then
			vim.notify("Failed to get hex input", vim.log.levels.ERROR)
			return
		end

		if bytes ~= "" then
			-- Enhanced validation and conversion to set commands
			local byte_list = {}
			local validation_failed = false
			local byte_count = 0

			-- Count and validate bytes first
			for byte in bytes:gmatch("%S+") do
				byte_count = byte_count + 1
				local hex_valid, hex_error = validate_hex_value(byte)
				if not hex_valid then
					vim.notify("Invalid hex value '" .. byte .. "': " .. hex_error, vim.log.levels.ERROR)
					validation_failed = true
					break
				end
				
				-- Normalize hex value (ensure 0x prefix)
				local normalized_byte = byte:gsub("^0x", "")
				if #normalized_byte > 2 then
					vim.notify("Hex value '" .. byte .. "' too large (max FF)", vim.log.levels.ERROR)
					validation_failed = true
					break
				end
				
				table.insert(byte_list, "0x" .. normalized_byte)
			end

			-- Check reasonable byte count limit
			if byte_count > 256 then
				vim.notify("Too many bytes to edit at once (max 256)", vim.log.levels.ERROR)
				validation_failed = true
			end

			if not validation_failed and #byte_list > 0 then
				local completed_operations = 0
				local total_operations = #byte_list
				local has_error = false
				local error_details = {}

				vim.notify("Writing " .. total_operations .. " bytes to memory...", vim.log.levels.INFO)

				for i, byte in ipairs(byte_list) do
					local addr = string.format("(char*)(%s)+%d", word, i - 1)
					utils.async_gdb_response(string.format("set *%s = %s", addr, byte), function(set_response, set_error)
						completed_operations = completed_operations + 1

						if set_error then
							has_error = true
							table.insert(error_details, string.format("Offset %d: %s", i - 1, set_error))
						else
							-- Check if response indicates success/failure
							if set_response and #set_response > 0 then
								local response_text = table.concat(set_response, " ")
								if response_text:match("[Ee]rror") or response_text:match("[Ff]ailed") then
									has_error = true
									table.insert(error_details, string.format("Offset %d: %s", i - 1, response_text))
								end
							end
						end

						-- When all operations complete, provide comprehensive feedback
						if completed_operations == total_operations then
							if not has_error then
								vim.notify("Successfully wrote " .. total_operations .. " bytes to memory", vim.log.levels.INFO)
								-- Refresh memory view if active
								if current_memory.address then
									vim.defer_fn(function()
										M.refresh_memory()
									end, 200)
								end
							else
								local success_count = total_operations - #error_details
								vim.notify(
									string.format("Memory write completed with errors (%d/%d successful):\n%s", 
										success_count, total_operations, table.concat(error_details, "\n")),
									vim.log.levels.WARN
								)
								-- Still refresh to show partial changes
								if current_memory.address then
									vim.defer_fn(function()
										M.refresh_memory()
									end, 200)
								end
							end
						end
					end, { timeout = 5000 })
				end
			end
		end
	else
		-- Variable - ask for new value
		local value_ok, value = pcall(vim.fn.input, "Set " .. word .. " = ")
		if not value_ok then
			vim.notify("Failed to get value input", vim.log.levels.ERROR)
			return
		end

		if value ~= "" then
			utils.async_gdb_response("set variable " .. word .. " = " .. value, function(_, error)
				if error then
					vim.notify("Failed to set variable: " .. error, vim.log.levels.ERROR)
				else
					-- Show updated value
					utils.async_gdb_response("print " .. word, function(r, e)
						if not e and r then
							local val = utils.extract_value(r)
							if val then
								vim.notify(word .. " = " .. val, vim.log.levels.INFO)
							else
								vim.notify("Variable " .. word .. " updated", vim.log.levels.INFO)
							end
						else
							vim.notify("Variable " .. word .. " updated (verification failed)", vim.log.levels.WARN)
						end
					end)
				end
			end)
		end
	end
end

---Interactive memory editor for current view
---Allows editing memory at specific offset from current address
---@return nil
function M.edit_memory_interactive()
	if not current_memory.address then
		local error_content = create_memory_error_content({
			type = "invalid_address",
			message = "No memory view active for editing",
			address = nil,
		})
		local config = get_config()
		create_memory_window(error_content, config, true)
		return
	end

	-- Check GDB availability
	local available, availability_error = check_memory_gdb_availability()
	if not available then
		vim.notify(availability_error, vim.log.levels.ERROR)
		return
	end

	local offset_ok, offset = pcall(vim.fn.input, "Offset from " .. current_memory.address .. ": ")
	if not offset_ok then
		vim.notify("Failed to get offset input", vim.log.levels.ERROR)
		return
	end

	if offset == "" then
		offset = "0"
	end

	-- Validate offset (should be a number)
	if not offset:match("^%-?%d+$") then
		vim.notify("Invalid offset format. Use a number (e.g., 0, 16, -8)", vim.log.levels.ERROR)
		return
	end

	local value_ok, value = pcall(vim.fn.input, "Value (hex): 0x")
	if not value_ok then
		vim.notify("Failed to get value input", vim.log.levels.ERROR)
		return
	end

	if value ~= "" then
		-- Validate hex value
		local hex_valid, hex_error = validate_hex_value("0x" .. value)
		if not hex_valid then
			vim.notify("Invalid hex value: " .. hex_error, vim.log.levels.ERROR)
			return
		end

		local addr = string.format("(char*)(%s)+%s", current_memory.address, offset)
		utils.async_gdb_response(string.format("set *%s = 0x%s", addr, value), function(_, error)
			if error then
				vim.notify("Failed to update memory at offset " .. offset .. ": " .. error, vim.log.levels.ERROR)
			else
				vim.notify("Memory updated at offset " .. offset, vim.log.levels.INFO)
				-- Refresh memory view
				vim.defer_fn(function()
					M.refresh_memory()
				end, 200)
			end
		end)
	end
end

---Create floating popup window for memory display
---@param content string[] Content to display
---@param opts table|nil Window options
---@param is_error boolean|nil Whether this is an error display
---@return number|nil, number|nil Window and buffer handles
local function create_popup_window(content, opts, is_error)
	opts = opts or {}
	is_error = is_error or false

	-- Close existing popup if any
	cleanup_popup_window()

	-- Create buffer for content
	local buf_ok, buf = pcall(vim.api.nvim_create_buf, false, true)
	if not buf_ok then
		vim.notify("Failed to create popup buffer: " .. tostring(buf), vim.log.levels.ERROR)
		return nil, nil
	end
	popup_buf = buf

	-- Track buffer for cleanup
	local track_buf_ok = pcall(function()
		utils.track_resource("popup_buf_" .. tostring(buf), "buffer", buf, function(b)
			if vim.api.nvim_buf_is_valid(b) then
				vim.api.nvim_buf_delete(b, { force = true })
			end
		end)
	end)
	if not track_buf_ok then
		vim.notify("Resource tracking unavailable for popup buffer", vim.log.levels.DEBUG)
	end

	local content_ok, content_err = pcall(vim.api.nvim_buf_set_lines, popup_buf, 0, -1, false, content or {})
	if not content_ok then
		vim.notify("Failed to set popup buffer content: " .. tostring(content_err), vim.log.levels.ERROR)
		cleanup_popup_window()
		return nil, nil
	end

	-- Calculate window size based on content
	local max_line_length = 0
	for _, line in ipairs(content) do
		max_line_length = math.max(max_line_length, vim.fn.strdisplaywidth(line))
	end

	-- Dynamic width: at least 60, at most 120, or content width + padding
	local width = math.min(120, math.max(60, max_line_length + 4))
	-- Dynamic height: at least 5, at most 25, or content height + padding
	local height = math.min(25, math.max(5, #content + 2))

	-- Get cursor position for positioning
	local cursor_pos = vim.api.nvim_win_get_cursor(0)
	local cursor_row = cursor_pos[1]
	local cursor_col = cursor_pos[2]

	-- Calculate position to avoid going off screen
	local screen_height = vim.o.lines
	local screen_width = vim.o.columns

	-- Position below cursor, but move up if it would go off screen
	local row = 1
	if cursor_row + height + 3 > screen_height then
		row = -(height + 1)
	end

	-- Position at cursor column, but adjust if it would go off screen
	local col = 0
	if cursor_col + width > screen_width then
		col = -(width - 10)
	end

	-- Create floating window
	local win_opts = {
		relative = "cursor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = opts.border or "rounded",
		noautocmd = true,
		focusable = true,
		zindex = 50,
	}

	local win_ok, win = pcall(vim.api.nvim_open_win, popup_buf, false, win_opts)
	if not win_ok then
		vim.notify("Failed to create popup window: " .. tostring(win), vim.log.levels.ERROR)
		cleanup_popup_window()
		return nil, nil
	end
	popup_win = win

	-- Track window for cleanup
	local track_win_ok = pcall(function()
		utils.track_resource("popup_win_" .. tostring(win), "window", win, function(w)
			if vim.api.nvim_win_is_valid(w) then
				vim.api.nvim_win_close(w, true)
			end
		end)
	end)
	if not track_win_ok then
		vim.notify("Resource tracking unavailable for popup window", vim.log.levels.DEBUG)
	end

	-- Set buffer options
	pcall(function()
		vim.bo[popup_buf].bufhidden = "wipe"
		vim.bo[popup_buf].buftype = "nofile"
		vim.bo[popup_buf].swapfile = false
		vim.bo[popup_buf].modifiable = false
		vim.bo[popup_buf].filetype = is_error and "text" or "xxd"
		vim.bo[popup_buf].wrap = true
		vim.bo[popup_buf].linebreak = true
	end)

	pcall(vim.api.nvim_buf_set_name, popup_buf, is_error and "Memory Error" or "Memory Popup")

	-- Add highlighting
	pcall(function()
		local highlight = is_error and "Normal:ErrorMsg,FloatBorder:ErrorMsg"
			or "Normal:NormalFloat,FloatBorder:FloatBorder"
		vim.wo[popup_win].winhl = highlight
	end)

	-- Add keybindings
	local keymaps = {
		["q"] = function() cleanup_popup_window() end,
		["<Esc>"] = function() cleanup_popup_window() end,
		["j"] = "<C-e>",
		["k"] = "<C-y>",
		["<C-d>"] = "<C-d>",
		["<C-u>"] = "<C-u>",
	}

	if not is_error then
		-- Add memory-specific keybindings
		keymaps["s"] = function() M.save_memory_to_register() end
		keymaps["S"] = function() M.save_memory_to_buffer() end
		keymaps["c"] = function() M.compare_memory_with_register() end
		keymaps["r"] = function() cleanup_popup_window(); M.show_memory_popup(current_memory.address, current_memory.size) end
	end

	for key, func in pairs(keymaps) do
		if type(func) == "function" then
			pcall(vim.api.nvim_buf_set_keymap, popup_buf, "n", key, "", {
				callback = func,
				noremap = true,
				silent = true,
			})
		else
			pcall(vim.api.nvim_buf_set_keymap, popup_buf, "n", key, func, {
				noremap = true,
				silent = true,
			})
		end
	end

	-- Auto-close on cursor movement/mode change
	local autocmd_id = vim.api.nvim_create_autocmd({"CursorMoved", "ModeChanged", "InsertEnter"}, {
		buffer = vim.api.nvim_get_current_buf(),
		once = true,
		callback = function()
			cleanup_popup_window()
		end,
	})

	return popup_win, popup_buf
end

---Show memory in popup window at cursor
---@param address string|nil Memory address to display
---@param size number|nil Number of bytes to show
---@return nil
function M.show_memory_popup(address, size)
	if not address then
		-- Get variable/address under cursor
		local word = vim.fn.expand("<cexpr>")
		if word == "" then
			word = vim.fn.expand("<cword>")
		end
		if word == "" then
			vim.notify("No variable or address under cursor", vim.log.levels.WARN)
			return
		end
		address = word
	end

	-- Check GDB availability
	local available, availability_error = check_memory_gdb_availability()
	if not available then
		local error_content = create_memory_error_content({
			type = "gdb_unavailable",
			message = availability_error,
			address = address,
		})
		create_popup_window(error_content, {}, true)
		return
	end

	-- Validate address
	local valid, validation_error = validate_address(address)
	if not valid then
		local error_content = create_memory_error_content({
			type = "invalid_address",
			message = validation_error,
			address = address,
		})
		create_popup_window(error_content, {}, true)
		return
	end

	size = size or 64 -- Smaller default for popups
	current_memory.variable = address

	-- Handle variable vs direct address
	if address:match("^0x%x+") or address:match("^%d+") then
		-- Direct address
		current_memory.address = address
		M._show_memory_popup_internal(address, size)
	else
		-- Variable - get address first with type info
		utils.async_gdb_response("info symbol " .. address, function(symbol_response, symbol_error)
			local type_info = ""
			if not symbol_error and symbol_response and #symbol_response > 0 then
				for _, line in ipairs(symbol_response) do
					if line and not line:match("^%(gdb%)") then
						type_info = line
						break
					end
				end
			end

			-- Get variable address and size
			utils.async_gdb_response("print &" .. address, function(addr_response, addr_error)
				if addr_error then
					local error_content = create_memory_error_content({
						type = "access_denied",
						message = "Could not get address: " .. addr_error,
						address = address,
					})
					create_popup_window(error_content, {}, true)
					return
				end

				-- Extract address
				local addr = nil
				if addr_response and #addr_response > 0 then
					for _, line in ipairs(addr_response) do
						addr = line:match("0x%x+")
						if addr then break end
					end
				end

				if addr then
					current_memory.address = addr
					-- Try to get variable size for better display
					utils.async_gdb_response("print sizeof(" .. address .. ")", function(sizeof_response, sizeof_error)
						local var_size = size
						if not sizeof_error and sizeof_response and #sizeof_response > 0 then
							for _, line in ipairs(sizeof_response) do
								local extracted_size = line:match("= (%d+)")
								if extracted_size then
									var_size = math.min(512, math.max(tonumber(extracted_size), 16)) -- Cap at 512 bytes for popup
									break
								end
							end
						end
						M._show_memory_popup_internal(addr, var_size, address, type_info)
					end, { timeout = 2000 })
				else
					local error_content = create_memory_error_content({
						type = "access_denied",
						message = "Could not get address for variable (may not be in scope)",
						address = address,
					})
					create_popup_window(error_content, {}, true)
				end
			end, { timeout = 3000 })
		end, { timeout = 2000 })
	end
end

---Internal function to show memory popup with enhanced formatting
---@param address string Memory address
---@param size number Number of bytes
---@param variable string|nil Variable name if applicable
---@param type_info string|nil Type information
---@return nil
function M._show_memory_popup_internal(address, size, variable, type_info)
	local cmd = string.format("x/%dxb %s", size, address)

	utils.async_gdb_response(cmd, function(response, error)
		if error then
			local error_content = create_memory_error_content({
				type = "access_denied",
				message = "Cannot access memory: " .. error,
				address = address,
			})
			create_popup_window(error_content, {}, true)
			return
		end

		if response and #response > 0 then
			-- Check for error in response
			local response_text = table.concat(response, " ")
			if response_text:match("[Cc]annot access") or response_text:match("[Ii]nvalid") then
				local error_content = create_memory_error_content({
					type = "access_denied",
					message = "Cannot access memory: " .. response_text,
					address = address,
				})
				create_popup_window(error_content, {}, true)
				return
			end

			-- Update state
			current_memory.address = address
			current_memory.size = size

			-- Enhanced header with variable info
			local formatted = {}
			if variable then
				table.insert(formatted, string.format("📍 Variable: %s", variable))
				if type_info and type_info ~= "" then
					table.insert(formatted, string.format("📝 Type: %s", type_info))
				end
				table.insert(formatted, string.format("🏠 Address: %s (%d bytes)", address, size))
			else
				table.insert(formatted, string.format("🏠 Memory at %s (%d bytes)", address, size))
			end
			table.insert(formatted, string.rep("─", 60))

			-- Format memory with ASCII sidebar
			local current_addr = parse_address(address) or 0
			for _, line in ipairs(response) do
				if line and line ~= "" and not line:match("^%(gdb%)") then
					local addr_match = line:match("(0x%x+):")
					if addr_match then
						local hex_part = line:match("0x%x+:%s*(.+)")
						if hex_part then
							-- Parse hex bytes and create ASCII representation
							local ascii = ""
							for hex_byte in hex_part:gmatch("0x(%x%x)") do
								local byte_val = tonumber(hex_byte, 16)
								if byte_val and byte_val >= 32 and byte_val <= 126 then
									ascii = ascii .. string.char(byte_val)
								else
									ascii = ascii .. "."
								end
							end

							-- Compact format for popup
							local formatted_line = string.format("%-12s %-32s |%s|",
								addr_match .. ":", hex_part, ascii)
							table.insert(formatted, formatted_line)
						else
							table.insert(formatted, line)
						end
					else
						table.insert(formatted, line)
					end
				end
			end

			-- Add help footer
			table.insert(formatted, "")
			table.insert(formatted, string.rep("─", 60))
			table.insert(formatted, "💾 s: save to register | S: save to buffer | c: compare | r: refresh | q: close")

			create_popup_window(formatted, {}, false)
		else
			local error_content = create_memory_error_content({
				type = "access_denied",
				message = "No memory data returned",
				address = address,
			})
			create_popup_window(error_content, {}, true)
		end
	end, { timeout = 5000 })
end

---Save current memory view to register
---@param register string|nil Register to save to (default 'm')
---@return nil
function M.save_memory_to_register(register)
	if not current_memory.address then
		vim.notify("No memory view active to save", vim.log.levels.WARN)
		return
	end

	register = register or 'm'

	-- Get current memory content
	local cmd = string.format("x/%dxb %s", current_memory.size, current_memory.address)
	utils.async_gdb_response(cmd, function(response, error)
		if error then
			vim.notify("Failed to get memory for saving: " .. error, vim.log.levels.ERROR)
			return
		end

		if response and #response > 0 then
			-- Format memory data with header
			local content_lines = {
				string.format("Memory dump: %s (%d bytes) - %s",
					current_memory.address, current_memory.size, os.date("%Y-%m-%d %H:%M:%S"))
			}
			for _, line in ipairs(response) do
				if line and line ~= "" and not line:match("^%(gdb%)") then
					table.insert(content_lines, line)
				end
			end

			-- Save to register
			local content = table.concat(content_lines, "\n")
			vim.fn.setreg(register, content)
			vim.notify(string.format("Memory saved to register '%s'", register), vim.log.levels.INFO)
		else
			vim.notify("No memory data to save", vim.log.levels.WARN)
		end
	end)
end

---Save current memory view to new buffer
---@param buffer_name string|nil Buffer name (default auto-generated)
---@return nil
function M.save_memory_to_buffer(buffer_name)
	if not current_memory.address then
		vim.notify("No memory view active to save", vim.log.levels.WARN)
		return
	end

	buffer_name = buffer_name or string.format("memory_%s_%s.hex",
		current_memory.address:gsub("0x", ""), os.date("%H%M%S"))

	-- Get current memory content
	local cmd = string.format("x/%dxb %s", current_memory.size, current_memory.address)
	utils.async_gdb_response(cmd, function(response, error)
		if error then
			vim.notify("Failed to get memory for saving: " .. error, vim.log.levels.ERROR)
			return
		end

		if response and #response > 0 then
			-- Create new buffer
			local buf = vim.api.nvim_create_buf(true, false)
			if not buf then
				vim.notify("Failed to create buffer", vim.log.levels.ERROR)
				return
			end

			-- Format content with enhanced header
			local content_lines = {
				"# Memory Dump",
				"# Address: " .. current_memory.address,
				"# Size: " .. current_memory.size .. " bytes",
				"# Variable: " .. (current_memory.variable or "N/A"),
				"# Timestamp: " .. os.date("%Y-%m-%d %H:%M:%S"),
				"#",
				"",
			}

			-- Add memory content with enhanced formatting
			for _, line in ipairs(response) do
				if line and line ~= "" and not line:match("^%(gdb%)") then
					local addr_match = line:match("(0x%x+):")
					if addr_match then
						local hex_part = line:match("0x%x+:%s*(.+)")
						if hex_part then
							-- Create ASCII representation
							local ascii = ""
							for hex_byte in hex_part:gmatch("0x(%x%x)") do
								local byte_val = tonumber(hex_byte, 16)
								if byte_val and byte_val >= 32 and byte_val <= 126 then
									ascii = ascii .. string.char(byte_val)
								else
									ascii = ascii .. "."
								end
							end

							-- Enhanced format for buffer
							local formatted_line = string.format("%-18s %-48s |%s|",
								addr_match .. ":", hex_part, ascii)
							table.insert(content_lines, formatted_line)
						else
							table.insert(content_lines, line)
						end
					else
						table.insert(content_lines, line)
					end
				end
			end

			-- Set buffer content and properties
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, content_lines)
			vim.api.nvim_buf_set_name(buf, buffer_name)
			vim.bo[buf].filetype = "xxd"
			vim.bo[buf].modified = false

			-- Open buffer in new split
			vim.cmd("split")
			vim.api.nvim_win_set_buf(0, buf)

			vim.notify(string.format("Memory saved to buffer '%s'", buffer_name), vim.log.levels.INFO)
		else
			vim.notify("No memory data to save", vim.log.levels.WARN)
		end
	end)
end

---Compare current memory view with saved register content
---@param register string|nil Register to compare with (default 'm')
---@return nil
function M.compare_memory_with_register(register)
	if not current_memory.address then
		vim.notify("No memory view active to compare", vim.log.levels.WARN)
		return
	end

	register = register or 'm'
	local saved_content = vim.fn.getreg(register)
	if not saved_content or saved_content == "" then
		vim.notify(string.format("Register '%s' is empty", register), vim.log.levels.WARN)
		return
	end

	-- Get current memory content
	local cmd = string.format("x/%dxb %s", current_memory.size, current_memory.address)
	utils.async_gdb_response(cmd, function(response, error)
		if error then
			vim.notify("Failed to get current memory: " .. error, vim.log.levels.ERROR)
			return
		end

		if response and #response > 0 then
			-- Format current memory
			local current_lines = {
				string.format("Current Memory: %s (%d bytes) - %s",
					current_memory.address, current_memory.size, os.date("%Y-%m-%d %H:%M:%S"))
			}
			for _, line in ipairs(response) do
				if line and line ~= "" and not line:match("^%(gdb%)") then
					table.insert(current_lines, line)
				end
			end

			-- Create comparison buffer
			local buf = vim.api.nvim_create_buf(true, false)
			if not buf then
				vim.notify("Failed to create comparison buffer", vim.log.levels.ERROR)
				return
			end

			-- Split saved content and add header
			local saved_lines = vim.split(saved_content, "\n")
			table.insert(saved_lines, 1, string.rep("=", 60))
			table.insert(saved_lines, 2, "SAVED CONTENT (from register '" .. register .. "'):")
			table.insert(saved_lines, 3, string.rep("=", 60))
			table.insert(saved_lines, 4, "")

			-- Add separator and current content
			table.insert(saved_lines, "")
			table.insert(saved_lines, string.rep("=", 60))
			table.insert(saved_lines, "CURRENT CONTENT:")
			table.insert(saved_lines, string.rep("=", 60))
			table.insert(saved_lines, "")
			for _, line in ipairs(current_lines) do
				table.insert(saved_lines, line)
			end

			-- Set buffer content
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, saved_lines)
			vim.api.nvim_buf_set_name(buf, string.format("memory_comparison_%s.diff", register))
			vim.bo[buf].filetype = "diff"
			vim.bo[buf].modified = false

			-- Open in split
			vim.cmd("split")
			vim.api.nvim_win_set_buf(0, buf)

			vim.notify(string.format("Memory comparison with register '%s' opened", register), vim.log.levels.INFO)
		else
			vim.notify("No current memory data to compare", vim.log.levels.WARN)
		end
	end)
end

---Open two memory dump buffers in diff mode
---@param buffer1 string First buffer name/pattern
---@param buffer2 string Second buffer name/pattern  
---@return nil
function M.diff_memory_buffers(buffer1, buffer2)
	-- Find buffers by name pattern
	local buf1, buf2 = nil, nil
	local buffers = vim.api.nvim_list_bufs()
	
	for _, buf in ipairs(buffers) do
		local name = vim.api.nvim_buf_get_name(buf)
		if name:match(buffer1) then
			buf1 = buf
		elseif name:match(buffer2) then
			buf2 = buf
		end
	end

	if not buf1 then
		vim.notify("Buffer matching '" .. buffer1 .. "' not found", vim.log.levels.ERROR)
		return
	end
	if not buf2 then
		vim.notify("Buffer matching '" .. buffer2 .. "' not found", vim.log.levels.ERROR)
		return
	end

	-- Open buffers in diff mode
	vim.cmd("tabnew")
	vim.api.nvim_win_set_buf(0, buf1)
	vim.cmd("diffthis")
	vim.cmd("vertical split")
	vim.api.nvim_win_set_buf(0, buf2)
	vim.cmd("diffthis")

	vim.notify("Memory buffers opened in diff mode", vim.log.levels.INFO)
end

-- Cleanup function for module
---@return nil
function M.cleanup_all_windows()
	cleanup_memory_window()
	cleanup_popup_window()
end

return M

