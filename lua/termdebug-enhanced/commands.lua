---@class Commands
local M = {}

local lib = require("termdebug-enhanced.lib")

---Create command with module loading
---@param name string Command name
---@param module_name string Module to load
---@param func_name string Function name to call
---@param opts table Command options
local function create_module_command(name, module_name, func_name, opts)
	vim.api.nvim_create_user_command(name, function(args)
		local module = lib.safe_require(module_name)
		if module and module[func_name] then
			if args.args ~= "" then
				module[func_name](args.args)
			else
				module[func_name]()
			end
		else
			lib.error("Failed to load " .. module_name)
		end
	end, opts)
end

---Create all user commands
---@param config table Plugin configuration
function M.setup_commands(config)
	-- Main debugging commands
	vim.api.nvim_create_user_command("TermdebugStart", function(args)
		if not lib.is_termdebug_available() then
			lib.error("Termdebug not available")
			return
		end

		local cmd_parts = { "Termdebug" }

		if config.gdbinit and vim.fn.filereadable(config.gdbinit) == 1 then
			table.insert(cmd_parts, "-x " .. vim.fn.shellescape(config.gdbinit))
		end

		if args.args ~= "" then
			table.insert(cmd_parts, args.args)
		end

		local ok, err = pcall(vim.cmd, table.concat(cmd_parts, " "))
		if not ok then
			lib.error("Failed to start termdebug: " .. tostring(err))
		end
	end, { nargs = "*", desc = "Start termdebug with enhanced features" })

	vim.api.nvim_create_user_command("TermdebugStop", function()
		pcall(vim.cmd, "TermdebugStop")
	end, { desc = "Stop termdebug" })

	-- Evaluation commands
	create_module_command(
		"Evaluate",
		"termdebug-enhanced.evaluate",
		"evaluate_custom",
		{ nargs = 1, desc = "Evaluate expression" }
	)

	create_module_command(
		"EvaluateCursor",
		"termdebug-enhanced.evaluate",
		"evaluate_under_cursor",
		{ desc = "Evaluate expression under cursor" }
	)

	-- Memory commands
	create_module_command(
		"MemoryView",
		"termdebug-enhanced.memory",
		"view_memory_at_cursor",
		{ nargs = "?", desc = "View memory at address or cursor" }
	)

	-- Diagnostic command
	vim.api.nvim_create_user_command("TermdebugDiagnose", function()
		local init = lib.safe_require("termdebug-enhanced")
		if init and init.print_diagnostics then
			init.print_diagnostics()
		end
	end, { desc = "Show diagnostic information" })
end

return M

