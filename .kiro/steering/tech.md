# Technology Stack

## Language & Runtime
- **Lua**: Primary language for Neovim plugin development
- **Neovim API**: Built on Neovim's Lua API and vim functions
- **GDB Integration**: Communicates with GDB through Neovim's termdebug

## Dependencies
- **Neovim**: Requires modern Neovim with Lua support
- **Termdebug**: Built-in Neovim debugging plugin (`:packadd termdebug`)
- **GDB**: External debugger (typically `arm-none-eabi-gdb` for embedded)
- **Optional**: MunifTanjim/nui.nvim for enhanced UI components

## Architecture Patterns
- **Modular design**: Separate modules for different concerns (evaluate, memory, keymaps, utils)
- **Async communication**: Timer-based polling for GDB responses
- **Event-driven**: Uses Neovim autocmds for lifecycle management
- **Configuration-driven**: Extensive user customization options
- **Caching**: Buffer caching for performance optimization

## Key Libraries & APIs
- `vim.api`: Core Neovim API functions
- `vim.fn`: Vim function compatibility layer  
- `vim.loop`: Event loop and timer functionality
- `vim.notify`: User notifications
- `vim.tbl_deep_extend`: Configuration merging

## Common Commands

### Testing
```bash
# Run all tests
./run_tests.sh

# Run specific test file
nvim --headless -u NONE -c "set rtp+=." -l tests/test_utils.lua
```

### Development
```bash
# Make test runner executable
chmod +x run_tests.sh

# Test plugin loading
nvim -c "set rtp+=." -c "lua require('termdebug-enhanced').setup()"
```

### Installation Testing
```bash
# Test LazyVim integration
nvim --headless -c "lua vim.cmd('packadd termdebug')" -c "qa"
```

## Code Quality Standards
- **LuaLS annotations**: All public functions must have type annotations
- **Error handling**: Proper pcall usage for external operations
- **Testing**: Unit tests for critical functionality
- **Documentation**: Comprehensive function documentation
- **Performance**: Async patterns and caching for GDB operations