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

---Validate debugger executable
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
        table.insert(errors,
          "Duplicate keymap '" .. key .. "' used for both '" .. used_keys[key] .. "' and '" .. name .. "'")
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
  if memory_viewer.bytes_per_line and (type(memory_viewer.bytes_per_line) ~= "number" or memory_viewer.bytes_per_line <= 0) then
    table.insert(errors, "Memory viewer bytes_per_line must be a positive number")
  end

  return #errors == 0, errors
end

---Check termdebug availability
---@return boolean available, string|nil error_msg
local function check_termdebug_availability()
  if vim.fn.exists(':Termdebug') == 0 then
    -- Check if termdebug can be loaded
    local pack_ok, pack_err = pcall(vim.cmd, "packadd termdebug")
    if not pack_ok then
      return false, "Termdebug plugin not available and cannot be loaded: " .. tostring(pack_err)
    end

    -- Check again after loading
    if vim.fn.exists(':Termdebug') == 0 then
      return false, "Termdebug plugin loaded but commands not available"
    end
  end

  return true, nil
end

---Comprehensive configuration validation
---@param config table Configuration to validate
---@return ConfigValidationResult Validation result
local function validate_config(config)
  local result = {
    valid = true,
    errors = {},
    warnings = {}
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

---Setup the termdebug-enhanced plugin
---@param opts table|nil Configuration options
---@return boolean success, string[] errors Setup result
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

---Clean up all plugin resources
---@return number cleaned_count Number of resources cleaned up
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

---Get resource usage statistics
---@return table Resource usage statistics
function M.get_resource_stats()
  local stats = {
    total_resources = 0,
    by_type = {},
    performance = {}
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
