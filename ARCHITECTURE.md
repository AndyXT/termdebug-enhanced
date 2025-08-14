# Termdebug Enhanced - Architecture Documentation

## Overview

Termdebug Enhanced is a Neovim plugin that extends the built-in termdebug functionality with VSCode-like debugging features. The plugin follows a modular architecture with clear separation of concerns and robust error handling.

## Architecture Principles

1. **Modular Design**: Each major feature is implemented in a separate module
2. **Async Communication**: All GDB communication is asynchronous to prevent UI blocking
3. **Resource Management**: Comprehensive tracking and cleanup of all resources
4. **Error Resilience**: Graceful degradation and comprehensive error handling
5. **Performance Optimization**: Caching, adaptive polling, and resource optimization

## Module Structure

```
lua/termdebug-enhanced/
├── init.lua          # Plugin entry point and configuration
├── utils.lua         # Core utilities and GDB communication
├── evaluate.lua      # Expression evaluation with popups
├── memory.lua        # Memory viewer and editor
└── keymaps.lua       # VSCode-like keymap management
```

## Core Components

### 1. Plugin Initialization (init.lua)

**Responsibilities:**
- Plugin configuration and validation
- Termdebug integration setup
- Autocommand management for lifecycle events
- User command creation
- Resource coordination across modules

**Key Functions:**
- `M.setup(opts)`: Main plugin initialization
- `validate_config(config)`: Comprehensive configuration validation
- `setup_autocmds()`: Lifecycle event management
- `M.cleanup_all_resources()`: Cross-module resource cleanup

**Configuration Schema:**
```lua
---@class TermdebugConfig
---@field debugger string Path to GDB executable
---@field gdbinit string Path to GDB initialization file
---@field popup PopupConfig Popup window configuration
---@field memory_viewer MemoryConfig Memory viewer configuration
---@field keymaps KeymapConfig Keymap configuration
```

### 2. Core Utilities (utils.lua)

**Responsibilities:**
- Asynchronous GDB communication
- Buffer management and caching
- Breakpoint parsing and management
- Performance monitoring and optimization
- Resource tracking and cleanup

**Key Components:**

#### Async GDB Communication
```lua
M.async_gdb_response(command, callback, opts)
```
- Adaptive polling with performance optimization
- Comprehensive error handling and categorization
- Response caching for frequently accessed commands
- Timeout management and resource cleanup

#### Buffer Management
```lua
M.find_gdb_buffer()  -- Cached GDB buffer lookup
M.invalidate_gdb_cache()  -- Cache invalidation
```
- Intelligent caching with automatic invalidation
- Performance metrics tracking
- Error-resilient buffer operations

#### Breakpoint Management
```lua
M.parse_breakpoints(lines)  -- Parse GDB breakpoint output
M.find_breakpoint(breakpoints, file, line)  -- Find specific breakpoint
```
- Robust parsing of various GDB output formats
- File path normalization for accurate matching
- Error handling for malformed input

#### Resource Tracking
```lua
M.track_resource(id, type, resource, cleanup_fn)
M.cleanup_all_resources()
```
- Comprehensive resource lifecycle management
- Automatic cleanup on session end
- Resource usage statistics and monitoring

### 3. Expression Evaluation (evaluate.lua)

**Responsibilities:**
- Expression evaluation under cursor
- Visual selection evaluation
- Floating popup window management
- Error display with helpful hints

**Key Features:**

#### Expression Detection
- Automatic C expression detection using `<cexpr>`
- Fallback to word detection with `<cword>`
- Multi-line visual selection support

#### Popup Management
```lua
create_float_window(content, opts, is_error)
```
- Dynamic window sizing and positioning
- Syntax highlighting for GDB output
- Automatic cleanup on cursor movement
- Error-specific styling and hints

#### Validation and Error Handling
```lua
validate_expression(expr)  -- Syntax validation
create_error_content(error_info)  -- Formatted error display
```
- Pre-validation to catch syntax errors
- Categorized error types with helpful hints
- User-friendly error messages

### 4. Memory Viewer (memory.lua)

**Responsibilities:**
- Memory viewing with hex dump display
- Memory editing capabilities
- Address navigation and formatting
- Interactive memory window management

**Key Features:**

#### Memory Display Formats
- Hexadecimal: `x/NNxb address`
- Decimal: `x/NNdb address`
- Binary: `x/NNtb address`

#### Navigation System
```lua
M.navigate_memory(offset)  -- Navigate by byte offset
M.refresh_memory()  -- Refresh current view
```
- Intelligent address calculation
- Bounds checking for navigation
- State preservation across operations

