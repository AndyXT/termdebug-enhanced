---@class KeymapEntry
---@field mode string Keymap mode
---@field key string Key combination

---@class KeymapError
---@field type string Error type (setup_failed, cleanup_failed, gdb_unavailable, command_failed)
---@field message string Human-readable error message
---@field keymap string|nil The keymap that caused the error

---@class DebugCommand
---@field vim_cmd string Vim command to try first
---@field gdb_cmd string GDB command to try as fallback
---@field description string Description for user feedback

---@class termdebug-enhanced.keymaps
local M = {}

local utils = require("termdebug-enhanced.utils")

---Lazy load evaluate module to avoid circular dependencies
---
---Loads the evaluate module only when needed to prevent circular dependency
---issues during module initialization. This pattern allows modules to reference
---each other without causing loading problems.
---
---@return termdebug-enhanced.evaluate
local function get_eval()
	return require("termdebug-enhanced.evaluate")
end

---Lazy load memory module to avoid circular dependencies
---
---Loads the memory module only when needed to prevent circular dependency
---issues during module initialization. This pattern allows modules to reference
---each other without causing loading problems.
---
---@return termdebug-enhanced.memory
local function get_memory()
	return require("termdebug-enhanced.memory")
end

---@type KeymapEntry[]
local active_keymaps = {}

---Check if GDB is available for keymap operations
---
---Verifies that the termdebug plugin is loaded and a debugging session is active
---before allowing keymap operations that require GDB communication. This prevents
---errors when users try to use debugging keymaps outside of debugging sessions.
---
---@return boolean available, string|nil error_msg
local function check_keymap_gdb_availability()
	if vim.fn.exists(":Termdebug") == 0 then
		return false, "Termdebug not available. Run :packadd termdebug"
	end

	if not vim.g.termdebug_running then
		return false, "Debug session not active. Start debugging first"
	end

	return true, nil
end

---Validate keymap configuration format and syntax
---
---Validates that a keymap string is properly formatted and can be used with
---Neovim's keymap system. Performs basic syntax checking to catch common
---formatting errors before attempting to register the keymap.
---
---@param key string Key combination to validate
---@return boolean valid, string|nil error_msg
local function validate_keymap(key)
	if not key or key == "" then
		return false, "Empty keymap"
	end

	local trimmed = vim.trim(key)
	if trimmed == "" then
		return false, "Keymap contains only whitespace"
	end

	-- Check for obviously invalid key combinations
	if trimmed:match("^<.*>$") and not trimmed:match("^<[%w%-_]+>$") then
		return false, "Invalid key format. Use format like <F5> or <C-S-F5>"
	end

	return true, nil
end

-- Safe keymap setting with error handling
---@param mode string Keymap mode
---@param key string Key combination
---@param callback function Callback function
---@param opts table Keymap options
---@return boolean success, string|nil error_msg
local function safe_set_keymap(mode, key, callback, opts)
	local ok, err = pcall(vim.keymap.set, mode, key, callback, opts)
	if not ok then
		return false, "Failed to set keymap " .. key .. ": " .. tostring(err)
	end
	return true, nil
end

-- Safe keymap deletion with error handling
---@param mode string Keymap mode
---@param key string Key combination
---@return boolean success, string|nil error_msg
local function safe_del_keymap(mode, key)
	local ok, err = pcall(vim.keymap.del, mode, key)
	if not ok then
		return false, "Failed to delete keymap " .. key .. ": " .. tostring(err)
	end
	return true, nil
end

