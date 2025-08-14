---@class TermdebugConfig
---@field debugger string Path to GDB executable
---@field gdbinit string Path to GDB initialization file
---@field popup PopupConfig Popup window configuration
---@field memory_viewer MemoryConfig Memory viewer configuration
---@field keymaps KeymapConfig Keymap configuration

---@class PopupConfig
---@field border string Border style
---@field width number Window width
---@field height number Window height
---@field position string Window position

---@class MemoryConfig
---@field width number Memory viewer width
---@field height number Memory viewer height
---@field format string Display format (hex/decimal/binary)
---@field bytes_per_line number Bytes per line in hex dump

---@class KeymapConfig
---@field continue string Continue execution keymap
---@field step_over string Step over keymap
---@field step_into string Step into keymap
---@field step_out string Step out keymap
---@field toggle_breakpoint string Toggle breakpoint keymap
---@field stop string Stop debugging keymap
---@field restart string Restart debugging keymap
---@field evaluate string Evaluate expression keymap
---@field evaluate_visual string Evaluate selection keymap
---@field watch_add string Add watch keymap
---@field watch_remove string Remove watch keymap
---@field memory_view string View memory keymap
---@field memory_edit string Edit memory keymap
---@field variable_set string Set variable keymap

---@class termdebug-enhanced
---@field config TermdebugConfig Plugin configuration
---@field setup function Setup function for the plugin
local M = {}

---@type TermdebugConfig
M.config = {
	-- Termdebug settings
	debugger = "arm-none-eabi-gdb.exe",
	gdbinit = ".gdbinit",

	-- UI settings
	popup = {
		border = "rounded",
		width = 60,
		height = 10,
		position = "cursor",
	},

	memory_viewer = {
		width = 80,
		height = 20,
		format = "hex", -- hex, decimal, binary
		bytes_per_line = 16,
	},

	-- Keybindings (VSCode-like)
	keymaps = {
		continue = "<F5>",
		step_over = "<F10>",
		step_into = "<F11>",
		step_out = "<S-F11>",
		toggle_breakpoint = "<F9>",
		stop = "<S-F5>",
		restart = "<C-S-F5>",
		evaluate = "K",
		evaluate_visual = "K",
		watch_add = "<leader>dw",
		watch_remove = "<leader>dW",
		memory_view = "<leader>dm",
		memory_edit = "<leader>dM",
		variable_set = "<leader>ds",
	},
}

---Setup termdebug with plugin configuration
---
---Configures Neovim's built-in termdebug plugin with the settings from this
---plugin's configuration. This includes setting the debugger executable and
---enabling wide mode for better layout.
---
---@return nil
local function setup_termdebug()
	vim.g.termdebugger = M.config.debugger
	vim.g.termdebug_wide = 1
end

---Setup autocmds for plugin lifecycle management
---
---Creates autocommands that manage the plugin's lifecycle in response to
---termdebug events. This includes setting up keymaps when debugging starts
---and cleaning up resources when debugging stops.
---
---Managed events:
---- TermdebugStartPost: Sets up keymaps and initializes debugging features
---- TermdebugStopPost: Cleans up keymaps and resources
---- VimLeavePre: Emergency cleanup on Neovim exit
---
---@return nil
local function setup_autocmds()
	local group = vim.api.nvim_create_augroup("TermdebugEnhanced", { clear = true })

	vim.api.nvim_create_autocmd("User", {
		pattern = "TermdebugStartPost",
		group = group,
		callback = function()
			vim.g.termdebug_running = true
			require("termdebug-enhanced.keymaps").setup_keymaps(M.config.keymaps)
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		pattern = "TermdebugStopPost",
		group = group,
		callback = function()
			vim.g.termdebug_running = false
			require("termdebug-enhanced.keymaps").cleanup_keymaps()
			-- Clean up all resources
			M.cleanup_all_resources()
		end,
	})

	-- Cleanup on Neovim exit
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			vim.g.termdebug_running = false
			M.cleanup_all_resources()
		end,
	})
end

---@class ConfigValidationResult
---@field valid boolean Whether configuration is valid
---@field errors string[] List of validation errors
---@field warnings string[] List of validation warnings

