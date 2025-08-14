-- Debug script for termdebug-enhanced issues
-- Run this in Neovim with: :luafile debug_issues.lua

print("=== Debugging Termdebug Enhanced Issues ===")

-- Enable debug logging
vim.log.set_level(vim.log.levels.DEBUG)

-- Load and setup plugin
local plugin_ok, plugin = pcall(require, "termdebug-enhanced")
if not plugin_ok then
    print("✗ Plugin failed to load: " .. tostring(plugin))
    return
end

-- Setup with debug configuration
plugin.setup({
    debugger = "gdb",
    keymaps = {
        evaluate = "K",
        evaluate_visual = "<leader>K",
        toggle_breakpoint = "<F9>",
        memory_view = "<leader>dm",
    },
})

print("✓ Plugin loaded and configured")

-- Test 1: Check if termdebug functions exist
print("\n=== Function Availability Test ===")
local functions_to_check = {
    "TermdebugCommand",
    "TermDebugSendCommand",
}

for _, func_name in ipairs(functions_to_check) do
    if vim.fn.exists('*' .. func_name) == 1 then
        print("✓ " .. func_name .. " exists")
    else
        print("✗ " .. func_name .. " does not exist")
    end
end

-- Test 2: Test evaluate module directly
print("\n=== Evaluate Module Test ===")
local eval_ok, evaluate = pcall(require, "termdebug-enhanced.evaluate")
if eval_ok then
    print("✓ Evaluate module loaded")
    
    -- Test if we can call evaluate functions
    print("Testing evaluate_custom function...")
    local test_ok, test_err = pcall(function()
        evaluate.evaluate_custom("1+1")  -- Simple test expression
    end)
    
    if test_ok then
        print("✓ evaluate_custom called successfully")
    else
        print("✗ evaluate_custom failed: " .. tostring(test_err))
    end
else
    print("✗ Evaluate module failed to load: " .. tostring(evaluate))
end

-- Test 3: Test utils module GDB communication
print("\n=== Utils Module Test ===")
local utils_ok, utils = pcall(require, "termdebug-enhanced.utils")
if utils_ok then
    print("✓ Utils module loaded")
    
    -- Test async_gdb_response function
    print("Testing async_gdb_response function...")
    local gdb_test_ok, gdb_test_err = pcall(function()
        utils.async_gdb_response("help", function(response, error)
            if error then
                print("GDB response error: " .. error)
            else
                print("GDB response received: " .. (response and #response or 0) .. " lines")
            end
        end)
    end)
    
    if gdb_test_ok then
        print("✓ async_gdb_response called successfully")
    else
        print("✗ async_gdb_response failed: " .. tostring(gdb_test_err))
    end
else
    print("✗ Utils module failed to load: " .. tostring(utils))
end

print("\n=== Instructions for Manual Testing ===")
print("1. Start a debugging session:")
print("   :TermdebugStart your_program")
print("")
print("2. Test breakpoint toggle (F9):")
print("   - Place cursor on a line with code")
print("   - Press F9")
print("   - Should see 'Breakpoint X set at file:line' message")
print("   - Press F9 again on same line")
print("   - Should see 'Breakpoint X removed from file:line' message")
print("")
print("3. Test evaluate feature (K):")
print("   - Set a breakpoint and run program until it stops")
print("   - Place cursor on a variable")
print("   - Press K")
print("   - Should see a floating popup with variable value")
print("   - Check :messages for debug output")
print("")
print("4. Test manual commands:")
print("   :Evaluate variable_name")
print("   :EvaluateCursor")
print("")
print("5. Check debug messages:")
print("   :messages")
print("")
print("=== Debug Tips ===")
print("- If breakpoint toggle shows 'No breakpoints' error:")
print("  The fix should handle this case now")
print("- If evaluate shows no popup:")
print("  Check :messages for debug output about popup creation")
print("- If GDB communication fails:")
print("  Verify debugging session is active with :echo g:termdebug_running")

-- Test 4: Create a simple popup test
print("\n=== Simple Popup Test ===")
print("Creating a test popup in 3 seconds...")
vim.defer_fn(function()
    local test_content = {"Test Popup", "This is a test", "Press Esc to close"}
    local test_opts = {border = "rounded", width = 30, height = 5}
    
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, test_content)
    
    local win_opts = {
        relative = "cursor",
        row = 1,
        col = 0,
        width = test_opts.width,
        height = test_opts.height,
        style = "minimal",
        border = test_opts.border,
    }
    
    local win = vim.api.nvim_open_win(buf, false, win_opts)
    
    -- Auto-close after 5 seconds
    vim.defer_fn(function()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
        if vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_delete(buf, {force = true})
        end
    end, 5000)
    
    print("✓ Test popup created (will auto-close in 5 seconds)")
end, 3000)
