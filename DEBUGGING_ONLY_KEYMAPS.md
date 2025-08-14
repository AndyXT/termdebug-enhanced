# Termdebug Enhanced - Debugging-Only Keymaps (Corrected Approach)

## Overview

The keymaps are now properly configured to only be active during debugging sessions, allowing normal LSP/editor functionality when not debugging.

## Keymap Lifecycle

### **When NOT Debugging**
- K key: Normal LSP hover or help lookup
- F9 key: Default behavior
- Other keys: Normal editor behavior
- **No termdebug-enhanced keymaps active**

### **When Debugging Starts** (`:TermdebugStart`)
- `TermdebugStartPost` event triggers
- Keymaps are set up with `remap = false` to override existing mappings
- K key: Variable evaluation with popup
- F9 key: Breakpoint toggle
- Other debugging keymaps become active

### **When Debugging Stops** (`:TermdebugStop`)
- `TermdebugStopPost` event triggers
- All debugging keymaps are cleaned up
- K key: Returns to LSP hover/help
- F9 key: Returns to default behavior

## Implementation Details

### **Keymap Setup (TermdebugStartPost)**
```lua
vim.api.nvim_create_autocmd("User", {
    pattern = "TermdebugStartPost",
    callback = function()
        vim.g.termdebug_running = true
        -- Set up keymaps only when debugging starts
        require("termdebug-enhanced.keymaps").setup_keymaps(M.config.keymaps)
    end,
})
```

### **Keymap Cleanup (TermdebugStopPost)**
```lua
vim.api.nvim_create_autocmd("User", {
    pattern = "TermdebugStopPost", 
    callback = function()
        vim.g.termdebug_running = false
        require("termdebug-enhanced.keymaps").cleanup_keymaps()
    end,
})
```

### **Keymap Override Behavior**
```lua
-- K keymap with remap = false to properly override LSP hover
safe_set_keymap("n", "K", function()
    require("termdebug-enhanced.evaluate").evaluate_under_cursor()
end, { desc = "Evaluate expression under cursor", remap = false })
```

## Fixed Issues

### **1. Popup Window Fixes**
- **100ms delay** before setting up autocmd to prevent immediate closure
- **Cursor-relative positioning** for better reliability
- **Non-focusable window** to prevent focus stealing
- **Enhanced debug logging** to trace popup creation

### **2. Breakpoint Toggle Fixes**
- **Proper "No breakpoints" response handling** (not treated as error)
- **Enhanced error reporting** for breakpoint operations
- **Better validation** of breakpoint commands

### **3. Keymap Conflict Resolution**
- **Debugging-only activation** preserves LSP functionality
- **Proper cleanup** when debugging stops
- **Override behavior** with `remap = false`

## Usage Workflow

### **Normal Editing**
```vim
" K works for LSP hover
" Place cursor on function/variable and press K
" Shows LSP hover information or help
```

### **Start Debugging**
```vim
:TermdebugStart your_program
" Keymaps become active
" K now works for variable evaluation
" F9 now works for breakpoint toggle
```

### **During Debugging**
```vim
" Set breakpoint: F9 on a line
" Run program: F5
" When stopped at breakpoint:
"   - K on variable: Shows popup with value
"   - <leader>dm on pointer: Shows memory viewer
"   - F9: Toggle breakpoint
```

### **Stop Debugging**
```vim
:TermdebugStop
" Keymaps are cleaned up
" K returns to LSP hover
" F9 returns to default behavior
```

## Testing the Implementation

### **Test 1: Normal Editing**
```vim
:luafile test_debugging_keymaps.lua
" Should show K is not mapped to our function
```

### **Test 2: Start Debugging**
```vim
:TermdebugStart program
:verbose map K
" Should show K mapped to our evaluate function
```

### **Test 3: Popup During Debugging**
```vim
" With debugging active and stopped at breakpoint:
" Press K on a variable
" Should see floating popup with variable value
```

### **Test 4: Stop Debugging**
```vim
:TermdebugStop
:verbose map K
" Should show K back to LSP hover or default
```

## Configuration

### **Recommended Setup**
```lua
require("termdebug-enhanced").setup({
    debugger = "gdb",
    keymaps = {
        evaluate = "K",                    -- Override K during debugging only
        evaluate_visual = "<leader>K",     -- Visual mode evaluation
        toggle_breakpoint = "<F9>",        -- Override F9 during debugging only
        memory_view = "<leader>dm",
        memory_edit = "<leader>dM",
        -- ... other keymaps
    },
})
```

### **Alternative Keys (if you prefer not to override K)**
```lua
require("termdebug-enhanced").setup({
    keymaps = {
        evaluate = "<leader>de",           -- Don't override K
        evaluate_visual = "<leader>dE",
        toggle_breakpoint = "<F9>",
        memory_view = "<leader>dm",
    },
})
```

## Benefits of This Approach

1. **No Keymap Conflicts**: LSP hover works normally when not debugging
2. **Clean Separation**: Debugging features only active when needed
3. **Familiar Workflow**: K behaves as expected in different contexts
4. **Proper Cleanup**: No leftover keymaps after debugging stops
5. **Override Safety**: `remap = false` ensures proper keymap precedence

## Files Modified

1. **`lua/termdebug-enhanced/init.lua`**
   - Restored keymap setup to `TermdebugStartPost` event
   - Removed keymap setup from main plugin initialization

2. **`lua/termdebug-enhanced/evaluate.lua`**
   - Removed debugging session check (not needed since keymaps only active during debugging)
   - Fixed popup positioning and timing issues

3. **`lua/termdebug-enhanced/keymaps.lua`**
   - Added `remap = false` to ensure proper keymap override

This approach provides the best of both worlds: full LSP functionality during normal editing and enhanced debugging features when actually debugging.