---Validate debugger executable availability and format
---
---Checks that the specified debugger executable exists and is accessible.
---Provides helpful error messages for common issues like missing executables,
---Windows/Unix path mismatches, and PATH configuration problems.
---
---@param debugger string|nil Debugger path to validate
---@return boolean valid, string|nil error_msg
local function validate_debugger(debugger)
	if not debugger or debugger == "" then
		return false, "No debugger specified"
	end

	local trimmed = vim.trim(debugger)
	if trimmed == "" then
		return false, "Debugger path contains only whitespace"
	end

	-- Check if executable exists
	if vim.fn.executable(trimmed) == 0 then
		-- Try to provide more helpful error message
		if trimmed:match("%.exe$") and vim.fn.has("win32") == 0 then
			return false, "Debugger executable not found: " .. trimmed .. " (Windows executable on non-Windows system?)"
		elseif not trimmed:match("%.exe$") and vim.fn.has("win32") == 1 then
			return false, "Debugger executable not found: " .. trimmed .. " (missing .exe extension on Windows?)"
		else
			return false, "Debugger executable not found: " .. trimmed .. " (check PATH or provide full path)"
		end
	end

	return true, nil
end

---Validate GDB init file
---@param gdbinit string|nil GDB init file path to validate
---@return boolean valid, string|nil error_msg, string|nil warning_msg
local function validate_gdbinit(gdbinit)
	if not gdbinit or gdbinit == "" then
		return true, nil, nil -- Optional field
	end

	local trimmed = vim.trim(gdbinit)
	if trimmed == "" then
		return false, "GDB init file path contains only whitespace", nil
	end

	-- Check if file exists and is readable
	if vim.fn.filereadable(trimmed) == 0 then
		local exists_ok, exists = pcall(vim.fn.fileexists, trimmed)
		if exists_ok and exists == 1 then
			return false, nil, "GDB init file exists but is not readable: " .. trimmed
		else
			return false, nil, "GDB init file not found: " .. trimmed .. " (will be ignored)"
		end
	end

	return true, nil, nil
end

---Validate keymap configuration
---@param keymaps table|nil Keymap configuration to validate
---@return boolean valid, string[] errors
local function validate_keymaps(keymaps)
	local errors = {}

	if not keymaps then
		return true, {} -- Optional field
	end

	if type(keymaps) ~= "table" then
		table.insert(errors, "Keymaps configuration must be a table")
		return false, errors
	end

	-- Check for duplicate keymaps
	local used_keys = {}
	for name, key in pairs(keymaps) do
		if key and key ~= "" then
			if used_keys[key] then
				table.insert(
					errors,
					"Duplicate keymap '" .. key .. "' used for both '" .. used_keys[key] .. "' and '" .. name .. "'"
				)
			else
				used_keys[key] = name
			end

			-- Basic keymap format validation
			if type(key) ~= "string" then
				table.insert(errors, "Keymap '" .. name .. "' must be a string")
			elseif vim.trim(key) == "" then
				table.insert(errors, "Keymap '" .. name .. "' cannot be empty or whitespace")
			end
		end
	end

	return #errors == 0, errors
end

---Validate popup configuration
---@param popup table|nil Popup configuration to validate
---@return boolean valid, string[] errors
local function validate_popup_config(popup)
	local errors = {}

	if not popup then
		return true, {} -- Optional field
	end

	if type(popup) ~= "table" then
		table.insert(errors, "Popup configuration must be a table")
		return false, errors
	end

	-- Validate width
	if popup.width and (type(popup.width) ~= "number" or popup.width <= 0) then
		table.insert(errors, "Popup width must be a positive number")
	end

	-- Validate height
	if popup.height and (type(popup.height) ~= "number" or popup.height <= 0) then
		table.insert(errors, "Popup height must be a positive number")
	end

	-- Validate border
	if popup.border and type(popup.border) ~= "string" then
		table.insert(errors, "Popup border must be a string")
	end

	return #errors == 0, errors
end