---Try vim command first, fallback to GDB command
---@param vim_cmd string Vim command to execute
---@param gdb_cmd string GDB command as fallback
---@param description string Description for logging
---@return boolean success
local function try_debug_command(vim_cmd, gdb_cmd, description)
	-- Method 1: Try Vim command
	local vim_ok, vim_err = pcall(vim.cmd, vim_cmd)
	if vim_ok then
		vim.notify(description .. " executed via :" .. vim_cmd, vim.log.levels.DEBUG)
		return true
	end

	vim.notify(vim_cmd .. " command failed: " .. tostring(vim_err), vim.log.levels.DEBUG)

	-- Method 2: Try direct GDB command
	if vim.fn.exists("*TermDebugSendCommand") == 1 then
		local gdb_ok, gdb_err = pcall(vim.fn.TermDebugSendCommand, gdb_cmd)
		if gdb_ok then
			vim.notify(description .. " executed via GDB '" .. gdb_cmd .. "'", vim.log.levels.DEBUG)
			return true
		end
		vim.notify("Direct GDB command failed: " .. tostring(gdb_err), vim.log.levels.ERROR)
	end

	vim.notify("Failed to execute " .. description, vim.log.levels.ERROR)
	return false
end

---Create a debug command function
---@param cmd DebugCommand Command configuration
---@return function Command function
local function create_debug_command(cmd)
	return function()
		try_debug_command(cmd.vim_cmd, cmd.gdb_cmd, cmd.description)
	end
end

---Create restart command with proper sequencing
---@return function Restart command function
local function create_restart_command()
	return function()
		local stop_ok, stop_error = pcall(vim.cmd, "Stop")
		if not stop_ok then
			vim.notify("Failed to stop debugging: " .. tostring(stop_error), vim.log.levels.ERROR)
			return
		end
		vim.defer_fn(function()
			local run_ok, run_error = pcall(vim.cmd, "Run")
			if not run_ok then
				vim.notify("Failed to restart debugging: " .. tostring(run_error), vim.log.levels.ERROR)
			end
		end, 100)
	end
end

---Setup a single keymap with validation and error handling
---@param key string Key combination
---@param mode string Keymap mode
---@param callback function Callback function
---@param description string Description for the keymap
---@param errors string[] Error collection
---@param validate_empty boolean Whether to validate empty keys (default: false)
---@return boolean success
local function setup_single_keymap(key, mode, callback, description, errors, validate_empty)
	validate_empty = validate_empty or false

	if not key then
		if validate_empty then
			table.insert(errors, "Missing " .. description .. " keymap")
		end
		return false
	end

	if key == "" then
		if validate_empty then
			table.insert(errors, "Empty " .. description .. " keymap")
		end
		return false
	end

	local valid, validation_error = validate_keymap(key)
	if not valid then
		table.insert(errors, "Invalid " .. description .. " keymap '" .. key .. "': " .. validation_error)
		return false
	end

	local keymap_success, keymap_error = safe_set_keymap(mode, key, callback, { desc = description })
	if keymap_success then
		table.insert(active_keymaps, { mode = mode, key = key })
		return true
	else
		table.insert(errors, keymap_error)
		return false
	end
end

---Set a breakpoint at the specified location
---@param file string File path
---@param line number Line number
local function set_breakpoint(file, line)
	utils.async_gdb_response("break " .. file .. ":" .. line, function(response, error)
		if error then
			vim.notify("Failed to set breakpoint: " .. error, vim.log.levels.ERROR)
			return
		end

		local response_text = response and table.concat(response, " ") or ""
		if response_text:match("[Ee]rror") or response_text:match("[Ff]ailed") then
			vim.notify("Breakpoint creation failed: " .. response_text, vim.log.levels.WARN)
		else
			local bp_num = response_text:match("Breakpoint (%d+)")
			local msg = bp_num and "Breakpoint " .. bp_num .. " set" or "Breakpoint set"
			vim.notify(msg .. " at " .. vim.fn.fnamemodify(file, ":t") .. ":" .. line, vim.log.levels.INFO)
		end
	end, { timeout = 3000 })
end

