-- Comprehensive diagnostic script for popup issues
-- Run this in Neovim with: :luafile diagnose_popup_issue.lua

print("=== Termdebug Enhanced Popup Diagnostics ===")
print()

-- Check Neovim version
print("Neovim version: " .. vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch)

-- Check if floating windows are supported
local float_supported = vim.fn.has('nvim-0.4') == 1
print("Floating windows supported: " .. tostring(float_supported))

-- Test basic floating window creation
print("\n--- Testing Basic Floating Window Creation ---")
local test_buf = vim.api.nvim_create_buf(false, true)
print("Created test buffer: " .. test_buf)

vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, {"Test line 1", "Test line 2"})
print("Set buffer content")

local win_opts = {
    relative = "cursor",
    row = 1,
    col = 0,
    width = 20,
    height = 3,
    style = "minimal",
    border = "rounded"
}

local test_win = vim.api.nvim_open_win(test_buf, false, win_opts)
print("Created test window: " .. test_win)

-- Close test window after a moment
vim.defer_fn(function()
    if vim.api.nvim_win_is_valid(test_win) then
        vim.api.nvim_win_close(test_win, true)
        print("Closed test window")
    end
    if vim.api.nvim_buf_is_valid(test_buf) then
        vim.api.nvim_buf_delete(test_buf, {force = true})
        print("Deleted test buffer")
    end
end, 2000)

print("Basic floating window test completed - window should appear for 2 seconds")

-- Test module loading
print("\n--- Testing Module Loading ---")
local modules_to_test = {
    "termdebug-enhanced",
    "termdebug-enhanced.evaluate",
    "termdebug-enhanced.utils"
}

for _, module_name in ipairs(modules_to_test) do
    local ok, module = pcall(require, module_name)
    if ok then
        print("✓ " .. module_name .. " loaded successfully")
    else
        print("✗ " .. module_name .. " failed to load: " .. tostring(module))
    end
end

-- Test evaluate module functions
print("\n--- Testing Evaluate Module Functions ---")
local eval_ok, evaluate = pcall(require, "termdebug-enhanced.evaluate")
if eval_ok then
    local functions_to_test = {
        "evaluate_under_cursor",
        "evaluate_selection", 
        "evaluate_custom",
        "test_popup"
    }
    
    for _, func_name in ipairs(functions_to_test) do
        if evaluate[func_name] then
            print("✓ " .. func_name .. " function exists")
        else
            print("✗ " .. func_name .. " function missing")
        end
    end
else
    print("✗ Cannot test evaluate functions - module failed to load")
end

-- Test configuration
print("\n--- Testing Configuration ---")
local config_ok, main_module = pcall(require, "termdebug-enhanced")
if config_ok and main_module.config then
    print("✓ Main configuration loaded")
    if main_module.config.popup then
        print("✓ Popup configuration exists:")
        print("  Border: " .. (main_module.config.popup.border or "none"))
        print("  Width: " .. (main_module.config.popup.width or "unknown"))
        print("  Height: " .. (main_module.config.popup.height or "unknown"))
    else
        print("✗ Popup configuration missing")
    end
else
    print("✗ Main configuration failed to load")
end

-- Test GDB availability (for debugging context)
print("\n--- Testing GDB Context ---")
print("Termdebug command exists: " .. tostring(vim.fn.exists(":Termdebug") == 1))
print("Termdebug running: " .. tostring(vim.g.termdebug_running or false))

-- Test utils functions
print("\n--- Testing Utils Functions ---")
local utils_ok, utils = pcall(require, "termdebug-enhanced.utils")
if utils_ok then
    local utils_functions = {
        "async_gdb_response",
        "extract_value",
        "find_gdb_buffer"
    }
    
    for _, func_name in ipairs(utils_functions) do
        if utils[func_name] then
            print("✓ utils." .. func_name .. " function exists")
        else
            print("✗ utils." .. func_name .. " function missing")
        end
    end
else
    print("✗ Utils module failed to load: " .. tostring(utils))
end

print("\n=== Diagnostic Complete ===")
print("If you saw a test floating window appear briefly, basic popup functionality works.")
print("If not, there may be an issue with your Neovim floating window support.")
