# Memory Format Switching Examples

## Available Formats

The memory viewer supports four different display formats:

1. **Hex** (`h`) - Traditional hexadecimal with ASCII sidebar (default)
2. **Decimal** (`d`) - Decimal values with ASCII sidebar  
3. **Binary** (`b`) - Binary representation with ASCII sidebar
4. **Base64** (`6`) - Base64 encoded representation

## Format Switching Controls

### In Memory Viewer (Split Window or Popup)
- `h` - Switch to hexadecimal format
- `d` - Switch to decimal format  
- `b` - Switch to binary format
- `6` - Switch to base64 format
- `f` - Cycle through all formats

### Programmatic Control
```vim
" Set specific format
:lua require("termdebug-enhanced.memory").set_format("decimal")
:lua require("termdebug-enhanced.memory").set_format("binary")
:lua require("termdebug-enhanced.memory").set_format("base64")

" Cycle through formats
:lua require("termdebug-enhanced.memory").switch_format()
```

## Format Examples

### Sample Memory Content (32 bytes at 0x20000100)
Raw bytes: `48 65 6C 6C 6F 20 57 6F 72 6C 64 21 00 FF A5 5A ...`

### 1. Hex Format (`h`)
```
✓ Memory at 0x20000100 (32 bytes, hex format):
──────────────────────────────────────────────────────────────────
0x20000100:        0x48 0x65 0x6c 0x6c 0x6f 0x20 0x57 0x6f        |Hello Wo|
0x20000108:        0x72 0x6c 0x64 0x21 0x00 0xff 0xa5 0x5a        |rld!..¥Z|
0x20000110:        0x12 0x34 0x56 0x78 0x9a 0xbc 0xde 0xf0        |.4Vx....|
0x20000118:        0x01 0x23 0x45 0x67 0x89 0xab 0xcd 0xef        |.#Eg....|
```

### 2. Decimal Format (`d`)
```
✓ Memory at 0x20000100 (32 bytes, decimal format):
──────────────────────────────────────────────────────────────────
0x20000100:         72 101 108 108 111  32  87 111        |Hello Wo|
0x20000108:        114 108 100  33   0 255 165  90        |rld!..¥Z|
0x20000110:         18  52  86 120 154 188 222 240        |.4Vx....|
0x20000118:          1  35  69 103 137 171 205 239        |.#Eg....|
```

### 3. Binary Format (`b`)
```
✓ Memory at 0x20000100 (32 bytes, binary format):
──────────────────────────────────────────────────────────────────
0x20000100:    01001000 01100101 01101100 01101100  |Hell|
0x20000104:    01101111 00100000 01010111 01101111  |o Wo|
0x20000108:    01110010 01101100 01100100 00100001  |rld!|
0x2000010c:    00000000 11111111 10100101 01011010  |..¥Z|
```

### 4. Base64 Format (`6`)
```
✓ Memory at 0x20000100 (32 bytes, base64 format):
──────────────────────────────────────────────────────────────────
0000: SGVsbG8gV29ybGQhAP+lWhI0VniavN7wASNFZ4mrze8=
```

## Use Cases for Different Formats

### Hex Format (Default)
- **Best for**: General purpose, debugging, pattern recognition
- **When to use**: Most common format for embedded development
- **Benefits**: Familiar, compact, shows byte boundaries clearly

### Decimal Format  
- **Best for**: Analyzing numeric data, counters, sensor values
- **When to use**: When memory contains numeric values you want to interpret
- **Benefits**: Easy to read numeric data, useful for arrays of integers

### Binary Format
- **Best for**: Bit-level analysis, flags, packed structures
- **When to use**: Analyzing bit fields, status registers, protocol headers
- **Benefits**: Shows individual bit patterns, useful for low-level debugging

### Base64 Format
- **Best for**: Data serialization, comparing large blocks, documentation
- **When to use**: Copying memory contents, creating test data, bug reports
- **Benefits**: Compact representation, easy to copy/paste, good for sharing

## Workflow Examples

### 1. Analyzing Protocol Headers
```vim
" Start with hex to see overall structure
<leader>dp              " Open memory popup
h                       " Ensure hex format

" Switch to binary to analyze flags
b                       " Binary format to see bit patterns

" Back to hex for addresses/lengths  
h                       " Hex format for multi-byte values
```

### 2. Debugging Sensor Data Arrays
```vim
" View sensor readings in decimal
<leader>dp              " Open popup on sensor array
d                       " Decimal format to see actual values

" Save current state for comparison
s                       " Save to register

" After sensor reading updates...
<leader>dp              " View again
c                       " Compare with previous values
```

### 3. Creating Bug Reports
```vim
" Capture memory in base64 for easy sharing
<leader>dp              " Open memory view
6                       " Base64 format
S                       " Save to buffer for copying to bug report
```

### 4. Bit Field Analysis  
```vim
" Analyze packed structures or registers
<leader>dp              " Open memory popup
b                       " Binary format to see bit patterns
f                       " Cycle through formats as needed
```

## Configuration

You can set the default format in your configuration:

```lua
require("termdebug-enhanced").setup({
    memory_viewer = {
        format = "decimal",  -- Default: "hex"
        -- ... other options
    }
})
```

The format setting persists during your debugging session and will be remembered when navigating or refreshing the memory view.