---Validate memory viewer configuration
---@param memory_viewer table|nil Memory viewer configuration to validate
---@return boolean valid, string[] errors
local function validate_memory_config(memory_viewer)
	local errors = {}

	if not memory_viewer then
		return true, {} -- Optional field
	end

	if type(memory_viewer) ~= "table" then
		table.insert(errors, "Memory viewer configuration must be a table")
		return false, errors
	end

	-- Validate width
	if memory_viewer.width and (type(memory_viewer.width) ~= "number" or memory_viewer.width <= 0) then
		table.insert(errors, "Memory viewer width must be a positive number")
	end

	-- Validate height
	if memory_viewer.height and (type(memory_viewer.height) ~= "number" or memory_viewer.height <= 0) then
		table.insert(errors, "Memory viewer height must be a positive number")
	end

	-- Validate format
	if memory_viewer.format then
		local valid_formats = { hex = true, decimal = true, binary = true }
		if not valid_formats[memory_viewer.format] then
			table.insert(errors, "Memory viewer format must be 'hex', 'decimal', or 'binary'")
		end
	end

	-- Validate bytes_per_line
	if
		memory_viewer.bytes_per_line
		and (type(memory_viewer.bytes_per_line) ~= "number" or memory_viewer.bytes_per_line <= 0)
	then
		table.insert(errors, "Memory viewer bytes_per_line must be a positive number")
	end

	return #errors == 0, errors
end

---Check termdebug availability
---@return boolean available, string|nil error_msg
local function check_termdebug_availability()
	if vim.fn.exists(":Termdebug") == 0 then
		-- Check if termdebug can be loaded
		local pack_ok, pack_err = pcall(vim.cmd, "packadd termdebug")
		if not pack_ok then
			return false, "Termdebug plugin not available and cannot be loaded: " .. tostring(pack_err)
		end

		-- Check again after loading
		if vim.fn.exists(":Termdebug") == 0 then
			return false, "Termdebug plugin loaded but commands not available"
		end
	end

	return true, nil
end

---Comprehensive configuration validation with detailed reporting
---
---Performs thorough validation of the entire plugin configuration, checking
---all settings for correctness and compatibility. Returns detailed results
---including both errors (which prevent operation) and warnings (which allow
---operation but may indicate issues).
---
---Validation includes:
---- Debugger executable availability
---- GDB init file accessibility
---- Keymap configuration and conflicts
---- UI configuration (popup, memory viewer)
---- Termdebug plugin availability
---
---@param config table Configuration to validate
---@return ConfigValidationResult Validation result with errors and warnings
local function validate_config(config)
	local result = {
		valid = true,
		errors = {},
		warnings = {},
	}

	if not config then
		table.insert(result.errors, "Configuration is nil")
		result.valid = false
		return result
	end

	if type(config) ~= "table" then
		table.insert(result.errors, "Configuration must be a table")
		result.valid = false
		return result
	end

	-- Validate debugger
	local debugger_valid, debugger_error = validate_debugger(config.debugger)
	if not debugger_valid then
		table.insert(result.errors, debugger_error)
		result.valid = false
	end

	-- Validate GDB init file
	local gdbinit_valid, gdbinit_error, gdbinit_warning = validate_gdbinit(config.gdbinit)
	if not gdbinit_valid then
		table.insert(result.errors, gdbinit_error)
		result.valid = false
	elseif gdbinit_warning then
		table.insert(result.warnings, gdbinit_warning)
	end

	-- Validate keymaps
	local keymaps_valid, keymap_errors = validate_keymaps(config.keymaps)
	if not keymaps_valid then
		for _, error in ipairs(keymap_errors) do
			table.insert(result.errors, error)
		end
		result.valid = false
	end

	-- Validate popup configuration
	local popup_valid, popup_errors = validate_popup_config(config.popup)
	if not popup_valid then
		for _, error in ipairs(popup_errors) do
			table.insert(result.errors, error)
		end
		result.valid = false
	end

	-- Validate memory viewer configuration
	local memory_valid, memory_errors = validate_memory_config(config.memory_viewer)
	if not memory_valid then
		for _, error in ipairs(memory_errors) do
			table.insert(result.errors, error)
		end
		result.valid = false
	end

	-- Check termdebug availability
	local termdebug_available, termdebug_error = check_termdebug_availability()
	if not termdebug_available then
		table.insert(result.warnings, termdebug_error)
	end

	return result
end

