-- Test script to verify popup fixes
-- Run this in Neovim with: :luafile test_popup_fix.lua

print("=== Testing Popup Fixes ===")

-- Enable debug logging
vim.log.set_level(vim.log.levels.DEBUG)

-- Test 1: Simple popup test to verify floating windows work
print("\n=== Simple Popup Test ===")
local function test_simple_popup()
    local buf = vim.api.nvim_create_buf(false, true)
    local content = {"Test Popup", "Line 2", "Line 3"}
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
    
    local win_opts = {
        relative = "cursor",
        row = 1,
        col = 0,
        width = 20,
        height = 3,
        style = "minimal",
        border = "rounded",
        focusable = false,
    }
    
    local win = vim.api.nvim_open_win(buf, false, win_opts)
    print("✓ Simple popup created: win=" .. win .. ", buf=" .. buf)
    
    -- Auto-close after 3 seconds
    vim.defer_fn(function()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
        if vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_delete(buf, {force = true})
        end
        print("✓ Simple popup closed")
    end, 3000)
end

test_simple_popup()

-- Test 2: Check keymap override
print("\n=== Keymap Override Test ===")
vim.defer_fn(function()
    -- Check what K is mapped to
    local k_mapping = vim.fn.maparg("K", "n", false, true)
    print("K mapping info:")
    print(vim.inspect(k_mapping))
    
    -- Check if our plugin is loaded
    local plugin_ok, plugin = pcall(require, "termdebug-enhanced")
    if plugin_ok then
        print("✓ Plugin loaded")
        
        -- Reload plugin to apply fixes
        plugin.setup({
            debugger = "gdb",
            keymaps = {
                evaluate = "K",
                evaluate_visual = "<leader>K",
                toggle_breakpoint = "<F9>",
            },
        })
        
        -- Check K mapping again
        local k_mapping_after = vim.fn.maparg("K", "n", false, true)
        print("K mapping after plugin setup:")
        print(vim.inspect(k_mapping_after))
        
        if k_mapping_after and k_mapping_after.callback then
            print("✓ K is mapped to our function")
        else
            print("✗ K is not mapped to our function")
        end
    else
        print("✗ Plugin failed to load: " .. tostring(plugin))
    end
end, 1000)

-- Test 3: Test evaluate function directly
print("\n=== Direct Evaluate Test ===")
vim.defer_fn(function()
    -- Create some test content
    vim.cmd("enew")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {"int main() {", "    int test_var = 42;", "    return 0;", "}"})
    vim.cmd("normal! 2G")  -- Go to line 2
    vim.cmd("normal! w")   -- Move to test_var
    
    print("Testing evaluate_under_cursor directly...")
    local eval_ok, eval_err = pcall(function()
        require("termdebug-enhanced.evaluate").evaluate_under_cursor()
    end)
    
    if eval_ok then
        print("✓ evaluate_under_cursor called successfully")
        print("  Check :messages for debug output")
    else
        print("✗ evaluate_under_cursor failed: " .. tostring(eval_err))
    end
end, 2000)

-- Test 4: Test K keymap directly
print("\n=== K Keymap Test ===")
vim.defer_fn(function()
    print("Testing K keymap...")
    
    -- Simulate pressing K
    local keymap_ok, keymap_err = pcall(function()
        vim.api.nvim_feedkeys("K", "n", false)
    end)
    
    if keymap_ok then
        print("✓ K keymap executed")
    else
        print("✗ K keymap failed: " .. tostring(keymap_err))
    end
end, 3000)

-- Instructions
vim.defer_fn(function()
    print("\n=== Instructions ===")
    print("1. You should see a simple popup appear and disappear")
    print("2. Check :messages for debug output")
    print("3. The K key should now be mapped to our evaluate function")
    print("4. Try pressing K on the word 'test_var' in the buffer")
    print("5. You should see 'No active debugging session' message")
    print("")
    print("=== To test with debugging ===")
    print("1. Create a simple C program:")
    print("   echo 'int main(){int x=42; return 0;}' > test.c")
    print("2. Compile: gcc -g test.c -o test")
    print("3. Start debugging: :TermdebugStart ./test")
    print("4. Set breakpoint: F9 on the int x=42 line")
    print("5. Run: F5")
    print("6. When stopped, press K on 'x' - should show popup")
    print("")
    print("=== Current Messages ===")
    vim.cmd("messages")
end, 4000)
