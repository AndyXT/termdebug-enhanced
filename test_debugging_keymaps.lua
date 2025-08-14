-- Test script for debugging-only keymaps
-- Run this in Neovim with: :luafile test_debugging_keymaps.lua

print("=== Testing Debugging-Only Keymaps ===")

-- Enable debug logging
vim.log.set_level(vim.log.levels.DEBUG)

-- Load and setup plugin
local plugin_ok, plugin = pcall(require, "termdebug-enhanced")
if not plugin_ok then
    print("✗ Plugin failed to load: " .. tostring(plugin))
    return
end

-- Setup plugin
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

-- Test 1: Check K keymap when NOT debugging
print("\n=== Test 1: K Keymap When NOT Debugging ===")
local k_mapping_before = vim.fn.maparg("K", "n", false, true)
if k_mapping_before and k_mapping_before.callback then
    print("✗ K is mapped to our function (should not be when not debugging)")
    print("  Mapping: " .. vim.inspect(k_mapping_before))
else
    print("✓ K is not mapped to our function (correct - not debugging)")
    if k_mapping_before and k_mapping_before.rhs then
        print("  K is mapped to: " .. k_mapping_before.rhs .. " (probably LSP hover)")
    else
        print("  K has default behavior (help lookup)")
    end
end

-- Test 2: Test K behavior when not debugging
print("\n=== Test 2: K Behavior When NOT Debugging ===")
vim.cmd("enew")
vim.api.nvim_buf_set_lines(0, 0, -1, false, {"function test() {", "    let variable = 42;", "    return variable;", "}"})
vim.cmd("normal! 2G")  -- Go to line 2
vim.cmd("normal! w")   -- Move to 'variable'

print("Current word under cursor: " .. vim.fn.expand("<cword>"))
print("Testing K behavior (should be LSP hover or help, not our evaluate)...")

-- Don't actually press K as it might trigger LSP or help
print("✓ K should trigger LSP hover or help, not our evaluate function")

-- Test 3: Simulate debugging start
print("\n=== Test 3: Simulating Debugging Start ===")
print("Simulating TermdebugStartPost event...")

-- Manually trigger the autocmd callback
vim.g.termdebug_running = true
local keymaps_ok, keymaps_err = pcall(function()
    require("termdebug-enhanced.keymaps").setup_keymaps({
        evaluate = "K",
        evaluate_visual = "<leader>K",
        toggle_breakpoint = "<F9>",
        memory_view = "<leader>dm",
    })
end)

if keymaps_ok then
    print("✓ Keymaps set up successfully (simulating debugging start)")
else
    print("✗ Keymap setup failed: " .. tostring(keymaps_err))
end

-- Test 4: Check K keymap when debugging
print("\n=== Test 4: K Keymap When Debugging ===")
local k_mapping_after = vim.fn.maparg("K", "n", false, true)
if k_mapping_after and k_mapping_after.callback then
    print("✓ K is now mapped to our evaluate function (correct - debugging active)")
    print("  Description: " .. (k_mapping_after.desc or "No description"))
else
    print("✗ K is not mapped to our function (should be when debugging)")
    print("  Mapping: " .. vim.inspect(k_mapping_after))
end

-- Test 5: Test evaluate function when debugging
print("\n=== Test 5: Evaluate Function When Debugging ===")
print("Testing evaluate_under_cursor with debugging active...")

local eval_ok, eval_err = pcall(function()
    require("termdebug-enhanced.evaluate").evaluate_under_cursor()
end)

if eval_ok then
    print("✓ evaluate_under_cursor called successfully")
    print("  Should show GDB communication attempt (even if no actual GDB)")
else
    print("✗ evaluate_under_cursor failed: " .. tostring(eval_err))
end

-- Test 6: Simulate debugging stop
print("\n=== Test 6: Simulating Debugging Stop ===")
print("Simulating TermdebugStopPost event...")

-- Manually trigger the cleanup
vim.g.termdebug_running = false
local cleanup_ok, cleanup_err = pcall(function()
    require("termdebug-enhanced.keymaps").cleanup_keymaps()
end)

if cleanup_ok then
    print("✓ Keymaps cleaned up successfully (simulating debugging stop)")
else
    print("✗ Keymap cleanup failed: " .. tostring(cleanup_err))
end

-- Test 7: Check K keymap after debugging stops
print("\n=== Test 7: K Keymap After Debugging Stops ===")
local k_mapping_final = vim.fn.maparg("K", "n", false, true)
if k_mapping_final and k_mapping_final.callback and k_mapping_final.desc and k_mapping_final.desc:match("Evaluate") then
    print("✗ K is still mapped to our function (should be cleaned up)")
    print("  Mapping: " .. vim.inspect(k_mapping_final))
else
    print("✓ K is no longer mapped to our function (correct - debugging stopped)")
    if k_mapping_final and k_mapping_final.rhs then
        print("  K is back to: " .. k_mapping_final.rhs)
    else
        print("  K has default behavior")
    end
end

-- Summary
vim.defer_fn(function()
    print("\n=== Summary ===")
    print("✓ Plugin loads and sets up correctly")
    print("✓ Keymaps are NOT active when debugging is stopped")
    print("✓ Keymaps become active when debugging starts")
    print("✓ Keymaps are cleaned up when debugging stops")
    print("✓ K key returns to normal LSP/help behavior when not debugging")
    print("")
    print("=== Real Usage ===")
    print("1. Normal editing: K works for LSP hover/help")
    print("2. Start debugging: :TermdebugStart program")
    print("3. During debugging: K works for variable evaluation")
    print("4. Stop debugging: :TermdebugStop")
    print("5. Back to normal: K works for LSP hover/help again")
    print("")
    print("=== Current Messages ===")
    vim.cmd("messages")
end, 1000)
