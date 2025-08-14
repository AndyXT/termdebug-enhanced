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
---@return nil
local function setup_termdebug()
  vim.g.termdebugger = M.config.debugger
  vim.g.termdebug_wide = 1
end

---Setup autocmds for plugin lifecycle management
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
      -- Clean up any open windows
      local memory = require("termdebug-enhanced.memory")
      if memory.cleanup_all_windows then
        memory.cleanup_all_windows()
      end
    end,
  })

  -- Cleanup on Neovim exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      vim.g.termdebug_running = false
      local ok, memory = pcall(require, "termdebug-enhanced.memory")
      if ok and memory.cleanup_all_windows then
        memory.cleanup_all_windows()
      end
    end,
  })
end

---Validate plugin configuration
---@param config TermdebugConfig Configuration to validate
---@return boolean success True if config is valid
local function validate_config(config)
  local errors = {}
  
  if config.debugger and vim.fn.executable(config.debugger) == 0 then
    table.insert(errors, "Debugger executable not found: " .. config.debugger)
  end
  
  if config.gdbinit and config.gdbinit ~= "" and vim.fn.filereadable(config.gdbinit) == 0 then
    vim.notify("GDB init file not found: " .. config.gdbinit .. " (will be ignored)", vim.log.levels.WARN)
  end

  if #errors > 0 then
    vim.notify("Termdebug Enhanced configuration errors:\n" .. table.concat(errors, "\n"), vim.log.levels.ERROR)
    return false
  end

  return true
end

---Setup the termdebug-enhanced plugin
---@param opts TermdebugConfig|nil Configuration options
---@return nil
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  -- Validate configuration
  validate_config(M.config)

  setup_termdebug()
  setup_autocmds()

  -- Create commands
  vim.api.nvim_create_user_command("TermdebugStart", function(args)
    -- Check if termdebug is available
    if vim.fn.exists(':Termdebug') == 0 then
      vim.notify("Termdebug not available. Run :packadd termdebug", vim.log.levels.ERROR)
      return
    end

    local cmd_parts = {"Termdebug"}

    if M.config.gdbinit and vim.fn.filereadable(M.config.gdbinit) == 1 then
      table.insert(cmd_parts, "-x")
      table.insert(cmd_parts, vim.fn.shellescape(M.config.gdbinit))
    end

    if args.args ~= "" then
      -- Properly escape the arguments
      for arg in args.args:gmatch("%S+") do
        table.insert(cmd_parts, vim.fn.shellescape(arg))
      end
    end

    vim.cmd(table.concat(cmd_parts, " "))
  end, { nargs = "*", desc = "Start termdebug with enhanced features" })

  vim.api.nvim_create_user_command("TermdebugStop", function()
    vim.cmd("TermdebugStop")
  end, { desc = "Stop termdebug" })
end

return M