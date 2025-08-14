-- Test script to verify keymap fixes
-- Run this in Neovim with: :luafile test_keymap_fix.lua

print("=== Testing Keymap Fixes ===")

-- Enable debug logging to see all messages
vim.log.set_level(vim.log.levels.DEBUG)

-- Load and setup plugin
local plugin_ok, plugin = pcall(require, "termdebug-enhanced")
if not plugin_ok then
    print("✗ Plugin failed to load: " .. tostring(plugin))
    return
end

-- Setup plugin (this should now set up keymaps immediately)
local setup_ok, setup_err = plugin.setup({
    debugger = "gdb",
    keymaps = {
        evaluate = "K",
        evaluate_visual = "<leader>K",
        toggle_breakpoint = "<F9>",
        memory_view = "<leader>dm",
    },
})

if setup_ok then
    print("✓ Plugin setup completed successfully")
else
    print("✗ Plugin setup failed: " .. vim.inspect(setup_err))
    return
end

-- Test 1: Check if K keymap is now active
print("\n=== Keymap Test ===")
local keymap_info = vim.fn.maparg("K", "n", false, true)
if keymap_info and keymap_info.callback then
    print("✓ K keymap is active")
    print("  Description: " .. (keymap_info.desc or "No description"))
else
    print("✗ K keymap is not active")
    print("  Current K mapping: " .. vim.inspect(keymap_info))
end

-- Test 2: Test the evaluate function directly (without debugging session)
print("\n=== Evaluate Function Test (No Debug Session) ===")
print("Testing evaluate_under_cursor without debugging session...")

-- Place cursor on a word for testing
vim.cmd("normal! itest_variable")
vim.cmd("normal! b")  -- Move cursor to beginning of word

local eval_ok, eval_err = pcall(function()
    require("termdebug-enhanced.evaluate").evaluate_under_cursor()
end)

if eval_ok then
    print("✓ evaluate_under_cursor called successfully")
    print("  Should show warning about no debugging session")
else
    print("✗ evaluate_under_cursor failed: " .. tostring(eval_err))
end

-- Test 3: Test keymap directly
print("\n=== Direct Keymap Test ===")
print("Testing K keymap directly...")

local keymap_test_ok, keymap_test_err = pcall(function()
    -- Simulate pressing K
    vim.api.nvim_feedkeys("K", "n", false)
end)

if keymap_test_ok then
    print("✓ K keymap executed successfully")
else
    print("✗ K keymap failed: " .. tostring(keymap_test_err))
end

-- Wait a moment for any async operations
vim.defer_fn(function()
    print("\n=== Results Summary ===")
    print("1. Check :messages for debug output")
    print("2. You should see 'evaluate_under_cursor called' message")
    print("3. You should see warning about no debugging session")
    print("4. K keymap should now work (try pressing K on a word)")
    print("")
    print("=== Next Steps ===")
    print("1. Start debugging: :TermdebugStart your_program")
    print("2. Set breakpoint: F9 on a line")
    print("3. Run program: F5")
    print("4. When stopped, test K on a variable")
    print("5. Check :messages for debug output")
    
    -- Show current messages
    print("\n=== Current Messages ===")
    local messages = vim.fn.execute("messages")
    print(messages)
end, 1000)

-- Test 4: Verify all keymaps are set
print("\n=== All Keymaps Check ===")
local keymaps_to_check = {
    {"K", "n", "Evaluate under cursor"},
    {"<leader>K", "v", "Evaluate selection"},
    {"<F9>", "n", "Toggle breakpoint"},
    {"<leader>dm", "n", "Memory view"},
}

for _, keymap_info in ipairs(keymaps_to_check) do
    local key, mode, desc = keymap_info[1], keymap_info[2], keymap_info[3]
    local mapping = vim.fn.maparg(key, mode, false, true)
    if mapping and mapping.callback then
        print("✓ " .. key .. " (" .. mode .. ") - " .. desc)
    else
        print("✗ " .. key .. " (" .. mode .. ") - " .. desc .. " - NOT SET")
    end
end