#### Memory Editing
```lua
M.edit_memory_at_cursor()  -- Edit memory/variables
M.edit_memory_interactive()  -- Interactive editing
```
- Variable vs. address detection
- Hex value validation
- Batch editing support
- Immediate feedback and verification

#### Window Management
- Split window layout for better visibility
- Interactive keybindings for navigation
- Help text and status information
- Proper resource cleanup

### 5. Keymap Management (keymaps.lua)

**Responsibilities:**
- VSCode-like keymap setup and cleanup
- Keymap validation and conflict detection
- Dynamic keymap management during debug sessions
- Integration with other plugin modules

**Key Features:**

#### VSCode-like Keybindings
- F5: Continue execution
- F9: Toggle breakpoint
- F10: Step over
- F11: Step into
- Shift+F11: Step out
- K: Evaluate expression

#### Advanced Operations
- Memory viewing and editing
- Watch expression management
- Variable modification
- Custom expression evaluation

#### Keymap Lifecycle
```lua
M.setup_keymaps(config)  -- Setup during debug start
M.cleanup_keymaps()  -- Cleanup during debug stop
```
- Automatic setup on debug session start
- Complete cleanup on session end
- Error handling for keymap conflicts
- Validation and duplicate detection

## Communication Patterns

### 1. GDB Communication Flow

```
User Action → Keymap → Module Function → utils.async_gdb_response → GDB
                                                ↓
User Feedback ← UI Update ← Callback ← Response Parser ← GDB Output
```

### 2. Resource Management Flow

```
Resource Creation → track_resource() → Resource Registry
                                            ↓
Session End → cleanup_all_resources() → Module Cleanup → Resource Disposal
```

### 3. Error Handling Flow

```
Operation → Validation → Execution → Error Detection → Categorization → User Feedback
     ↓           ↓           ↓            ↓              ↓              ↓
   Early      Prevent     Safe        Graceful       Helpful       Clear
   Exit       Errors    Execution   Degradation    Messages     Recovery
```

## Performance Optimizations

### 1. Adaptive Polling
- Starts with fast polling (25ms) for responsiveness
- Gradually increases interval (up to 100ms) if no response
- Reduces CPU usage during long operations

### 2. Intelligent Caching
- GDB buffer caching with automatic invalidation
- Command result caching for 'info' commands
- Performance metrics tracking for optimization

### 3. Resource Optimization
- Lazy loading of modules to prevent circular dependencies
- Efficient memory usage with proper cleanup
- Minimal UI updates to reduce rendering overhead

### 4. Error Prevention
- Input validation before GDB communication
- Availability checks before operations
- Graceful degradation on partial failures

## Error Handling Strategy

### 1. Error Categories
- **Configuration Errors**: Invalid settings, missing files
- **Runtime Errors**: GDB communication failures, timeouts
- **User Input Errors**: Invalid expressions, malformed addresses
- **System Errors**: Missing dependencies, resource exhaustion

### 2. Error Response Patterns
- **Immediate Feedback**: Show errors in popups or notifications
- **Graceful Degradation**: Continue operation with reduced functionality
- **Recovery Suggestions**: Provide actionable error messages
- **Resource Cleanup**: Ensure no resource leaks on errors

### 3. Validation Layers
- **Input Validation**: Check user input before processing
- **Configuration Validation**: Validate settings during setup
- **Runtime Validation**: Check system state before operations
- **Output Validation**: Verify GDB responses before processing

## Extension Points

### 1. Custom Evaluators
```lua
-- Add custom expression evaluators
local function custom_evaluator(expr)
  -- Custom evaluation logic
  return result
end
```

### 2. Memory Formatters
```lua
-- Add custom memory display formats
local function custom_formatter(data, config)
  -- Custom formatting logic
  return formatted_lines
end
```

### 3. Keymap Extensions
```lua
-- Add custom debugging keymaps
local custom_keymaps = {
  custom_action = "<leader>dc",
}
```

## Testing Strategy

### 1. Unit Testing
- Individual function testing with mocked dependencies
- Error condition testing with controlled inputs
- Performance testing with metrics validation

### 2. Integration Testing
- Module interaction testing
- GDB communication testing with mock responses
- UI integration testing with buffer/window operations

### 3. End-to-End Testing
- Complete debugging workflow testing
- Resource cleanup verification
- Error recovery testing

## Future Enhancements

### 1. Protocol Extensions
- Support for additional debugger protocols
- Remote debugging capabilities
- Multi-target debugging support

### 2. UI Improvements
- Graphical memory viewer
- Variable watch windows
- Call stack visualization

### 3. Performance Enhancements
- Background caching strategies
- Predictive prefetching
- Optimized rendering pipelines

This architecture provides a solid foundation for reliable, performant, and extensible debugging functionality while maintaining clean separation of concerns and robust error handling.