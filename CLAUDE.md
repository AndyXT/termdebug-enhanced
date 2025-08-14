# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the termdebug-enhanced plugin for Neovim - a Lua plugin that enhances Neovim's built-in termdebug with VSCode-like keybindings and improved UI, specifically designed for embedded development with ARM GDB.

## Architecture

### Module Structure

The plugin follows a modular architecture with clear separation of concerns:

- **init.lua**: Core module that handles plugin configuration, autocmd setup, and user command creation. Manages the plugin lifecycle and coordinates between modules.
- **utils.lua**: Shared utilities for GDB communication, response parsing, and buffer caching. Implements async timer-based polling for non-blocking operations.
- **keymaps.lua**: Manages all debugging keybindings setup and cleanup. Uses lazy loading to avoid circular dependencies with other modules.
- **evaluate.lua**: Handles expression evaluation with floating popup windows. Implements hover-like functionality (K key) to show variable values.
- **memory.lua**: Provides memory viewing and editing capabilities with hex dump display, navigation, and interactive editing.
- **termdebug-enhanced.lua**: LazyVim plugin specification file for easy integration.

### Key Design Patterns

1. **Lazy Module Loading**: Modules use lazy loading (via functions like `get_eval()`, `get_memory()`) to prevent circular dependencies.

2. **Safe GDB Communication**: All GDB commands go through `utils.async_gdb_response()` wrapper that checks:
   - Termdebug availability
   - Active debug session status  
   - Error handling for command failures

3. **Resource Management**: Proper cleanup of windows/buffers through dedicated cleanup functions to prevent memory leaks.

4. **Config Safety**: Config access uses fallback defaults to handle uninitialized state.

## Critical Implementation Details

### GDB Response Handling
The plugin uses async timer-based polling (`utils.async_gdb_response`) instead of fixed delays. This provides:
- Configurable timeout and poll intervals
- Proper error handling
- Early termination when response is found
- Buffer caching for improved performance

### Window Management
- Floating windows auto-close on cursor movement or mode change
- Memory viewer uses split windows with dedicated keymaps
- All windows/buffers are tracked and cleaned up on plugin stop or Neovim exit

### State Management
- `vim.g.termdebug_running` tracks debug session state
- `current_memory` table maintains memory viewer state across operations
- `active_keymaps` array tracks keybindings for proper cleanup

## Common Development Tasks

### Testing the Plugin
```bash
# Run unit tests
./run_tests.sh

# Manual testing in Neovim
nvim
:packadd termdebug
:source lua/termdebug-enhanced/init.lua
:lua require("termdebug-enhanced").setup({ debugger = "arm-none-eabi-gdb.exe" })
:TermdebugStart <your-binary>
```

### Test Structure
- `tests/test_utils.lua`: Tests for utility functions
- `tests/test_evaluate.lua`: Tests for evaluation functionality
- `run_tests.sh`: Test runner script

### Key Files to Modify

When adding new features:
1. Add config options to `init.lua` M.config table
2. Add keybindings to `keymaps.lua` 
3. Implement feature logic in appropriate module (evaluate/memory/new module)
4. Update cleanup functions if creating new windows/buffers

### Important Constraints

- **Termdebug Dependency**: Plugin requires Neovim's built-in termdebug (`:packadd termdebug`)
- **ARM GDB Default**: Configured for `arm-none-eabi-gdb.exe` by default
- **GDB Init**: Expects `.gdbinit` file with connection commands for embedded targets
- **API Compatibility**: Uses modern Neovim API (vim.bo, vim.wo) - requires recent Neovim version
- **Timer Dependency**: Uses vim.loop.new_timer() for async operations - requires Neovim 0.5+

## Key Features

1. **Async Response Handling**: Timer-based polling with configurable timeouts
2. **Buffer Caching**: GDB buffer lookup is cached for 1 second to improve performance
3. **Proper Breakpoint Toggle**: Checks existing breakpoints and toggles correctly
4. **Comprehensive Documentation**: All functions have LuaLS type annotations
5. **Unit Tests**: Critical functions are covered by automated tests