# Memory Diffing Workflow Examples

## Quick Reference

### Available Diffing Methods
1. **Quick Register Comparison**: `s` (save) → `c` (compare) 
2. **Buffer Diffing**: `S` (save to buffer) → use Neovim's `:diffthis`
3. **Programmatic Comparison**: `compare_memory_with_register()` and `diff_memory_buffers()`

### Keyboard Shortcuts in Memory Viewer
- `s` - Save to register 'm' (or specify register)  
- `S` - Save to new buffer with timestamp
- `c` - Compare current memory with register 'm'
- `r` - Refresh current view
- `e` - Edit memory interactively

## Simple Workflow (Recommended)

```vim
" 1. Position cursor on variable/array and open memory view
<leader>dp              " Opens popup memory viewer

" 2. Save initial state  
s                       " Save to register 'm'

" 3. Execute some code (step, continue, etc.)
<F10>                   " Step over some operations
<F5>                    " Continue to next breakpoint

" 4. Check if memory changed
<leader>dp              " Open memory view again
c                       " Compare with saved state - opens comparison window

" Alternative: For detailed analysis
S                       " Save to timestamped buffer for later reference
```

## Scenario 1: Array Corruption Debugging

```vim
" 1. Pause at function entry, save array state
:lua require("termdebug-enhanced.memory").save_memory_to_buffer("array_before.hex")

" 2. Step through suspicious function
<F10>  " step over
<F10>  " step over
<F10>  " step over

" 3. Save array state after function
:lua require("termdebug-enhanced.memory").save_memory_to_buffer("array_after.hex")

" 4. Open both buffers in diff mode
:edit array_before.hex
:vertical diffsplit array_after.hex
```

## Scenario 2: Register State Comparison

```vim
" Quick register-based comparison for small structures
" Save struct state before critical operation
<leader>dp              " Open memory popup on struct variable  
s                       " Save to default register 'm'

" Execute critical code section
<F5>                    " continue execution
<C-c>                   " break at next point

" Check if struct changed
<leader>dp              " View current memory
S                       " Save to new buffer for detailed comparison
```

## Scenario 3: Circular Buffer Analysis

```vim
" Monitor circular buffer across multiple iterations
:lua require("termdebug-enhanced.memory").save_memory_to_register('1')  " iteration 1
" ... step through one iteration ...
:lua require("termdebug-enhanced.memory").save_memory_to_register('2')  " iteration 2  
" ... step through another iteration ...
:lua require("termdebug-enhanced.memory").save_memory_to_register('3')  " iteration 3

" Compare states
:echo "1->2 same: " . (@1 == @2 ? "yes" : "no")
:echo "2->3 same: " . (@2 == @3 ? "yes" : "no")
```

## Buffer Content Format

When saved to buffer, memory dumps include:

```
# Memory Dump
# Address: 0x20000100
# Size: 64 bytes
# Variable: my_array
# Timestamp: 2024-01-15 14:30:45
#

0x20000100:    0x00 0x01 0x02 0x03 0x04 0x05 0x06 0x07  |........|
0x20000108:    0x08 0x09 0x0a 0x0b 0x0c 0x0d 0x0e 0x0f  |........|
0x20000110:    0x10 0x11 0x12 0x13 0x14 0x15 0x16 0x17  |........|
...
```

This format makes it easy to:
- Identify when/where the dump was taken
- See byte-level changes highlighted in diff mode
- Track which variable/address was being monitored