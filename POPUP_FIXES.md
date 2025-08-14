# Termdebug Enhanced - Popup and Keymap Fixes

## Issues Identified and Fixed

### **Issue 1: K Keymap Conflict**
**Problem**: K was mapped to both the built-in hover function and our evaluate function

**Root Cause**: The keymap wasn't properly overriding the existing K mapping

**Fix Applied**:
- Added `remap = false` option to ensure our keymap takes precedence
- Modified `safe_set_keymap` call in `keymaps.lua`

**Before**:
```lua
safe_set_keymap("n", keymaps.evaluate, function()...end, { desc = "Evaluate expression under cursor" })
```

**After**:
```lua
safe_set_keymap("n", keymaps.evaluate, function()...end, { desc = "Evaluate expression under cursor", remap = false })
```

### **Issue 2: Popup Window Immediately Closing**
**Problem**: Popup appears but closes immediately due to cursor movement detection

**Root Causes**:
1. Autocmd triggers immediately when cursor moves
2. Complex window positioning calculations
3. Window positioning relative to screen coordinates

**Fixes Applied**:

1. **Added delay to autocmd setup**:
```lua
-- Before: Immediate autocmd setup
pcall(vim.api.nvim_create_autocmd, { "CursorMoved", "InsertEnter", "BufLeave" }, {
    once = true,
    callback = function() cleanup_float_window() end,
})

-- After: 100ms delay
vim.defer_fn(function()
    pcall(vim.api.nvim_create_autocmd, { "CursorMoved", "InsertEnter", "BufLeave" }, {
        once = true,
        callback = function() cleanup_float_window() end,
    })
end, 100)
```

2. **Simplified window positioning**:
```lua
-- Before: Complex screen-relative positioning
local win_opts = {
    relative = "win",
    row = calculated_row,
    col = calculated_col,
    -- ... complex calculations
}

-- After: Simple cursor-relative positioning
local win_opts = {
    relative = "cursor",
    row = 1,  -- 1 line below cursor
    col = 0,  -- Same column as cursor
    width = width,
    height = height,
    style = "minimal",
    border = opts.border or "rounded",
    noautocmd = true,
    focusable = false,  -- Don't steal focus
}
```

### **Issue 3: Keymaps Only Active During Debugging**
**Problem**: Keymaps were only set up after starting a debugging session

**Fix Applied**: Moved keymap setup to plugin initialization in `init.lua`

**Before**:
```lua
-- Keymaps set up in TermdebugStartPost autocmd
vim.api.nvim_create_autocmd("User", {
    pattern = "TermdebugStartPost",
    callback = function()
        require("termdebug-enhanced.keymaps").setup_keymaps(M.config.keymaps)
    end,
})
```

**After**:
```lua
-- Keymaps set up immediately during plugin setup
local keymaps_ok, keymaps_err = pcall(function()
    local keymaps = require("termdebug-enhanced.keymaps")
    keymaps.setup_keymaps(M.config.keymaps)
end)
```

### **Issue 4: No Debugging Session Check**
**Problem**: Functions didn't provide helpful feedback when debugging wasn't active

**Fix Applied**: Added session check with helpful message

```lua
function M.evaluate_under_cursor()
    -- Check if debugging session is active
    if not vim.g.termdebug_running then
        vim.notify("No active debugging session. Start debugging with :TermdebugStart", vim.log.levels.WARN)
        return
    end
    -- ... rest of function
end
```

## Testing the Fixes

### **Test 1: Keymap Override**
```vim
:verbose map K
```
Should show our function, not the built-in hover.

### **Test 2: Popup Appearance**
1. Start debugging: `:TermdebugStart program`
2. Set breakpoint: `F9`
3. Run: `F5`
4. When stopped, press `K` on a variable
5. Should see popup that stays visible for a moment

### **Test 3: No Debugging Session**
1. Press `K` on any word (without debugging)
2. Should see: "No active debugging session. Start debugging with :TermdebugStart"

### **Test 4: Debug Output**
```vim
:lua vim.log.set_level(vim.log.levels.DEBUG)
" Press K on a variable
:messages
```
Should see debug messages about popup creation.

## Expected Behavior After Fixes

### **K Keymap**
- **Outside debugging**: Shows "No active debugging session" message
- **During debugging**: Shows floating popup with variable value
- **Popup behavior**: 
  - Appears below cursor
  - Stays visible until cursor moves (with 100ms grace period)
  - Can be closed with Esc
  - Auto-closes on buffer leave or insert mode

### **Popup Window**
- Positioned relative to cursor (1 line below)
- Rounded border
- Non-focusable (doesn't steal focus)
- Proper syntax highlighting
- Auto-sizing based on content

## Files Modified

1. **`lua/termdebug-enhanced/keymaps.lua`**
   - Added `remap = false` to evaluate keymap

2. **`lua/termdebug-enhanced/evaluate.lua`**
   - Added debugging session check
   - Added 100ms delay to autocmd setup
   - Simplified window positioning to cursor-relative
   - Added debug logging

3. **`lua/termdebug-enhanced/init.lua`**
   - Moved keymap setup to plugin initialization
   - Keymaps now active immediately, not just during debugging

## Troubleshooting

### **If K still conflicts**
```vim
:verbose map K
:lua vim.keymap.del("n", "K")  -- Remove conflicting mapping
:lua require("termdebug-enhanced").setup({...})  -- Reload plugin
```

### **If popup still doesn't appear**
```vim
:lua vim.log.set_level(vim.log.levels.DEBUG)
" Press K and check messages
:messages
```

### **If popup closes immediately**
The 100ms delay should prevent this, but if it still happens:
```lua
-- Increase delay in evaluate.lua line ~310
vim.defer_fn(function() ... end, 500)  -- Increase to 500ms
```

The fixes address the core issues with keymap conflicts and popup window behavior. The popup should now appear reliably and stay visible long enough to read the content.
