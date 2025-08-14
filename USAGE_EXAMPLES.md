# Termdebug Enhanced - Usage Examples and Troubleshooting

## Table of Contents
- [Basic Usage](#basic-usage)
- [Configuration Examples](#configuration-examples)
- [Advanced Features](#advanced-features)
- [Troubleshooting](#troubleshooting)
- [Performance Optimization](#performance-optimization)

## Basic Usage

### Starting a Debug Session

```lua
-- Start debugging with default settings
:TermdebugStart

-- Start debugging with a specific executable
:TermdebugStart ./my_program

-- Start debugging with arguments
:TermdebugStart ./my_program arg1 arg2
```

### Basic Debugging Operations

```lua
-- Set breakpoints
-- Place cursor on line and press F9
-- Or use GDB command
:Break main.c:42

-- Step through code
-- F10: Step over (next line)
-- F11: Step into (enter function)
-- Shift+F11: Step out (exit function)
-- F5: Continue execution

-- Evaluate expressions
-- Place cursor on variable and press K
-- Or select expression in visual mode and press K
```

## Configuration Examples

### Basic Configuration

```lua
require("termdebug-enhanced").setup({
  -- Debugger settings
  debugger = "gdb",  -- or "arm-none-eabi-gdb" for embedded
  gdbinit = ".gdbinit",
  
  -- UI settings
  popup = {
    border = "rounded",
    width = 60,
    height = 10,
  },
  
  memory_viewer = {
    width = 80,
    height = 20,
    format = "hex",
    bytes_per_line = 16,
  },
})
```

### Embedded Development Configuration

```lua
require("termdebug-enhanced").setup({
  debugger = "arm-none-eabi-gdb",
  gdbinit = "embedded.gdbinit",
  
  popup = {
    border = "double",
    width = 80,
    height = 15,
  },
  
  memory_viewer = {
    width = 100,
    height = 25,
    format = "hex",
    bytes_per_line = 16,
  },
  
  keymaps = {
    -- Custom keymaps for embedded workflow
    memory_view = "<leader>mv",
    memory_edit = "<leader>me",
    evaluate = "<leader>ev",
  },
})
```

### LazyVim Integration

```lua
-- In your LazyVim plugins configuration
{
  "your-username/termdebug-enhanced",
  dependencies = { "mfussenegger/nvim-dap" }, -- optional
  config = function()
    require("termdebug-enhanced").setup({
      debugger = "gdb",
      popup = { border = "rounded" },
    })
  end,
}
```

## Advanced Features

### Memory Viewing and Editing

```lua
-- View memory at cursor (variable or address)
-- Place cursor on variable/address and use keymap (default: <leader>dm)

-- Navigate memory viewer
-- +/-: Move by 16 bytes (one line)
-- PageUp/PageDown: Move by 256 bytes (one page)
-- r: Refresh current view
-- e: Edit memory at current location
-- q/Esc: Close memory viewer

-- Edit memory interactively
-- In memory viewer, press 'e' and enter offset and hex value
-- Example: offset=0, value=FF (sets byte at current address to 0xFF)
```

### Expression Evaluation

```lua
-- Evaluate under cursor
-- Place cursor on variable/expression and press K (or configured key)

-- Evaluate selection
-- Select expression in visual mode and press K

-- Evaluate custom expression
-- Use :lua require("termdebug-enhanced.evaluate").evaluate_custom("my_expr")

-- Complex expressions
-- Supports C expressions: ptr->field, array[index], (type*)address
```

### Breakpoint Management

```lua
-- Toggle breakpoint at current line
-- Press F9 (or configured key)

-- Conditional breakpoints (use GDB commands)
:Break main.c:42 if x > 10

-- Watchpoints
:Watch variable_name

-- List all breakpoints
:Info breakpoints
```

## Troubleshooting

### Common Issues

#### 1. "Termdebug not available" Error

**Problem**: Plugin reports termdebug is not available.

**Solutions**:
```vim
" Manually load termdebug
:packadd termdebug

" Check if termdebug is available
:echo exists(':Termdebug')

" Add to your init.vim/init.lua
vim.cmd('packadd termdebug')
```

#### 2. "Debugger executable not found" Error

**Problem**: GDB executable is not in PATH or incorrectly specified.

**Solutions**:
```lua
-- Check if debugger is in PATH
:!which gdb
:!which arm-none-eabi-gdb

-- Use full path in configuration
require("termdebug-enhanced").setup({
  debugger = "/usr/bin/gdb",  -- or full path to your debugger
})

-- For embedded development
require("termdebug-enhanced").setup({
  debugger = "/opt/gcc-arm-none-eabi/bin/arm-none-eabi-gdb",
})
```

#### 3. Memory Viewer Shows "Cannot access memory"

**Problem**: Trying to view invalid memory addresses.

**Solutions**:
```gdb
# Check if program is running
(gdb) info program

# Check variable scope
(gdb) info locals
(gdb) info args

# Use valid addresses
(gdb) print &variable_name
(gdb) x/16xb 0x12345678
```

#### 4. Evaluation Timeouts

**Problem**: Expression evaluation times out.

**Solutions**:
```lua
-- Increase timeout in async operations
-- This is handled automatically, but you can check:
-- 1. Ensure GDB is responsive
-- 2. Simplify complex expressions
-- 3. Check if program is in valid state

-- Debug GDB communication
:lua vim.g.termdebug_running = true  -- Check debug state
```

#### 5. Keymap Conflicts

**Problem**: Keymaps don't work or conflict with other plugins.

**Solutions**:
```lua
-- Customize keymaps to avoid conflicts
require("termdebug-enhanced").setup({
  keymaps = {
    continue = "<F5>",
    step_over = "<F10>",
    step_into = "<F11>",
    toggle_breakpoint = "<F9>",
    evaluate = "<leader>de",  -- Changed from K to avoid conflicts
    memory_view = "<leader>dm",
  },
})

-- Check for keymap conflicts
:verbose map <F9>
:verbose map K
```

### Debugging Plugin Issues

#### Enable Debug Logging

```lua
-- Check plugin state
:lua print(vim.inspect(require("termdebug-enhanced").config))

-- Check resource usage
:lua print(vim.inspect(require("termdebug-enhanced").get_resource_stats()))

-- Check GDB buffer
:lua print(require("termdebug-enhanced.utils").find_gdb_buffer())
```

#### Manual Cleanup

```lua
-- If plugin gets stuck, manually clean up
:lua require("termdebug-enhanced").cleanup_all_resources()

-- Reset performance metrics
:lua require("termdebug-enhanced.utils").reset_performance_metrics()

-- Clear caches
:lua require("termdebug-enhanced.utils").clear_gdb_info_cache()
```

## Performance Optimization

### Configuration for Better Performance

```lua
require("termdebug-enhanced").setup({
  -- Optimize popup size for faster rendering
  popup = {
    width = 60,    -- Smaller width
    height = 10,   -- Reasonable height
  },
  
  memory_viewer = {
    bytes_per_line = 16,  -- Standard hex dump format
    height = 20,          -- Don't make too large
  },
})
```

### GDB Configuration (.gdbinit)

```gdb
# Optimize GDB for better performance
set pagination off
set confirm off
set verbose off

# For embedded development
set architecture arm
set endian little
target extended-remote :3333

# Reduce output verbosity
set print pretty on
set print array on
set print array-indexes on
```

### Memory Usage Tips

1. **Close unused memory viewers**: Use 'q' or Esc to close memory windows
2. **Limit memory view size**: Don't view large memory regions unnecessarily
3. **Use appropriate polling intervals**: Plugin automatically adapts polling
4. **Clean up regularly**: Plugin automatically cleans up on session end

### Performance Monitoring

```lua
-- Check performance metrics
:lua print(vim.inspect(require("termdebug-enhanced.utils").get_performance_metrics()))

-- Check resource usage
:lua print(vim.inspect(require("termdebug-enhanced").get_resource_stats()))

-- Monitor cache effectiveness
-- High cache hit ratio indicates good performance
-- High cache miss ratio may indicate inefficient usage patterns
```

## Integration Examples

### With nvim-dap

```lua
-- termdebug-enhanced can complement nvim-dap
-- Use termdebug-enhanced for GDB-specific features
-- Use nvim-dap for general debugging protocol support

{
  "mfussenegger/nvim-dap",
  dependencies = {
    "your-username/termdebug-enhanced",
  },
  config = function()
    -- Configure nvim-dap
    local dap = require("dap")
    
    -- Configure termdebug-enhanced for GDB-specific features
    require("termdebug-enhanced").setup({
      debugger = "gdb",
      keymaps = {
        -- Use different keymaps to avoid conflicts
        memory_view = "<leader>gm",
        evaluate = "<leader>ge",
      },
    })
  end,
}
```

### With Telescope

```lua
-- Create custom Telescope picker for breakpoints
local function telescope_breakpoints()
  require("telescope.pickers").new({}, {
    prompt_title = "GDB Breakpoints",
    finder = require("telescope.finders").new_dynamic({
      fn = function()
        -- Get breakpoints using termdebug-enhanced utils
        local utils = require("termdebug-enhanced.utils")
        utils.async_gdb_response("info breakpoints", function(response)
          if response then
            local breakpoints = utils.parse_breakpoints(response)
            -- Process breakpoints for Telescope display
          end
        end)
      end,
    }),
  }):find()
end

-- Map to keymap
vim.keymap.set("n", "<leader>db", telescope_breakpoints, { desc = "Show breakpoints" })
```

This comprehensive documentation provides users with practical examples, troubleshooting guidance, and advanced usage patterns for the termdebug-enhanced plugin.