---Remove a breakpoint by number
---@param bp_num string Breakpoint number
---@param file string File path
---@param line number Line number
local function remove_breakpoint(bp_num, file, line)
	utils.async_gdb_response("delete " .. bp_num, function(response, error)
		if error then
			vim.notify("Failed to remove breakpoint: " .. error, vim.log.levels.ERROR)
			return
		end

		local response_text = response and table.concat(response, " ") or ""
		if response_text:match("[Ee]rror") or response_text:match("[Ff]ailed") then
			vim.notify("Breakpoint deletion failed: " .. response_text, vim.log.levels.WARN)
		else
			vim.notify(
				"Breakpoint " .. bp_num .. " removed from " .. vim.fn.fnamemodify(file, ":t") .. ":" .. line,
				vim.log.levels.INFO
			)
		end
	end, { timeout = 3000 })
end

---Create breakpoint toggle command with unified logic
---@return function Breakpoint toggle function
local function create_breakpoint_command()
	return function()
		local bp_available, bp_error = check_keymap_gdb_availability()
		if not bp_available then
			vim.notify("Cannot toggle breakpoint: " .. bp_error, vim.log.levels.ERROR)
			return
		end

		local line_ok, line = pcall(vim.fn.line, ".")
		local file_ok, file = pcall(vim.fn.expand, "%:p")

		if not line_ok or not file_ok or file == "" then
			vim.notify("Cannot determine current file/line for breakpoint", vim.log.levels.ERROR)
			return
		end

		utils.async_gdb_response("info breakpoints", function(response, error)
			if error then
				vim.notify("Failed to check breakpoints: " .. error, vim.log.levels.ERROR)
				return
			end

			local no_breakpoints = not response
				or #response == 0
				or table.concat(response, " "):match("[Nn]o breakpoints")

			if no_breakpoints then
				set_breakpoint(file, line)
			else
				local breakpoints = utils.parse_breakpoints(response)
				local bp_num = utils.find_breakpoint(breakpoints, file, line)

				if bp_num then
					remove_breakpoint(bp_num, file, line)
				else
					set_breakpoint(file, line)
				end
			end
		end, { timeout = 3000 })
	end
end

---Create protected wrapper for module functions
---@param module_getter function Function that returns the module
---@param method_name string Method name to call
---@param error_prefix string Error message prefix
---@return function Protected function
local function create_protected_call(module_getter, method_name, error_prefix)
	return function()
		local ok, err = pcall(function()
			module_getter()[method_name]()
		end)
		if not ok then
			vim.notify(error_prefix .. ": " .. tostring(err), vim.log.levels.ERROR)
		end
	end
end

---Setup step debugging keymaps
---@param keymaps table Keymap configuration
---@param errors string[] Error collection
---@return number success_count
local function setup_step_keymaps(keymaps, errors)
	local commands = {
		{
			key = keymaps.continue,
			cmd = { vim_cmd = "Continue", gdb_cmd = "continue", description = "Continue execution" },
		},
		{ key = keymaps.step_over, cmd = { vim_cmd = "Over", gdb_cmd = "next", description = "Step over" } },
		{ key = keymaps.step_into, cmd = { vim_cmd = "Step", gdb_cmd = "step", description = "Step into" } },
		{ key = keymaps.step_out, cmd = { vim_cmd = "Finish", gdb_cmd = "finish", description = "Step out" } },
	}

	local success_count = 0
	for _, command in ipairs(commands) do
		if
			setup_single_keymap(
				command.key,
				"n",
				create_debug_command(command.cmd),
				command.cmd.description,
				errors,
				true -- validate empty keys
			)
		then
			success_count = success_count + 1
		end
	end

	return success_count
end

---Setup control keymaps (stop, restart)
---@param keymaps table Keymap configuration
---@param errors string[] Error collection
---@return number success_count
local function setup_control_keymaps(keymaps, errors)
	local success_count = 0

	if setup_single_keymap(keymaps.stop, "n", function()
		vim.cmd("Stop")
	end, "Stop debugging", errors) then
		success_count = success_count + 1
	end

	if setup_single_keymap(keymaps.restart, "n", create_restart_command(), "Restart debugging", errors) then
		success_count = success_count + 1
	end

	return success_count
