---@class Commands
local M = {}

---Safe module loading helper
---@param module_name string Module name to load
---@return table|nil module Module or nil if failed
local function safe_require(module_name)
    local ok, module = pcall(require, module_name)
    return ok and module or nil
end

---Create command with module loading
---@param name string Command name
---@param module_name string Module to load
---@param func_name string Function name to call
---@param opts table Command options
local function create_module_command(name, module_name, func_name, opts)
    vim.api.nvim_create_user_command(name, function(args)
        local module = safe_require(module_name)
        if module and module[func_name] then
            if args.args ~= "" then
                module[func_name](args.args)
            else
                module[func_name]()
            end
        else
            vim.notify("Failed to load " .. module_name, vim.log.levels.ERROR)
        end
    end, opts)
end

---Check termdebug availability
---@return boolean available
local function check_termdebug()
    if vim.fn.exists(":Termdebug") == 0 then
        local ok = pcall(vim.cmd, "packadd termdebug")
        return ok and vim.fn.exists(":Termdebug") ~= 0
    end
    return true
end

---Create all user commands
---@param config table Plugin configuration
function M.setup_commands(config)
    -- Main debugging commands
    vim.api.nvim_create_user_command("TermdebugStart", function(args)
        if not check_termdebug() then
            vim.notify("Termdebug not available", vim.log.levels.ERROR)
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
            vim.notify("Failed to start termdebug: " .. tostring(err), vim.log.levels.ERROR)
        end
    end, { nargs = "*", desc = "Start termdebug with enhanced features" })

    vim.api.nvim_create_user_command("TermdebugStop", function()
        pcall(vim.cmd, "TermdebugStop")
    end, { desc = "Stop termdebug" })

    -- Evaluation commands
    create_module_command("Evaluate", "termdebug-enhanced.evaluate", "evaluate_custom", 
        { nargs = 1, desc = "Evaluate expression" })
    
    create_module_command("EvaluateCursor", "termdebug-enhanced.evaluate", "evaluate_under_cursor", 
        { desc = "Evaluate expression under cursor" })

    -- Memory commands  
    create_module_command("MemoryView", "termdebug-enhanced.memory", "view_memory_at_cursor", 
        { nargs = "?", desc = "View memory at address or cursor" })

    -- Diagnostic command
    vim.api.nvim_create_user_command("TermdebugDiagnose", function()
        local init = safe_require("termdebug-enhanced")
        if init and init.print_diagnostics then
            init.print_diagnostics()
        end
    end, { desc = "Show diagnostic information" })
end

return M