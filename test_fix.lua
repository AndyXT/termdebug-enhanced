-- Test script to verify the TermdebugCommand fix
-- Run this in Neovim with: :luafile test_fix.lua

print("=== Testing Termdebug Enhanced Fix ===")

-- Load the plugin
local plugin_ok, plugin = pcall(require, "termdebug-enhanced")
if not plugin_ok then
    print("✗ Plugin failed to load: " .. tostring(plugin))
    return
end

-- Setup with a simple configuration
plugin.setup({
    debugger = "gdb",  -- Use standard gdb
    keymaps = {
        evaluate = "K",
        evaluate_visual = "<leader>K",  -- Different key to avoid conflict
        memory_view = "<leader>dm",
    },
})

print("✓ Plugin loaded and configured")

-- Check if termdebug is available
vim.cmd('packadd termdebug')
if vim.fn.exists(':Termdebug') == 0 then
    print("✗ Termdebug not available")
    return
end

print("✓ Termdebug is available")

-- Check if TermdebugCommand exists
if vim.fn.exists('*TermdebugCommand') == 1 then
    print("✓ TermdebugCommand function exists")
else
    print("✗ TermdebugCommand function does not exist")
    return
end

-- Test the new user commands
print("\n=== Testing New User Commands ===")

local commands = {
    "Evaluate",
    "EvaluateCursor", 
    "MemoryView"
}

for _, cmd in ipairs(commands) do
    if vim.fn.exists(':' .. cmd) == 2 then
        print("✓ :" .. cmd .. " command is available")
    else
        print("✗ :" .. cmd .. " command is not available")
    end
end

print("\n=== Instructions ===")
print("1. Start a debugging session: :Termdebug your_program")
print("2. Set a breakpoint: place cursor on a line and press F9")
print("3. Run the program: press F5")
print("4. When stopped at breakpoint:")
print("   - Test evaluate: place cursor on variable and press K")
print("   - Test memory: place cursor on pointer and press <leader>dm")
print("   - Test commands: :Evaluate variable_name")
print("   - Test commands: :MemoryView 0x1234")

print("\n=== Fix Applied ===")
print("✓ Changed TermDebugSendCommand to TermdebugCommand")
print("✓ Added fallback methods for GDB communication")
print("✓ Added missing user commands (:Evaluate, :MemoryView)")