---Setup the termdebug-enhanced plugin with comprehensive error handling
---
---Initializes the plugin with the provided configuration, performing validation,
---setting up termdebug integration, creating autocommands, and registering user
---commands. This is the main entry point for plugin initialization.
---
---The setup process includes:
---1. Configuration merging and validation
---2. Termdebug plugin configuration
---3. Autocommand registration for lifecycle management
---4. User command creation (TermdebugStart, TermdebugStop)
---5. Comprehensive error reporting and recovery
---
---@param opts table|nil Configuration options to merge with defaults
---@return boolean success, string[] errors Setup result with detailed error information
function M.setup(opts)
	local setup_errors = {}

	-- Merge configuration with error handling
	local merge_ok, merge_err = pcall(function()
		M.config = vim.tbl_deep_extend("force", M.config, opts or {})
	end)

	if not merge_ok then
		table.insert(setup_errors, "Failed to merge configuration: " .. tostring(merge_err))
		return false, setup_errors
	end

	-- Validate configuration
	local validation_result = validate_config(M.config)

	-- Report validation results
	if #validation_result.warnings > 0 then
		vim.notify("Configuration warnings:\n" .. table.concat(validation_result.warnings, "\n"), vim.log.levels.WARN)
	end

	if not validation_result.valid then
		local error_msg = "Configuration validation failed:\n" .. table.concat(validation_result.errors, "\n")
		vim.notify(error_msg, vim.log.levels.ERROR)
		return false, validation_result.errors
	end

	-- Setup termdebug with error handling
	local termdebug_ok, termdebug_err = pcall(setup_termdebug)
	if not termdebug_ok then
		table.insert(setup_errors, "Failed to setup termdebug: " .. tostring(termdebug_err))
	end

	-- Setup autocmds with error handling
	local autocmd_ok, autocmd_err = pcall(setup_autocmds)
	if not autocmd_ok then
		table.insert(setup_errors, "Failed to setup autocmds: " .. tostring(autocmd_err))
	end

	-- Create commands with error handling
	local cmd_ok, cmd_err = pcall(function()
		vim.api.nvim_create_user_command("TermdebugStart", function(args)
			-- Check if termdebug is available
			local available, availability_error = check_termdebug_availability()
			if not available then
				vim.notify(availability_error, vim.log.levels.ERROR)
				return
			end

			local cmd_parts = { "Termdebug" }

			-- Add GDB init file if configured and readable
			if M.config.gdbinit and vim.fn.filereadable(M.config.gdbinit) == 1 then
				table.insert(cmd_parts, "-x")
				local escape_ok, escaped_init = pcall(vim.fn.shellescape, M.config.gdbinit)
				if escape_ok then
					table.insert(cmd_parts, escaped_init)
				else
					vim.notify("Failed to escape GDB init file path", vim.log.levels.WARN)
				end
			end

			-- Add command arguments
			if args.args ~= "" then
				-- Properly escape the arguments
				for arg in args.args:gmatch("%S+") do
					local escape_ok, escaped_arg = pcall(vim.fn.shellescape, arg)
					if escape_ok then
						table.insert(cmd_parts, escaped_arg)
					else
						vim.notify("Failed to escape argument: " .. arg, vim.log.levels.WARN)
					end
				end
			end

			-- Execute termdebug command
			local exec_ok, exec_err = pcall(vim.cmd, table.concat(cmd_parts, " "))
			if not exec_ok then
				vim.notify("Failed to start termdebug: " .. tostring(exec_err), vim.log.levels.ERROR)
			end
		end, { nargs = "*", desc = "Start termdebug with enhanced features" })

		vim.api.nvim_create_user_command("TermdebugStop", function()
			local stop_ok, stop_err = pcall(vim.cmd, "TermdebugStop")
			if not stop_ok then
				vim.notify("Failed to stop termdebug: " .. tostring(stop_err), vim.log.levels.ERROR)
			end
		end, { desc = "Stop termdebug" })

		-- Diagnostic command
		vim.api.nvim_create_user_command("TermdebugDiagnose", function()
			M.print_diagnostics()
		end, { desc = "Show termdebug-enhanced diagnostic information" })

		-- Configuration reload command
		vim.api.nvim_create_user_command("TermdebugReloadConfig", function(args)
			if args.args ~= "" then
				-- Try to load config from file
				local config_file = args.args
				if vim.fn.filereadable(config_file) == 1 then
					local load_ok, new_config = pcall(dofile, config_file)
					if load_ok and type(new_config) == "table" then
						local success, errors = M.reload_config(new_config)
						if not success then
							vim.notify("Config reload failed:\n" .. table.concat(errors, "\n"), vim.log.levels.ERROR)
						end
					else
						vim.notify("Failed to load config file: " .. tostring(new_config), vim.log.levels.ERROR)
					end
				else
					vim.notify("Config file not readable: " .. config_file, vim.log.levels.ERROR)
				end
			else
				-- Reload current config (re-validate)
				local success, errors = M.reload_config({})
				if not success then
					vim.notify("Config validation failed:\n" .. table.concat(errors, "\n"), vim.log.levels.ERROR)
				end
			end
		end, { nargs = "?", desc = "Reload termdebug-enhanced configuration", complete = "file" })

		-- Validation commands for runtime use
		vim.api.nvim_create_user_command("TermdebugValidateAddress", function(args)
			if args.args == "" then
				vim.notify("Usage: TermdebugValidateAddress <address>", vim.log.levels.INFO)
				return
			end
			local valid, error_msg = M.validate.address(args.args)
			if valid then
				vim.notify("✓ Address '" .. args.args .. "' is valid", vim.log.levels.INFO)
			else
				vim.notify("✗ Address '" .. args.args .. "' is invalid: " .. error_msg, vim.log.levels.ERROR)
			end
		end, { nargs = 1, desc = "Validate memory address format" })

		vim.api.nvim_create_user_command("TermdebugValidateExpression", function(args)
			if args.args == "" then
				vim.notify("Usage: TermdebugValidateExpression <expression>", vim.log.levels.INFO)
				return
			end
			local valid, error_msg = M.validate.expression(args.args)
			if valid then
				vim.notify("✓ Expression '" .. args.args .. "' is valid", vim.log.levels.INFO)
			else
				vim.notify("✗ Expression '" .. args.args .. "' is invalid: " .. error_msg, vim.log.levels.ERROR)
			end
		end, { nargs = 1, desc = "Validate GDB expression syntax" })
	end)

	if not cmd_ok then
		table.insert(setup_errors, "Failed to create user commands: " .. tostring(cmd_err))
	end

	-- Report setup results
	if #setup_errors > 0 then
		vim.notify("Plugin setup completed with errors:\n" .. table.concat(setup_errors, "\n"), vim.log.levels.WARN)
		return false, setup_errors
	else
		vim.notify("Termdebug Enhanced setup completed successfully", vim.log.levels.INFO)
		return true, {}
	end
