-- Debug test script for termdebug-enhanced
-- Run this with: nvim --headless -c "set rtp+=." -l debug_test.lua

print("=== Termdebug Enhanced Debug Test ===")
print()

-- Test 1: Check if plugin loads
print("1. Testing plugin loading...")
local plugin_ok, plugin = pcall(require, "termdebug-enhanced")
if plugin_ok then
    print("✓ Plugin loaded successfully")
else
    print("✗ Plugin failed to load: " .. tostring(plugin))
    return
end

-- Test 2: Check termdebug availability
print("\n2. Testing termdebug availability...")
vim.cmd('packadd termdebug')
if vim.fn.exists(':Termdebug') == 1 then
    print("✓ Termdebug is available")
else
    print("✗ Termdebug is not available")
    return
end

-- Test 3: Check TermDebugSendCommand function
print("\n3. Testing TermDebugSendCommand function...")
if vim.fn.exists('*TermDebugSendCommand') == 1 then
    print("✓ TermDebugSendCommand function exists")
else
    print("✗ TermDebugSendCommand function does not exist")
    print("   This is likely why evaluate/memory features aren't working")
end

-- Test 4: Check if debugging session can be detected
print("\n4. Testing debug session detection...")
print("   termdebug_running: " .. tostring(vim.g.termdebug_running))

-- Test 5: Test GDB buffer detection
print("\n5. Testing GDB buffer detection...")
local utils_ok, utils = pcall(require, "termdebug-enhanced.utils")
if utils_ok then
    local gdb_buf = utils.find_gdb_buffer()
    if gdb_buf then
        print("✓ GDB buffer found: " .. tostring(gdb_buf))
    else
        print("✗ GDB buffer not found (expected if not debugging)")
    end
else
    print("✗ Utils module failed to load: " .. tostring(utils))
end

-- Test 6: Test evaluate module loading
print("\n6. Testing evaluate module...")
local eval_ok, evaluate = pcall(require, "termdebug-enhanced.evaluate")
if eval_ok then
    print("✓ Evaluate module loaded successfully")
else
    print("✗ Evaluate module failed to load: " .. tostring(evaluate))
end

-- Test 7: Test memory module loading
print("\n7. Testing memory module...")
local mem_ok, memory = pcall(require, "termdebug-enhanced.memory")
if mem_ok then
    print("✓ Memory module loaded successfully")
else
    print("✗ Memory module failed to load: " .. tostring(memory))
end

-- Test 8: Check available termdebug functions
print("\n8. Available termdebug functions:")
local termdebug_functions = {
    'TermDebugSendCommand',
    'TermdebugCommand',
    'TermDebugCommand',
    'TermDebug',
}

for _, func_name in ipairs(termdebug_functions) do
    if vim.fn.exists('*' .. func_name) == 1 then
        print("✓ " .. func_name .. " exists")
    else
        print("✗ " .. func_name .. " does not exist")
    end
end

-- Test 9: Check Neovim version
print("\n9. Neovim version check...")
local version = vim.version()
print("   Neovim version: " .. version.major .. "." .. version.minor .. "." .. version.patch)
if version.major == 0 and version.minor >= 8 then
    print("✓ Neovim version is compatible")
else
    print("✗ Neovim version may be too old")
end

print("\n=== Test Complete ===")
print("\nIf TermDebugSendCommand doesn't exist, that's the root cause.")
print("The plugin needs an active termdebug session to work properly.")
