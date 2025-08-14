# Project Structure

## Root Directory
```
termdebug-enhanced/
├── lua/                          # Main plugin code
├── tests/                        # Unit tests
├── .kiro/                        # Kiro IDE configuration
├── .vscode/                      # VSCode configuration
├── README.md                     # Main documentation
├── IMPROVEMENTS.md               # Development changelog
└── run_tests.sh                  # Test runner script
```

## Core Plugin Structure (`lua/`)
```
lua/
├── termdebug-enhanced.lua        # LazyVim plugin spec
└── termdebug-enhanced/           # Main plugin module
    ├── init.lua                  # Plugin entry point & setup
    ├── keymaps.lua              # Keymap management
    ├── evaluate.lua             # Expression evaluation
    ├── memory.lua               # Memory viewer/editor
    └── utils.lua                # Shared utilities
```

## Module Responsibilities

### `init.lua`
- Plugin configuration and setup
- Termdebug integration
- Autocmd management for plugin lifecycle
- User command creation (`TermdebugStart`, `TermdebugStop`)

### `keymaps.lua`
- VSCode-like keymap definitions
- Dynamic keymap setup/cleanup during debug sessions
- Keymap validation and conflict resolution

### `evaluate.lua`
- Expression evaluation under cursor (`K` key)
- Visual mode selection evaluation
- Popup window management for results
- Variable watching functionality

### `memory.lua`
- Memory viewer with hex dump display
- Memory editing capabilities
- Address navigation and formatting
- Memory window lifecycle management

### `utils.lua`
- Async GDB communication with timer-based polling
- Buffer caching and lookup optimization
- Breakpoint parsing and management
- Shared utility functions (debounce, validation, etc.)

## Test Structure (`tests/`)
```
tests/
├── test_utils.lua               # Tests for utils.lua functions
└── test_evaluate.lua            # Tests for evaluate.lua functions
```

## Configuration Files
- `.kiro/steering/`: AI assistant guidance documents
- `.vscode/`: VSCode workspace settings
- `run_tests.sh`: Automated test execution script

## Naming Conventions
- **Files**: Snake_case for Lua files (`memory.lua`, `test_utils.lua`)
- **Functions**: Snake_case for all function names (`setup_keymaps`, `async_gdb_response`)
- **Variables**: Snake_case for local variables, camelCase for config options
- **Constants**: UPPER_SNAKE_CASE for constants

## Import Patterns
```lua
-- Standard module require pattern
local M = {}

-- Cross-module dependencies
local utils = require("termdebug-enhanced.utils")
local evaluate = require("termdebug-enhanced.evaluate")

-- Return module table
return M
```

## File Organization Rules
- Each module should be self-contained with clear responsibilities
- Shared functionality goes in `utils.lua`
- UI-specific code stays in respective modules (`evaluate.lua`, `memory.lua`)
- Configuration handling centralized in `init.lua`
- Tests mirror the structure of source files