end

---Setup breakpoint keymaps
---@param keymaps table Keymap configuration
---@param errors string[] Error collection
---@return number success_count
local function setup_breakpoint_keymaps(keymaps, errors)
	local success_count = 0

	if
		setup_single_keymap(keymaps.toggle_breakpoint, "n", create_breakpoint_command(), "Toggle breakpoint", errors)
	then
		success_count = success_count + 1
	end

	return success_count
end

---Setup evaluation keymaps
---@param keymaps table Keymap configuration
---@param errors string[] Error collection
---@return number success_count
local function setup_evaluation_keymaps(keymaps, errors)
	local success_count = 0

	if
		setup_single_keymap(
			keymaps.evaluate,
			"n",
			create_protected_call(get_eval, "evaluate_under_cursor", "Evaluation failed"),
			"Evaluate expression under cursor",
			errors
		)
	then
		success_count = success_count + 1
	end

	if
		setup_single_keymap(
			keymaps.evaluate_visual,
			"v",
			create_protected_call(get_eval, "evaluate_selection", "Visual evaluation failed"),
			"Evaluate selected expression",
			errors
		)
	then
		success_count = success_count + 1
	end

	return success_count
end

---Setup memory keymaps
---@param keymaps table Keymap configuration
---@param errors string[] Error collection
---@return number success_count
local function setup_memory_keymaps(keymaps, errors)
	local memory_commands = {
		{ key = keymaps.memory_view, method = "view_memory_at_cursor", desc = "View memory at cursor" },
		{ key = keymaps.memory_edit, method = "edit_memory_at_cursor", desc = "Edit memory/variable at cursor" },
		{ key = keymaps.memory_popup, method = "show_memory_popup", desc = "Show memory popup at cursor" },
	}

	local success_count = 0
	for _, cmd in ipairs(memory_commands) do
		if
			setup_single_keymap(
				cmd.key,
				"n",
				create_protected_call(get_memory, cmd.method, "Memory operation failed"),
				cmd.desc,
				errors
			)
		then
			success_count = success_count + 1
		end
	end

	return success_count
end

---Setup watch and variable keymaps
---@param keymaps table Keymap configuration
---@param errors string[] Error collection
---@return number success_count
local function setup_variable_keymaps(keymaps, errors)
	local success_count = 0

	-- Watch add
	if
		setup_single_keymap(keymaps.watch_add, "n", function()
			local available, error_msg = check_keymap_gdb_availability()
			if not available then
				vim.notify("Cannot add watch: " .. error_msg, vim.log.levels.ERROR)
				return
			end

			local ok, expr = pcall(vim.fn.input, "Watch expression: ")
			if ok and expr ~= "" then
				utils.async_gdb_response("display " .. expr, function(_, error)
					if error then
						vim.notify("Failed to add watch: " .. error, vim.log.levels.ERROR)
					else
						vim.notify("Watch added: " .. expr, vim.log.levels.INFO)
					end
				end)
			end
		end, "Add watch expression", errors)
	then
		success_count = success_count + 1
	end

	-- Variable set
	if
		setup_single_keymap(keymaps.variable_set, "n", function()
			local available, error_msg = check_keymap_gdb_availability()
			if not available then
				vim.notify("Cannot set variable: " .. error_msg, vim.log.levels.ERROR)
				return
			end

			local var_ok, var = pcall(vim.fn.expand, "<cword>")
			if not var_ok or var == "" then
				vim.notify("No variable under cursor", vim.log.levels.WARN)
				return
			end

			local value_ok, value = pcall(vim.fn.input, "Set " .. var .. " = ")
			if value_ok and value ~= "" then
				utils.async_gdb_response("set variable " .. var .. " = " .. value, function(_, error)
					if error then
						vim.notify("Failed to set variable: " .. error, vim.log.levels.ERROR)
					else
						vim.notify("Variable " .. var .. " set to " .. value, vim.log.levels.INFO)
					end
				end)
			end
		end, "Set variable value", errors)
	then
		success_count = success_count + 1
	end

	return success_count
