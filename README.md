# Termdebug Enhanced

A Neovim plugin that enhances the built-in termdebug with VSCode-like keybindings and improved UI for embedded development.

## Features

- **VSCode-like keybindings** for familiar debugging experience
- **Hover evaluation** (press `K` to evaluate expression under cursor, like LSP hover)
- **Memory viewer** with hex dump display and navigation
- **Memory/variable editing** capabilities with validation
- **Floating popup windows** for evaluation results
- **Visual mode evaluation** for complex expressions
- **Auto-configuration** for embedded debugging (ARM GDB)
- **Async GDB communication** with timer-based polling for reliability
- **Smart breakpoint toggle** that checks existing breakpoints
- **Performance optimizations** with buffer caching
- **Comprehensive error handling** with helpful feedback
- **Unit tests** for critical functionality

## Installation

### Using LazyVim

Add this to your LazyVim plugins configuration:

```lua
return {
  {
    "termdebug-enhanced",
    dir = "~/path/to/termdebug-enhanced", -- Adjust to your plugin location
    event = "VeryLazy",
    keys = {
      { "<leader>dd", "<cmd>TermdebugStart<cr>", desc = "Start debugging" },
      { "<leader>dq", "<cmd>TermdebugStop<cr>", desc = "Stop debugging" },
    },
    opts = {
      debugger = "arm-none-eabi-gdb.exe", -- Your debugger executable
      gdbinit = ".gdbinit",                -- Path to .gdbinit file
    },
    config = function(_, opts)
      require("termdebug-enhanced").setup(opts)
    end,
  },
}
```

### Manual Installation

1. Copy the plugin to your Neovim config directory:
```bash
cp -r termdebug-enhanced ~/.config/nvim/lua/
```

2. Add to your init.lua:
```lua
require("termdebug-enhanced").setup({
  debugger = "arm-none-eabi-gdb.exe",
  gdbinit = ".gdbinit",
})
```

## Recent Improvements (v2.0)

### 🚀 Async Response Handling
- Replaced fixed delays with timer-based polling
- Configurable timeouts and poll intervals
- Better error handling and user feedback
- Early termination when response is ready

### 🎯 Smart Breakpoint Toggle
- True toggle functionality (F9 key)
- Automatically detects existing breakpoints
- Removes existing or adds new breakpoints
- Clear notifications about breakpoint state

### ⚡ Performance Improvements
- GDB buffer lookup caching (1-second cache)
- Reduced CPU usage during debugging
- Faster response times for operations
- Debounced functions to prevent excessive calls

### 🧪 Testing & Quality
- Comprehensive unit test suite
- Automated test runner (`./run_tests.sh`)
- Mock framework for testing
- Coverage of critical parsing and utility functions

### 📚 Documentation
- Complete LuaLS type annotations
- Inline documentation for all functions
- Parameter and return type information
- Better IDE support with autocomplete

## Configuration

### Full Configuration Options

```lua
require("termdebug-enhanced").setup({
  -- Debugger settings
  debugger = "arm-none-eabi-gdb.exe",  -- Your GDB executable
  gdbinit = ".gdbinit",                 -- GDB init file
  
  -- UI settings
  popup = {
    border = "rounded",     -- Border style: "none", "single", "double", "rounded"
    width = 60,            -- Popup width
    height = 10,           -- Popup height
  },
  
  memory_viewer = {
    width = 80,            -- Memory viewer width
    height = 20,           -- Memory viewer height
    format = "hex",        -- Display format: "hex", "decimal", "binary"
    bytes_per_line = 16,   -- Bytes per line in hex dump
  },
  
  -- Keybindings (VSCode-like defaults)
  keymaps = {
    continue = "<F5>",              -- Continue execution
    step_over = "<F10>",            -- Step over
    step_into = "<F11>",            -- Step into
    step_out = "<S-F11>",           -- Step out
    toggle_breakpoint = "<F9>",     -- Toggle breakpoint
    stop = "<S-F5>",                -- Stop debugging
    restart = "<C-S-F5>",           -- Restart debugging
    evaluate = "K",                 -- Evaluate under cursor (like LSP hover)
    evaluate_visual = "K",          -- Evaluate selection in visual mode
    watch_add = "<leader>dw",       -- Add watch expression
    watch_remove = "<leader>dW",    -- Remove watch
    memory_view = "<leader>dm",     -- View memory at cursor
    memory_edit = "<leader>dM",     -- Edit memory/variable
    variable_set = "<leader>ds",    -- Set variable value
  },
})
```

### Example .gdbinit

```gdb
# Load your binary
file /path/to/your/binary.elf

# Connect to remote target
target extended-remote localhost:3000

# Optional: Set breakpoint at main
break main
```

## Usage

### Starting a Debug Session

1. Create a `.gdbinit` file in your project root with your GDB commands
2. Start debugging:
   - Press `<leader>dd` or run `:TermdebugStart`
   - Or specify arguments: `:TermdebugStart myprogram`

