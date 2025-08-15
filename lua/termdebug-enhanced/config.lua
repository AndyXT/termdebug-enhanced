---@class termdebug-enhanced.config
---Centralized configuration management for the plugin
---Provides a single source of truth for configuration access across all modules
local M = {}

---Default configuration values
---@type TermdebugConfig
M.defaults = {
	debugger = "arm-none-eabi-gdb.exe",
	gdbinit = ".gdbinit",

	popup = {
		border = "rounded",
		width = 60,
		height = 10,
		position = "cursor",
	},

	memory_viewer = {
		width = 80,
		height = 20,
		format = "hex",
		bytes_per_line = 16,
	},

	keymaps = {
		continue = "<F5>",
		step_over = "<F10>",
		step_into = "<F11>",
		step_out = "<S-F11>",
		toggle_breakpoint = "<F9>",
		stop = "<S-F5>",
		restart = "<C-S-F5>",
		evaluate = "K",
		evaluate_visual = "<leader>K",
		watch_add = "<leader>dw",
		watch_remove = "<leader>dW",
		memory_view = "<leader>dm",
		memory_edit = "<leader>dM",
		memory_popup = "<leader>dp",
		variable_set = "<leader>ds",
	},
}

---Get the current configuration
---Attempts to load from the main module, falls back to defaults if not available
---@return TermdebugConfig
function M.get()
	-- Try to get config from main module
	local ok, main = pcall(require, "termdebug-enhanced")
	if ok and main and type(main) == "table" and main.config and type(main.config) == "table" then
		return main.config
	end

	-- Return defaults if main module not loaded
	return M.defaults
end

---Get a specific configuration section
---@param section string The configuration section to retrieve (e.g., "popup", "memory_viewer")
---@return table|nil
function M.get_section(section)
	local config = M.get()
	return config[section]
end

---Get popup configuration
---@return PopupConfig
function M.get_popup()
	return M.get_section("popup") or M.defaults.popup
end

---Get memory viewer configuration
---@return MemoryConfig
function M.get_memory_viewer()
	return M.get_section("memory_viewer") or M.defaults.memory_viewer
end

---Get keymaps configuration
---@return KeymapConfig
function M.get_keymaps()
	return M.get_section("keymaps") or M.defaults.keymaps
end

return M