end

---Clean up all plugin resources across all modules
---
---Performs comprehensive cleanup of all plugin resources including windows,
---buffers, timers, and other objects created during the debugging session.
---This function coordinates cleanup across all plugin modules and provides
---detailed reporting of the cleanup process.
---
---Cleanup includes:
---- Utils module: timers, caches, tracked resources
---- Memory module: memory viewer windows and buffers
---- Evaluate module: evaluation popup windows
---- Keymaps module: debugging keymaps
---
---@return number cleaned_count Number of resources successfully cleaned up
function M.cleanup_all_resources()
	local total_cleaned = 0

	-- Clean up utils resources
	local utils_ok, utils = pcall(require, "termdebug-enhanced.utils")
	if utils_ok and utils.cleanup_all_resources then
		total_cleaned = total_cleaned + utils.cleanup_all_resources()
	end

	-- Clean up memory windows
	local memory_ok, memory = pcall(require, "termdebug-enhanced.memory")
	if memory_ok and memory.cleanup_all_windows then
		memory.cleanup_all_windows()
	end

	-- Clean up evaluation windows
	local eval_ok, evaluate = pcall(require, "termdebug-enhanced.evaluate")
	if eval_ok and evaluate.cleanup_all_windows then
		evaluate.cleanup_all_windows()
	end

	-- Clean up keymaps
	local keymaps_ok, keymaps = pcall(require, "termdebug-enhanced.keymaps")
	if keymaps_ok and keymaps.cleanup_keymaps then
		keymaps.cleanup_keymaps()
	end

	if total_cleaned > 0 then
		vim.notify("Cleaned up " .. total_cleaned .. " resources", vim.log.levels.INFO)
	end

	return total_cleaned
end

---Runtime validation for user inputs (addresses, expressions, memory values)
---
---Provides validation functions for common user inputs during debugging sessions.
---These functions can be used by other modules to validate user input before
---processing, preventing errors and providing helpful feedback.
---
---@class RuntimeValidation
M.validate = {}

---Validate memory address format
---@param address string Address to validate
---@return boolean valid, string|nil error_msg
function M.validate.address(address)
	if not address or address == "" then
		return false, "Empty address"
	end

	local trimmed = vim.trim(address)
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

---Validate expression syntax for GDB evaluation
---@param expression string Expression to validate
---@return boolean valid, string|nil error_msg
function M.validate.expression(expression)
	if not expression or expression == "" then
		return false, "Empty expression"
	end

	local trimmed = vim.trim(expression)
	if trimmed == "" then
		return false, "Expression contains only whitespace"
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

