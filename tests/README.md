# Test Suite for termdebug-enhanced

This directory contains comprehensive tests for the termdebug-enhanced Neovim plugin.

## Test Files

### Core Test Infrastructure
- `test_helpers.lua` - Enhanced test framework with mocking utilities, async testing support, and common fixtures
- `test_simple.lua` - Basic test to verify test infrastructure works

### Module Tests
- `test_utils.lua` - Tests for the utils module (existing, working)
- `test_evaluate.lua` - Tests for the evaluate module (existing, mostly working)
- `test_memory.lua` - Comprehensive tests for memory module functionality
- `test_memory_simple.lua` - Simplified memory tests without complex async operations
- `test_keymaps.lua` - Comprehensive tests for keymaps module functionality
- `test_keymaps_simple.lua` - Simplified keymaps tests
- `test_integration.lua` - Integration tests for module interactions

## Test Infrastructure Features

### Enhanced Test Framework (`test_helpers.lua`)
- **Assertion Functions**: `assert_eq`, `assert_true`, `assert_false`, `assert_nil`, `assert_not_nil`, `assert_contains`, `assert_error`
- **Test Runner**: `run_test`, `run_test_suite` with colored output and error reporting
- **Mock Framework**: `create_mock`, `create_mock_with_behavior`, `mock_vim_api`, `restore_mocks`
- **Async Testing**: `wait_for`, `create_test_timer` for testing async operations
- **Test Fixtures**: Common GDB responses, breakpoint data, memory dumps, error scenarios
- **Resource Management**: `create_test_buffer`, `create_test_window`, `cleanup_test_resources`

### Mock Utilities
- **GDB Communication**: `mock_async_gdb_response` with configurable responses
- **Vim API Mocking**: Comprehensive mocking of vim functions and APIs
- **Test Fixtures**: Pre-defined responses for common GDB operations

## Test Coverage

### Memory Module Tests
- ✅ Memory viewing at cursor position
- ✅ Direct address memory examination
- ✅ Memory navigation (forward/backward)
- ✅ Memory editing (variables and raw memory)
- ✅ Error handling for invalid addresses
- ✅ GDB availability checking
- ✅ Resource cleanup and window management
- ✅ Input validation for addresses and hex values

### Keymaps Module Tests
- ✅ Keymap setup and cleanup functionality
- ✅ Breakpoint toggle logic with various GDB scenarios
- ✅ Integration with evaluate and memory modules
- ✅ Error handling for invalid keymap configurations
- ✅ GDB availability checking for keymap operations
- ✅ Keymap validation and conflict detection

### Integration Tests
- ✅ Full plugin lifecycle (setup → use → cleanup)
- ✅ Module interaction testing (keymaps ↔ evaluate, keymaps ↔ memory)
- ✅ Cross-module error handling
- ✅ Configuration loading and validation
- ✅ Resource cleanup across modules
- ✅ Async operation coordination
- ✅ Module state consistency

## Running Tests

### Individual Tests
```bash
# Run specific test file
nvim --headless -u NONE -c "set rtp+=." -l tests/test_memory_simple.lua

# Run with timeout for hanging tests
timeout 10 nvim --headless -u NONE -c "set rtp+=." -l tests/test_integration.lua
```

### All Tests
```bash
# Run all tests using the test runner
./run_tests.sh
```

## Test Implementation Notes

### Async Testing Challenges
- Some tests use `vim.defer_fn` and async operations which can cause hanging in headless mode
- Simplified versions of tests (`test_memory_simple.lua`, `test_keymaps_simple.lua`) provide synchronous alternatives
- Integration tests may need timeout handling for complex async scenarios

### Mock Strategy
- Comprehensive mocking of vim APIs to avoid dependencies on actual Neovim state
- GDB communication is mocked with configurable responses for different test scenarios
- Module dependencies are mocked to enable isolated testing

### Coverage Areas
- **Functionality Testing**: Core features work as expected
- **Error Handling**: Proper error handling and user feedback
- **Edge Cases**: Invalid inputs, missing dependencies, error conditions
- **Integration**: Module interactions and data flow
- **Resource Management**: Proper cleanup of windows, buffers, and keymaps

## Requirements Satisfied

This test suite addresses the following requirements from the spec:

- **3.1**: Comprehensive unit tests for memory viewing and editing functions ✅
- **3.1**: Test hex dump formatting, navigation, and memory address parsing ✅
- **3.1**: Tests for memory window creation, cleanup, and resource management ✅
- **3.1**: Test error conditions for invalid addresses and memory access failures ✅
- **3.1**: Unit tests for keymap setup and cleanup functionality ✅
- **3.1**: Test breakpoint toggle logic with various GDB response scenarios ✅
- **3.1**: Tests for async keymap operations and error handling ✅
- **3.2**: Enhanced mock framework for Neovim APIs and GDB communication ✅
- **3.2**: Helper functions for testing async operations with controlled timing ✅
- **3.2**: Test fixtures for common GDB responses and error scenarios ✅
- **3.2**: Test utilities for floating window and buffer management testing ✅
- **3.1, 3.2**: Integration tests for module interactions ✅
- **3.1, 3.2**: End-to-end workflows for debugging operations ✅
- **3.1, 3.2**: Plugin lifecycle management and resource cleanup tests ✅
- **3.1, 3.2**: Configuration loading and validation across modules ✅