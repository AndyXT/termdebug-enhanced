-- Simple test script to verify popup functionality
-- Run this in Neovim with: :luafile test_popup_simple.lua

print("Testing termdebug-enhanced popup functionality...")

-- First, let's test if we can load the module
local ok, evaluate = pcall(require, "termdebug-enhanced.evaluate")
if not ok then
    print("ERROR: Failed to load evaluate module: " .. tostring(evaluate))
    return
end

print("✓ Evaluate module loaded successfully")

-- Test if the test_popup function exists
if not evaluate.test_popup then
    print("ERROR: test_popup function not found in evaluate module")
    return
end

print("✓ test_popup function found")

-- Try to call the test popup function
print("Calling test_popup()...")
local test_ok, test_err = pcall(evaluate.test_popup)
if not test_ok then
    print("ERROR: test_popup() failed: " .. tostring(test_err))
    return
end

print("✓ test_popup() called successfully")
print("Check if a popup window appeared above this message!")