---Validate hex value for memory editing
---@param hex_value string Hex value to validate
---@return boolean valid, string|nil error_msg
function M.validate.hex_value(hex_value)
	if not hex_value or hex_value == "" then
		return false, "Empty hex value"
	end

	local trimmed = vim.trim(hex_value)
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

---Validate GDB command for safety
---@param command string GDB command to validate
---@return boolean valid, string|nil error_msg
function M.validate.gdb_command(command)
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

---Configuration hot-reloading with proper validation
---
---Allows updating the plugin configuration at runtime while maintaining
---validation and consistency. This function validates the new configuration,
---applies changes, and updates any active debugging sessions.
---
---@param new_config table New configuration to apply
---@return boolean success, string[] errors Hot-reload result with detailed error information
function M.reload_config(new_config)
	local reload_errors = {}

	-- Validate new configuration
	local validation_result = validate_config(new_config)

	if not validation_result.valid then
		table.insert(reload_errors, "Configuration validation failed during hot-reload")
		for _, error in ipairs(validation_result.errors) do
			table.insert(reload_errors, "  " .. error)
		end
		return false, reload_errors
	end

	-- Store old config for rollback
	local old_config = vim.deepcopy(M.config)

	-- Apply new configuration with error handling
	local apply_ok, apply_err = pcall(function()
		M.config = vim.tbl_deep_extend("force", M.config, new_config)
	end)

	if not apply_ok then
		table.insert(reload_errors, "Failed to apply new configuration: " .. tostring(apply_err))
		return false, reload_errors
	end

	-- Update termdebug settings
	local termdebug_ok, termdebug_err = pcall(setup_termdebug)
	if not termdebug_ok then
		-- Rollback configuration
		M.config = old_config
		table.insert(reload_errors, "Failed to update termdebug settings, rolled back: " .. tostring(termdebug_err))
		return false, reload_errors
	end

	-- If debugging is active, update keymaps
	if vim.g.termdebug_running then
		local keymaps_ok, keymaps = pcall(require, "termdebug-enhanced.keymaps")
		if keymaps_ok then
			-- Clean up old keymaps
			local cleanup_ok, cleanup_errors = keymaps.cleanup_keymaps()
			if not cleanup_ok then
				vim.notify("Warning: Some old keymaps failed to clean up during reload", vim.log.levels.WARN)
			end

			-- Set up new keymaps
			local setup_ok, setup_errors = keymaps.setup_keymaps(M.config.keymaps)
			if not setup_ok then
				table.insert(reload_errors, "Failed to update keymaps during reload")
				for _, error in ipairs(setup_errors) do
					table.insert(reload_errors, "  " .. error)
				end
			end
		end
	end

	-- Report warnings if any
	if #validation_result.warnings > 0 then
		vim.notify("Configuration reload warnings:\n" .. table.concat(validation_result.warnings, "\n"), vim.log.levels.WARN)
	end

	-- Report results
	if #reload_errors > 0 then
		vim.notify("Configuration reload completed with errors:\n" .. table.concat(reload_errors, "\n"), vim.log.levels.WARN)
		return false, reload_errors
	else
		vim.notify("Configuration reloaded successfully", vim.log.levels.INFO)
		return true, {}
	end
end

---Diagnostic commands for troubleshooting plugin setup issues
---
---Provides comprehensive diagnostic information about the plugin state,
---configuration, and environment. This helps users troubleshoot setup
---issues and verify that everything is working correctly.
---
---@return table Diagnostic information
function M.diagnose()
	local diagnostics = {
		plugin_info = {
			version = "1.0.0", -- TODO: Get from plugin metadata
			loaded = true,
		},
		configuration = {
			valid = false,
			errors = {},
			warnings = {},
		},
		environment = {
			neovim_version = vim.version(),
			platform = vim.loop.os_uname(),
			termdebug_available = false,
			debugger_available = false,
		},
		runtime_state = {
			debugging_active = vim.g.termdebug_running or false,
			resources = M.get_resource_stats(),
		},
	}

	-- Validate current configuration
	local validation_result = validate_config(M.config)
	diagnostics.configuration.valid = validation_result.valid
	diagnostics.configuration.errors = validation_result.errors
	diagnostics.configuration.warnings = validation_result.warnings

	-- Check termdebug availability
	local termdebug_available, termdebug_error = check_termdebug_availability()
	diagnostics.environment.termdebug_available = termdebug_available
	if not termdebug_available then
		diagnostics.environment.termdebug_error = termdebug_error
	end

	-- Check debugger availability
	local debugger_available, debugger_error = validate_debugger(M.config.debugger)
	diagnostics.environment.debugger_available = debugger_available
	if not debugger_available then
		diagnostics.environment.debugger_error = debugger_error
	end

	-- Check GDB init file
	if M.config.gdbinit then
		local gdbinit_valid, gdbinit_error, gdbinit_warning = validate_gdbinit(M.config.gdbinit)
		diagnostics.environment.gdbinit_valid = gdbinit_valid
		if gdbinit_error then
			diagnostics.environment.gdbinit_error = gdbinit_error
		end
		if gdbinit_warning then
			diagnostics.environment.gdbinit_warning = gdbinit_warning
		end
	end

	return diagnostics
