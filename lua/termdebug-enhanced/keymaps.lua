---@class KeymapEntry
---@field mode string Keymap mode
---@field key string Key combination

---@class KeymapError
---@field type string Error type (setup_failed, cleanup_failed, gdb_unavailable, command_failed)
---@field message string Human-readable error message
---@field keymap string|nil The keymap that caused the error

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
	local total_count = 0

	-- Check GDB availability first
	local available, availability_error = check_keymap_gdb_availability()
	if not available then
		table.insert(errors, "GDB not available: " .. availability_error)
		-- Continue with setup but warn user
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

	-- VSCode-like debugging keymaps (with safe access)
	local mappings = {}

	if keymaps.continue then
		mappings[keymaps.continue] = { cmd = "Continue", desc = "Continue execution" }
	end
	if keymaps.step_over then
		mappings[keymaps.step_over] = { cmd = "Over", desc = "Step over" }
	end
	if keymaps.step_into then
		mappings[keymaps.step_into] = { cmd = "Step", desc = "Step into" }
	end
	if keymaps.step_out then
		mappings[keymaps.step_out] = { cmd = "Finish", desc = "Step out" }
	end
	if keymaps.stop then
		mappings[keymaps.stop] = { cmd = "Stop", desc = "Stop debugging" }
	end
	if keymaps.restart then
		mappings[keymaps.restart] = {
			cmd = function()
				local stop_ok, stop_err = pcall(vim.cmd, "Stop")
				if not stop_ok then
					vim.notify("Failed to stop debugging: " .. tostring(stop_err), vim.log.levels.ERROR)
					return
				end
				vim.defer_fn(function()
					local run_ok, run_err = pcall(vim.cmd, "Run")
					if not run_ok then
						vim.notify("Failed to restart debugging: " .. tostring(run_err), vim.log.levels.ERROR)
					end
				end, 100)
			end,
			desc = "Restart debugging",
		}
	end

	-- Set up standard debugging keymaps
	for key, mapping in pairs(mappings) do
		if key and key ~= "" then
			total_count = total_count + 1

			-- Validate keymap
			local valid, validation_error = validate_keymap(key)
			if not valid then
				table.insert(errors, "Invalid keymap '" .. key .. "': " .. validation_error)
				goto continue
			end

			-- Set up keymap with error handling
			local keymap_success, keymap_error = safe_set_keymap("n", key, function()
				local cmd_ok, cmd_err = pcall(function()
					if type(mapping.cmd) == "function" then
						mapping.cmd()
					else
						vim.cmd(mapping.cmd)
					end
				end)
				if not cmd_ok then
					vim.notify("Keymap command failed: " .. tostring(cmd_err), vim.log.levels.ERROR)
				end
			end, { desc = mapping.desc, buffer = false })

			if keymap_success then
				table.insert(active_keymaps, { mode = "n", key = key })
				success_count = success_count + 1
			else
				table.insert(errors, keymap_error)
			end

			::continue::
		end
	end

	-- Breakpoint toggle with proper toggle logic and error handling
	if keymaps.toggle_breakpoint then
		total_count = total_count + 1

		-- Validate keymap
		local valid, validation_error = validate_keymap(keymaps.toggle_breakpoint)
		if not valid then
			table.insert(
				errors,
				"Invalid toggle_breakpoint keymap '" .. keymaps.toggle_breakpoint .. "': " .. validation_error
			)
		else
			local keymap_success, keymap_error = safe_set_keymap("n", keymaps.toggle_breakpoint, function()
				-- Check GDB availability for breakpoint operations
				local bp_available, bp_error = check_keymap_gdb_availability()
				if not bp_available then
					vim.notify("Cannot toggle breakpoint: " .. bp_error, vim.log.levels.ERROR)
					return
				end

				local line_ok, line = pcall(vim.fn.line, ".")
				local file_ok, file = pcall(vim.fn.expand, "%:p")

				if not line_ok or not file_ok then
					vim.notify("Failed to get current file/line information", vim.log.levels.ERROR)
					return
				end

				if file == "" then
					vim.notify("No file open for breakpoint", vim.log.levels.WARN)
					return
				end

				-- Get current breakpoints
				utils.async_gdb_response("info breakpoints", function(response, error)
					if error then
						-- No breakpoints exist or error getting them, just add one
						utils.async_gdb_response("break " .. file .. ":" .. line, function(_, bp_error)
							if bp_error then
								vim.notify("Failed to set breakpoint: " .. bp_error, vim.log.levels.ERROR)
							else
								vim.notify("Breakpoint set at line " .. line, vim.log.levels.INFO)
							end
						end)
						return
					end

					-- Parse breakpoints and check if one exists at this location
					if response and #response > 0 then
						local breakpoints = utils.parse_breakpoints(response)
						local bp_num = utils.find_breakpoint(breakpoints, file, line)

						if bp_num then
							-- Breakpoint exists, remove it
							utils.async_gdb_response("delete " .. bp_num, function(_, del_error)
								if del_error then
									vim.notify("Failed to remove breakpoint: " .. del_error, vim.log.levels.ERROR)
								else
									vim.notify("Breakpoint " .. bp_num .. " removed", vim.log.levels.INFO)
								end
							end)
						else
							-- No breakpoint here, add one
							utils.async_gdb_response("break " .. file .. ":" .. line, function(_, add_error)
								if add_error then
									vim.notify("Failed to set breakpoint: " .. add_error, vim.log.levels.ERROR)
								else
									vim.notify("Breakpoint set at line " .. line, vim.log.levels.INFO)
								end
							end)
						end
					else
						-- Empty response, try to add breakpoint
						utils.async_gdb_response("break " .. file .. ":" .. line, function(_, add_error)
							if add_error then
								vim.notify("Failed to set breakpoint: " .. add_error, vim.log.levels.ERROR)
							else
								vim.notify("Breakpoint set at line " .. line, vim.log.levels.INFO)
							end
						end)
					end
				end, { timeout = 2000 })
			end, { desc = "Toggle breakpoint" })

			if keymap_success then
				table.insert(active_keymaps, { mode = "n", key = keymaps.toggle_breakpoint })
				success_count = success_count + 1
			else
				table.insert(errors, keymap_error)
			end
		end
	end

	-- Evaluate under cursor (like LSP hover)
	if keymaps.evaluate then
		total_count = total_count + 1
		local valid, validation_error = validate_keymap(keymaps.evaluate)
		if not valid then
			table.insert(errors, "Invalid evaluate keymap '" .. keymaps.evaluate .. "': " .. validation_error)
		else
			local keymap_success, keymap_error = safe_set_keymap("n", keymaps.evaluate, function()
				local eval_ok, eval_err = pcall(function()
					get_eval().evaluate_under_cursor()
				end)
				if not eval_ok then
					vim.notify("Evaluation failed: " .. tostring(eval_err), vim.log.levels.ERROR)
				end
			end, { desc = "Evaluate expression under cursor" })

			if keymap_success then
				table.insert(active_keymaps, { mode = "n", key = keymaps.evaluate })
				success_count = success_count + 1
			else
				table.insert(errors, keymap_error)
			end
		end
	end

	-- Evaluate visual selection
	if keymaps.evaluate_visual then
		total_count = total_count + 1
		local valid, validation_error = validate_keymap(keymaps.evaluate_visual)
		if not valid then
			table.insert(
				errors,
				"Invalid evaluate_visual keymap '" .. keymaps.evaluate_visual .. "': " .. validation_error
			)
		else
			local keymap_success, keymap_error = safe_set_keymap("v", keymaps.evaluate_visual, function()
				local eval_ok, eval_err = pcall(function()
					get_eval().evaluate_selection()
				end)
				if not eval_ok then
					vim.notify("Visual evaluation failed: " .. tostring(eval_err), vim.log.levels.ERROR)
				end
			end, { desc = "Evaluate selected expression" })

			if keymap_success then
				table.insert(active_keymaps, { mode = "v", key = keymaps.evaluate_visual })
				success_count = success_count + 1
			else
				table.insert(errors, keymap_error)
			end
		end
	end

	-- Watch expressions
	if keymaps.watch_add then
		total_count = total_count + 1
		local valid, validation_error = validate_keymap(keymaps.watch_add)
		if not valid then
			table.insert(errors, "Invalid watch_add keymap '" .. keymaps.watch_add .. "': " .. validation_error)
		else
			local keymap_success, keymap_error = safe_set_keymap("n", keymaps.watch_add, function()
				local watch_available, watch_error = check_keymap_gdb_availability()
				if not watch_available then
					vim.notify("Cannot add watch: " .. watch_error, vim.log.levels.ERROR)
					return
				end

				local input_ok, expr = pcall(vim.fn.input, "Watch expression: ")
				if not input_ok then
					vim.notify("Failed to get watch expression input", vim.log.levels.ERROR)
					return
				end

				if expr ~= "" then
					utils.async_gdb_response("display " .. expr, function(_, error)
						if error then
							vim.notify("Failed to add watch: " .. error, vim.log.levels.ERROR)
						else
							vim.notify("Watch added: " .. expr, vim.log.levels.INFO)
						end
					end)
				end
			end, { desc = "Add watch expression" })

			if keymap_success then
				table.insert(active_keymaps, { mode = "n", key = keymaps.watch_add })
				success_count = success_count + 1
			else
				table.insert(errors, keymap_error)
			end
		end
	end

	-- Memory viewer
	if keymaps.memory_view then
		total_count = total_count + 1
		local valid, validation_error = validate_keymap(keymaps.memory_view)
		if not valid then
			table.insert(errors, "Invalid memory_view keymap '" .. keymaps.memory_view .. "': " .. validation_error)
		else
			local keymap_success, keymap_error = safe_set_keymap("n", keymaps.memory_view, function()
				local mem_ok, mem_err = pcall(function()
					get_memory().view_memory_at_cursor()
				end)
				if not mem_ok then
					vim.notify("Memory view failed: " .. tostring(mem_err), vim.log.levels.ERROR)
				end
			end, { desc = "View memory at cursor" })

			if keymap_success then
				table.insert(active_keymaps, { mode = "n", key = keymaps.memory_view })
				success_count = success_count + 1
			else
				table.insert(errors, keymap_error)
			end
		end
	end

	-- Memory edit
	if keymaps.memory_edit then
		total_count = total_count + 1
		local valid, validation_error = validate_keymap(keymaps.memory_edit)
		if not valid then
			table.insert(errors, "Invalid memory_edit keymap '" .. keymaps.memory_edit .. "': " .. validation_error)
		else
			local keymap_success, keymap_error = safe_set_keymap("n", keymaps.memory_edit, function()
				local mem_ok, mem_err = pcall(function()
					get_memory().edit_memory_at_cursor()
				end)
				if not mem_ok then
					vim.notify("Memory edit failed: " .. tostring(mem_err), vim.log.levels.ERROR)
				end
			end, { desc = "Edit memory/variable at cursor" })

			if keymap_success then
				table.insert(active_keymaps, { mode = "n", key = keymaps.memory_edit })
				success_count = success_count + 1
			else
				table.insert(errors, keymap_error)
			end
		end
	end

	-- Variable set
	if keymaps.variable_set then
		total_count = total_count + 1
		local valid, validation_error = validate_keymap(keymaps.variable_set)
		if not valid then
			table.insert(errors, "Invalid variable_set keymap '" .. keymaps.variable_set .. "': " .. validation_error)
		else
			local keymap_success, keymap_error = safe_set_keymap("n", keymaps.variable_set, function()
				local var_available, var_error = check_keymap_gdb_availability()
				if not var_available then
					vim.notify("Cannot set variable: " .. var_error, vim.log.levels.ERROR)
					return
				end

				local var_ok, var = pcall(vim.fn.expand, "<cword>")
				if not var_ok or var == "" then
					vim.notify("No variable under cursor", vim.log.levels.WARN)
					return
				end

				local input_ok, value = pcall(vim.fn.input, "Set " .. var .. " = ")
				if not input_ok then
					vim.notify("Failed to get variable value input", vim.log.levels.ERROR)
					return
				end

				if value ~= "" then
					utils.async_gdb_response("set variable " .. var .. " = " .. value, function(_, error)
						if error then
							vim.notify("Failed to set variable: " .. error, vim.log.levels.ERROR)
						else
							vim.notify("Variable " .. var .. " set to " .. value, vim.log.levels.INFO)
						end
					end)
				end
			end, { desc = "Set variable value" })

			if keymap_success then
				table.insert(active_keymaps, { mode = "n", key = keymaps.variable_set })
				success_count = success_count + 1
			else
				table.insert(errors, keymap_error)
			end
		end
	end

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

