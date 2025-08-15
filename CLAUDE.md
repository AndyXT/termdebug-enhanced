# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the termdebug-enhanced plugin for Neovim - a Lua plugin that enhances Neovim's built-in termdebug with VSCode-like keybindings and improved UI, specifically designed for embedded development with ARM GDB.

## Commands

### Testing
```bash
# Run all tests
./run_tests.sh

# Run specific test module
nvim --headless -u NONE -c "set rtp+=." -l tests/test_utils.lua
nvim --headless -u NONE -c "set rtp+=." -l tests/test_evaluate.lua
nvim --headless -u NONE -c "set rtp+=." -l tests/test_memory.lua
nvim --headless -u NONE -c "set rtp+=." -l tests/test_keymaps.lua
nvim --headless -u NONE -c "set rtp+=." -l tests/test_integration.lua

# Run simplified tests (no async operations, better for headless mode)
nvim --headless -u NONE -c "set rtp+=." -l tests/test_memory_simple.lua
nvim --headless -u NONE -c "set rtp+=." -l tests/test_keymaps_simple.lua

# Run with timeout for potentially hanging tests
timeout 10 nvim --headless -u NONE -c "set rtp+=." -l tests/test_integration.lua
```

### Manual Testing in Neovim
```vim
:packadd termdebug
:source lua/termdebug-enhanced/init.lua
:lua require("termdebug-enhanced").setup({ debugger = "arm-none-eabi-gdb.exe" })
:TermdebugStart <your-binary>
```

### Debugging Utilities
```vim
" Test popup functionality
:lua require("termdebug-enhanced.debug").test_popup()

" Test GDB response handling
:lua require("termdebug-enhanced.debug").test_gdb_response()

" Debug all buffers
:lua require("termdebug-enhanced.debug").debug_all_buffers()

" Diagnose GDB functions
:lua require("termdebug-enhanced.debug").diagnose_gdb_functions()
```

## Architecture

### Module Dependencies and Communication

```
init.lua (core)
    ├── utils.lua (shared utilities)
    │   └── Provides: async_gdb_response(), parse_breakpoints(), GDB buffer caching
    ├── keymaps.lua (keybinding management)
    │   ├── Uses: utils.async_gdb_response()
    │   ├── Lazy loads: evaluate, memory modules (via get_eval(), get_memory())
    │   └── Manages: active_keymaps array for cleanup
    ├── evaluate.lua (expression evaluation)
    │   ├── Uses: utils.async_gdb_response()
    │   └── Manages: floating popup windows
    ├── memory.lua (memory viewing/editing)
    │   ├── Uses: utils.async_gdb_response()
    │   └── Manages: split windows, current_memory state
    └── debug.lua (debugging utilities)
        └── Uses: utils, evaluate modules for testing
```

### Key Design Patterns

1. **Lazy Module Loading**: Prevents circular dependencies
   - keymaps.lua uses functions like `get_eval()` and `get_memory()` instead of direct requires
   - Modules are loaded only when needed

2. **Async GDB Communication**: All GDB commands use `utils.async_gdb_response()`
   - Timer-based polling with configurable timeout (default 3s)
   - Poll interval of 50ms for responsive feedback
   - Automatic buffer caching (2-second cache duration)
   - Proper error handling with typed errors (GdbUtilsError)

3. **State Management**:
   - `vim.g.termdebug_running`: Global debug session state
   - `current_memory`: Memory viewer state (address, size, format)
   - `active_keymaps`: Array of active keybindings for cleanup
   - `gdb_buffer_cache`: Cached GDB buffer lookup (2s TTL)

4. **Resource Management**:
   - All windows/buffers tracked for cleanup
   - Cleanup functions in each module (cleanup_windows, cleanup_keymaps)
   - Auto-cleanup on VimLeavePre and TermdebugStopPost

## Critical Implementation Details

### GDB Response Handling (utils.async_gdb_response)
```lua
-- Always use async response handling for GDB commands
utils.async_gdb_response(
    "info breakpoints",           -- GDB command
    function(response, error)      -- Callback
        if error then
            vim.notify(error.message, vim.log.levels.ERROR)
            return
        end
        -- Process response
    end,
    { timeout = 3000, poll_interval = 50 }  -- Options
)
```

### Window Management Pattern
```lua
-- Always track windows for cleanup
local window_id = vim.api.nvim_open_win(buf, false, config)
table.insert(active_windows, window_id)

-- Set window-local options
vim.wo[window_id].option = value

-- Cleanup on close
vim.api.nvim_create_autocmd({"CursorMoved", "ModeChanged"}, {
    callback = function() cleanup_windows() end
})
```

### Module Access Pattern
```lua
-- Avoid direct require to prevent circular dependencies
local function get_eval()
    local ok, eval = pcall(require, "termdebug-enhanced.evaluate")
    return ok and eval or nil
end

-- Use the module
local eval = get_eval()
if eval then
    eval.evaluate_expression()
end
```

## Important Constraints

- **Termdebug Dependency**: Requires `:packadd termdebug` before use
- **ARM GDB Default**: Configured for `arm-none-eabi-gdb.exe` by default
- **GDB Init**: Expects `.gdbinit` file with target connection commands
- **Neovim Version**: Requires Neovim 0.5+ for timer support (vim.loop.new_timer)
- **Buffer Caching**: GDB buffer lookup cached for 2 seconds to improve performance
- **Async Operations**: All GDB communication is async with 3s default timeout

## Common Tasks

### Adding New GDB Commands
1. Always use `utils.async_gdb_response()` for GDB communication
2. Handle both success and error cases in the callback
3. Provide user feedback via `vim.notify()`
4. Clean up any created resources on error

### Adding New Keybindings
1. Add config option in `init.lua` M.config.keymaps table
2. Implement handler in `keymaps.lua` setup_keymaps()
3. Add to active_keymaps array for cleanup
4. Test with various GDB states (running, stopped, no debug session)

### Creating Floating Windows
1. Use evaluate.lua's create_popup() as reference
2. Track window ID for cleanup
3. Add autocmds for auto-close on cursor movement
4. Handle window already closed errors gracefully

### Writing Tests
1. Use test_helpers.lua for mock framework
2. Mock GDB responses with `mock_async_gdb_response()`
3. Test both success and error paths
4. Clean up test resources with `cleanup_test_resources()`

## Performance Considerations

- **Buffer Caching**: GDB buffer lookup is expensive, cached for 2 seconds
- **Async Operations**: Avoid blocking operations, use timers and callbacks
- **Debouncing**: Functions like evaluate use debouncing to prevent rapid calls
- **Early Returns**: Check vim.g.termdebug_running early to avoid unnecessary work