end

---Setup debugging keymaps with comprehensive error handling
---
---Configures VSCode-like debugging keymaps for the current session. This function
---sets up all the debugging keybindings including step operations, breakpoint
---management, expression evaluation, and memory operations.
---
---The function includes:
---- Validation of all keymap configurations
---- Duplicate keymap detection
---- Comprehensive error reporting
---- Graceful degradation on partial failures
---- Resource tracking for cleanup
---
---Supported keymaps:
---- F5: Continue execution
---- F9: Toggle breakpoint
---- F10: Step over
---- F11: Step into
---- Shift+F11: Step out
---- K: Evaluate expression under cursor
---- Memory and variable operations
---
---@param keymaps table Keymap configuration from plugin config
---@return boolean success, string[] errors List of setup errors
function M.setup_keymaps(keymaps)
	local errors = {}
	local success_count = 0

	-- Check GDB availability first
	local available, availability_error = check_keymap_gdb_availability()
	if not available then
		table.insert(errors, "GDB not available: " .. availability_error)
		vim.notify(
			"Warning: " .. availability_error .. " (keymaps will be set up but may not work)",
			vim.log.levels.WARN
		)
	end

	-- Validate keymaps parameter
	if not keymaps or type(keymaps) ~= "table" then
		table.insert(errors, "Invalid keymaps configuration")
		return false, errors
	end

	-- Setup keymaps by category
	success_count = success_count + setup_step_keymaps(keymaps, errors)
	success_count = success_count + setup_control_keymaps(keymaps, errors)
	success_count = success_count + setup_breakpoint_keymaps(keymaps, errors)
	success_count = success_count + setup_evaluation_keymaps(keymaps, errors)
	success_count = success_count + setup_memory_keymaps(keymaps, errors)
	success_count = success_count + setup_variable_keymaps(keymaps, errors)

	local total_count = success_count + #errors

	-- Report setup results
	if #errors > 0 then
		vim.notify(
			"Keymap setup completed with errors ("
				.. success_count
				.. "/"
				.. total_count
				.. " successful):\n"
				.. table.concat(errors, "\n"),
			vim.log.levels.WARN
		)
	else
		vim.notify(
			"All keymaps set up successfully (" .. success_count .. "/" .. total_count .. ")",
			vim.log.levels.INFO
		)
	end

	return #errors == 0, errors
end

---Clean up all active keymaps with error handling
---
---Removes all debugging keymaps that were set up during the debugging session.
---This function is called automatically when the debugging session ends to
---prevent keymap conflicts and ensure clean state for the next session.
---
---The cleanup process includes:
---- Safe removal of all registered keymaps
---- Error handling for already-removed keymaps
---- Comprehensive error reporting
---- Resource tracking cleanup
---
---@return boolean success, string[] errors List of cleanup errors
function M.cleanup_keymaps()
	local errors = {}
	local success_count = 0
	local total_count = #active_keymaps

	for _, mapping in ipairs(active_keymaps) do
		local cleanup_success, cleanup_error = safe_del_keymap(mapping.mode, mapping.key)
		if cleanup_success then
			success_count = success_count + 1
		else
			table.insert(errors, cleanup_error)
		end
	end

	active_keymaps = {}

	-- Report cleanup results
	if #errors > 0 then
		vim.notify(
			"Keymap cleanup completed with errors ("
				.. success_count
				.. "/"
				.. total_count
				.. " successful):\n"
				.. table.concat(errors, "\n"),
			vim.log.levels.WARN
		)
	elseif total_count > 0 then
		vim.notify("All keymaps cleaned up successfully (" .. success_count .. " removed)", vim.log.levels.INFO)
	end

	return #errors == 0, errors
end

return M