end

---Print formatted diagnostic information
---@return nil
function M.print_diagnostics()
	local diag = M.diagnose()

	print("=== Termdebug Enhanced Diagnostics ===")
	print()

	-- Plugin info
	print("Plugin Information:")
	print("  Version: " .. diag.plugin_info.version)
	print("  Loaded: " .. tostring(diag.plugin_info.loaded))
	print()

	-- Configuration
	print("Configuration:")
	print("  Valid: " .. tostring(diag.configuration.valid))
	if #diag.configuration.errors > 0 then
		print("  Errors:")
		for _, error in ipairs(diag.configuration.errors) do
			print("    - " .. error)
		end
	end
	if #diag.configuration.warnings > 0 then
		print("  Warnings:")
		for _, warning in ipairs(diag.configuration.warnings) do
			print("    - " .. warning)
		end
	end
	print()

	-- Environment
	print("Environment:")
	print("  Neovim: " .. vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch)
	print("  Platform: " .. diag.environment.platform.sysname .. " " .. diag.environment.platform.machine)
	print("  Termdebug Available: " .. tostring(diag.environment.termdebug_available))
	if diag.environment.termdebug_error then
		print("    Error: " .. diag.environment.termdebug_error)
	end
	print("  Debugger Available: " .. tostring(diag.environment.debugger_available))
	if diag.environment.debugger_error then
		print("    Error: " .. diag.environment.debugger_error)
	end
	if diag.environment.gdbinit_valid ~= nil then
		print("  GDB Init File Valid: " .. tostring(diag.environment.gdbinit_valid))
		if diag.environment.gdbinit_error then
			print("    Error: " .. diag.environment.gdbinit_error)
		end
		if diag.environment.gdbinit_warning then
			print("    Warning: " .. diag.environment.gdbinit_warning)
		end
	end
	print()

	-- Runtime state
	print("Runtime State:")
	print("  Debugging Active: " .. tostring(diag.runtime_state.debugging_active))
	print("  Total Resources: " .. diag.runtime_state.resources.total_resources)
	if diag.runtime_state.resources.performance.async_operations_count then
		print("  Async Operations: " .. diag.runtime_state.resources.performance.async_operations_count)
		print("  Avg Response Time: " .. string.format("%.1fms", diag.runtime_state.resources.performance.avg_response_time))
	end
	print()

	-- Recommendations
	print("Recommendations:")
	if not diag.configuration.valid then
		print("  - Fix configuration errors before using the plugin")
	end
	if not diag.environment.termdebug_available then
		print("  - Run ':packadd termdebug' to load the termdebug plugin")
	end
	if not diag.environment.debugger_available then
		print("  - Install the debugger or update the 'debugger' configuration")
	end
	if #diag.configuration.warnings > 0 then
		print("  - Review configuration warnings for potential issues")
	end
end

---Get resource usage statistics
---@return table Resource usage statistics
function M.get_resource_stats()
	local stats = {
		total_resources = 0,
		by_type = {},
		performance = {},
	}

	local utils_ok, utils = pcall(require, "termdebug-enhanced.utils")
	if utils_ok then
		if utils.get_resource_stats then
			stats.by_type = utils.get_resource_stats()
			for _, count in pairs(stats.by_type) do
				stats.total_resources = stats.total_resources + count
			end
		end
		if utils.get_performance_metrics then
			stats.performance = utils.get_performance_metrics()
		end
	end

	return stats
end

return M