### Key Bindings

| Key | Action | Description |
|-----|--------|-------------|
| `F5` | Continue | Continue program execution |
| `F9` | Toggle Breakpoint | Set/remove breakpoint at current line |
| `F10` | Step Over | Step over current line |
| `F11` | Step Into | Step into function |
| `Shift+F11` | Step Out | Step out of current function |
| `Shift+F5` | Stop | Stop debugging |
| `Ctrl+Shift+F5` | Restart | Restart debugging session |
| `K` | Evaluate | Show value of expression under cursor (like LSP hover) |
| `K` (visual) | Evaluate Selection | Evaluate selected expression |
| `<leader>dm` | View Memory | Open memory viewer for variable/address |
| `<leader>dM` | Edit Memory | Edit memory or variable value |
| `<leader>ds` | Set Variable | Set variable to new value |
| `<leader>dw` | Add Watch | Add expression to watch list |

### Memory Viewer

When viewing memory (`<leader>dm`):
- `q` or `Esc` - Close memory viewer
- `r` - Refresh memory display
- `e` - Edit memory at offset
- `+`/`-` - Navigate forward/backward by 16 bytes
- `PageUp`/`PageDown` - Navigate by 256 bytes

### Evaluation Popup

The evaluation popup (triggered with `K`) works like LSP hover:
- Shows the value of the expression under cursor
- Automatically closes when cursor moves
- Press `Esc` to close manually
- Works with complex expressions in visual mode

## Working with LazyVim DAP

This plugin can coexist with nvim-dap. To use both:

1. Keep nvim-dap enabled for languages it supports (Python, etc.)
2. Use termdebug-enhanced for embedded/C/C++ debugging
3. You may want to disable DAP keymaps for C/C++ files:

```lua
-- In your LazyVim config
{
  "mfussenegger/nvim-dap",
  keys = function()
    -- Return empty keys for C/C++ files
    if vim.bo.filetype == "c" or vim.bo.filetype == "cpp" then
      return {}
    end
    -- Return default DAP keys for other files
    return { --[[ your DAP keys ]] }
  end,
}
```

## Development

### Running Tests

```bash
# Run all tests
./run_tests.sh

# Run specific test module
nvim --headless -u NONE -c "set rtp+=." -l tests/test_utils.lua
nvim --headless -u NONE -c "set rtp+=." -l tests/test_evaluate.lua
```

### Test Coverage

- **Utils module**: Breakpoint parsing, value extraction, buffer caching
- **Evaluate module**: Expression evaluation, popup creation, error handling
- **Mock framework**: Neovim API mocking for isolated testing

## Tips

1. **Quick Variable Inspection**: Just hover over any variable and press `K` to see its value
2. **Memory Debugging**: Place cursor on a pointer and press `<leader>dm` to see memory contents
3. **Expression Evaluation**: Select any complex expression in visual mode and press `K`
4. **Breakpoint Toggle**: Press `F9` to toggle breakpoints - plugin automatically detects existing ones
5. **Async Operations**: All GDB communication is now async with configurable timeouts
6. **Performance**: GDB buffer lookups are cached for better performance

## Troubleshooting

### GDB not connecting
- Ensure your `.gdbinit` has the correct target configuration
- Check that your debug server is running (OpenOCD, J-Link GDB Server, etc.)
- Plugin validates GDB executable on startup

### Evaluation not working
- Make sure you're at a breakpoint or paused state
- The program must be running for evaluation to work
- Check for timeout errors (default 3 seconds)
- Plugin now provides clear error messages

### Memory viewer shows error
- Verify the address/variable is valid
- Ensure you have the right permissions to read that memory region
- Use async error handling with detailed feedback

### Performance issues
- GDB buffer caching should improve lookup speed
- Adjust timeout settings if responses are slow
- Use `utils.invalidate_gdb_cache()` if buffer detection fails

### Testing failures
- Run `./run_tests.sh` to verify plugin functionality
- Check individual test modules for specific issues
- Ensure Neovim version supports timer functions (0.5+)

## Architecture

### Core Modules

- **`init.lua`**: Plugin setup, configuration, and lifecycle management
- **`keymaps.lua`**: VSCode-like keybinding management with async operations
- **`evaluate.lua`**: Expression evaluation with floating popups
- **`memory.lua`**: Memory viewing and editing with hex display
- **`utils.lua`**: Async GDB communication, parsing, and caching utilities

### Key Features

- **Async Communication**: Timer-based polling with configurable timeouts
- **Buffer Caching**: 1-second cache for GDB buffer lookups
- **Error Handling**: Comprehensive error checking with user feedback
- **Type Safety**: Complete LuaLS annotations for better development
- **Testing**: Unit tests for critical parsing and utility functions

## Contributing

1. Run tests before submitting: `./run_tests.sh`
2. Add tests for new functionality
3. Use LuaLS annotations for new functions
4. Follow async patterns for GDB communication
5. Update documentation for user-facing changes

## License

MIT