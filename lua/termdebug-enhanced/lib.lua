---@class termdebug-enhanced.lib
---Common utility functions shared across all modules
local M = {}

---Safely require a module without throwing errors
---@param module_name string The module name to require
---@return table|nil module The module or nil if loading failed
function M.safe_require(module_name)
    local ok, module = pcall(require, module_name)
    return ok and module or nil
end

---Lazy load a module (useful for avoiding circular dependencies)
---@param module_name string The module name to require
---@return function loader A function that returns the module when called
function M.lazy_require(module_name)
    return function()
        return M.safe_require(module_name)
    end
end

---Check if debugging is active
---@return boolean
function M.is_debugging()
    return vim.g.termdebug_running == true
end

---Check if termdebug is available
---@return boolean
function M.is_termdebug_available()
    if vim.fn.exists(":Termdebug") == 0 then
        -- Try to load termdebug
        local ok = pcall(vim.cmd, "packadd termdebug")
        return ok and vim.fn.exists(":Termdebug") ~= 0
    end
    return true
end

---Simple notification wrapper
---@param msg string Message to display
---@param level number|nil Vim log level (default: INFO)
function M.notify(msg, level)
    vim.notify(msg, level or vim.log.levels.INFO)
end

---Error notification
---@param msg string Error message
function M.error(msg)
    vim.notify(msg, vim.log.levels.ERROR)
end

---Warning notification
---@param msg string Warning message
function M.warn(msg)
    vim.notify(msg, vim.log.levels.WARN)
end

return M