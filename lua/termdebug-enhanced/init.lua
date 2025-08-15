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
---@field memory_popup string Show memory popup keymap
---@field variable_set string Set variable keymap

---@class termdebug-enhanced
local M = {}

local lib = require("termdebug-enhanced.lib")
local default_config = require("termdebug-enhanced.config").defaults

---@type TermdebugConfig
M.config = vim.deepcopy(default_config)

---Setup termdebug configuration
local function setup_termdebug()
    vim.g.termdebugger = M.config.debugger
    vim.g.termdebug_wide = 1
end

---Setup autocmds for plugin lifecycle
local function setup_autocmds()
    local group = vim.api.nvim_create_augroup("TermdebugEnhanced", { clear = true })
    
    vim.api.nvim_create_autocmd("User", {
        pattern = "TermdebugStartPost",
        group = group,
        callback = function()
            vim.g.termdebug_running = true
            local keymaps = lib.safe_require("termdebug-enhanced.keymaps")
            if keymaps and keymaps.setup_keymaps then
                keymaps.setup_keymaps(M.config.keymaps)
                vim.notify("Termdebug Enhanced: Active", vim.log.levels.INFO)
            end
        end,
    })
    
    vim.api.nvim_create_autocmd("User", {
        pattern = "TermdebugStopPost",
        group = group,
        callback = function()
            vim.g.termdebug_running = false
            local keymaps = lib.safe_require("termdebug-enhanced.keymaps")
            if keymaps and keymaps.cleanup_keymaps then
                keymaps.cleanup_keymaps()
            end
            M.cleanup_all_resources()
        end,
    })
    
    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = group,
        callback = function()
            vim.g.termdebug_running = false
            M.cleanup_all_resources()
        end,
    })
end

---Clean up all plugin resources
function M.cleanup_all_resources()
    local modules = {
        "termdebug-enhanced.utils",
        "termdebug-enhanced.memory", 
        "termdebug-enhanced.evaluate",
        "termdebug-enhanced.keymaps"
    }
    
    local cleanup_functions = {
        "cleanup_all_resources",
        "cleanup_all_windows",
        "cleanup_all_windows", 
        "cleanup_keymaps"
    }
    
    for i, module_name in ipairs(modules) do
        local module = lib.safe_require(module_name)
        local cleanup_func = cleanup_functions[i]
        if module and module[cleanup_func] then
            pcall(module[cleanup_func])
        end
    end
end

---Setup the plugin
---@param opts table|nil Configuration options
---@return boolean success, table|nil errors
function M.setup(opts)
    -- Validate opts is a table or nil
    if opts ~= nil and type(opts) ~= "table" then
        local err = "Configuration must be a table, got " .. type(opts)
        vim.notify(err, vim.log.levels.ERROR)
        return false, {err}
    end
    
    -- Merge configuration
    M.config = vim.tbl_deep_extend("force", M.config, opts or {})
    
    -- Validate configuration
    local validation = lib.safe_require("termdebug-enhanced.validation")
    if validation then
        local valid, errors = validation.validate_config(M.config)
        if not valid then
            vim.notify("Configuration errors:\n" .. table.concat(errors, "\n"), vim.log.levels.ERROR)
            return false, errors
        end
    end
    
    -- Setup components
    local setup_ok, setup_err = pcall(function()
        setup_termdebug()
        setup_autocmds()
        
        local commands = lib.safe_require("termdebug-enhanced.commands")
        if commands and commands.setup_commands then
            commands.setup_commands(M.config)
        end
    end)
    
    if setup_ok then
        vim.notify("Termdebug Enhanced setup completed", vim.log.levels.INFO)
        return true, {}
    else
        vim.notify("Termdebug Enhanced setup failed", vim.log.levels.ERROR)
        return false, {tostring(setup_err)}
    end
end

---Simple diagnostics
function M.print_diagnostics()
    print("=== Termdebug Enhanced Diagnostics ===")
    print("Debugger: " .. M.config.debugger)
    print("Debugger available: " .. tostring(vim.fn.executable(M.config.debugger) == 1))
    print("Termdebug available: " .. tostring(vim.fn.exists(":Termdebug") ~= 0))
    print("Debug session active: " .. tostring(vim.g.termdebug_running or false))
    
    if M.config.gdbinit then
        print("GDB init file: " .. M.config.gdbinit)
        print("GDB init readable: " .. tostring(vim.fn.filereadable(M.config.gdbinit) == 1))
    end
end

-- Export validation for runtime use
M.validate = lib.safe_require("termdebug-enhanced.validation")
if M.validate then
    M.validate = M.validate.validate
end

return M