---Unit tests for termdebug-enhanced validation functionality
---Run with: nvim -l tests/test_validation.lua

-- Mock vim functions
vim.trim = function(s) return s:match("^%s*(.-)%s*$") end
vim.notify = function() end
vim.log = { levels = { INFO = 1, WARN = 2, ERROR = 3 } }

local utils = require("termdebug-enhanced.utils")

-- Test framework
local tests = {}
local passed = 0
local failed = 0

local function assert_true(value, message)
  if not value then
    error((message or "Expected true, got: ") .. vim.inspect(value))
  end
end

local function assert_equal(expected, actual, message)
  if expected ~= actual then
    error((message or "Expected: ") .. vim.inspect(expected) .. ", got: " .. vim.inspect(actual))
  end
end

local function run_test(name, test_fn)
  local ok, err = pcall(test_fn)
  if ok then
    passed = passed + 1
    print("✓ " .. name)
  else
    failed = failed + 1
    print("✗ " .. name .. "\n  " .. tostring(err))
  end
end

-- Test address validation
function tests.test_address_validation()
  -- Valid addresses
  local addr, err = utils.validation.normalize_address("0x1234")
  assert_equal("0x1234", addr, "Should normalize hex address")
  assert_equal(nil, err, "Should not have error for valid hex")

  addr, err = utils.validation.normalize_address("1234")
  assert_equal("0x4d2", addr, "Should convert decimal to hex")
  assert_equal(nil, err, "Should not have error for valid decimal")

  addr, err = utils.validation.normalize_address("variable_name")
  assert_equal("variable_name", addr, "Should accept variable names")
  assert_equal(nil, err, "Should not have error for valid variable")

  -- Invalid addresses
  addr, err = utils.validation.normalize_address("")
  assert_equal(nil, addr, "Should reject empty address")
  assert_true(err ~= nil, "Should have error for empty address")

  addr, err = utils.validation.normalize_address("invalid!")
  assert_equal(nil, addr, "Should reject invalid characters")
  assert_true(err ~= nil, "Should have error for invalid characters")
end

-- Test expression validation
function tests.test_expression_validation()
  -- Valid expressions
  local valid, err, hint = utils.validation.validate_expression_with_hints("variable")
  assert_true(valid, "Should accept simple variable")
  assert_equal(nil, err, "Should not have error for valid variable")

  valid, err, hint = utils.validation.validate_expression_with_hints("ptr->field")
  assert_true(valid, "Should accept pointer dereference")
  assert_true(hint and hint:match("Pointer dereference"), "Should provide hint for pointer")

  valid, err, hint = utils.validation.validate_expression_with_hints("array[5]")
  assert_true(valid, "Should accept array indexing")
  assert_true(hint and hint:match("Array indexing"), "Should provide hint for array")

  -- Invalid expressions
  valid, err, hint = utils.validation.validate_expression_with_hints("(unmatched")
  assert_true(not valid, "Should reject unmatched parenthesis")
  assert_true(err ~= nil, "Should have error for unmatched parenthesis")

  valid, err, hint = utils.validation.validate_expression_with_hints("")
  assert_true(not valid, "Should reject empty expression")
  assert_true(err ~= nil, "Should have error for empty expression")
end

-- Test hex value validation
function tests.test_hex_validation()
  -- Valid hex values
  local hex, err, suggestion = utils.validation.normalize_hex_value("0xFF")
  assert_equal("0xFF", hex, "Should normalize hex with 0x prefix")
  assert_equal(nil, err, "Should not have error for valid hex")

  hex, err, suggestion = utils.validation.normalize_hex_value("FF")
  assert_equal("0xFF", hex, "Should add 0x prefix")
  assert_equal(nil, err, "Should not have error for hex without prefix")

  hex, err, suggestion = utils.validation.normalize_hex_value("F")
  assert_equal("0x0F", hex, "Should pad odd-length hex")
  assert_equal(nil, err, "Should not have error for odd-length hex")

  -- Invalid hex values
  hex, err, suggestion = utils.validation.normalize_hex_value("XYZ")
  assert_equal(nil, hex, "Should reject invalid hex characters")
  assert_true(err ~= nil, "Should have error for invalid hex")

  hex, err, suggestion = utils.validation.normalize_hex_value("")
  assert_equal(nil, hex, "Should reject empty hex")
  assert_true(err ~= nil, "Should have error for empty hex")
end

-- Test GDB command validation
function tests.test_gdb_command_validation()
  -- Valid commands
  local valid, err, suggestion = utils.validation.validate_gdb_command_with_suggestions("print variable")
  assert_true(valid, "Should accept print command")
  assert_equal(nil, err, "Should not have error for valid command")

  valid, err, suggestion = utils.validation.validate_gdb_command_with_suggestions("break main.c:42")
  assert_true(valid, "Should accept break command")
  assert_equal(nil, err, "Should not have error for valid break")

  -- Dangerous commands
  valid, err, suggestion = utils.validation.validate_gdb_command_with_suggestions("quit")
  assert_true(not valid, "Should reject quit command")
  assert_true(err ~= nil, "Should have error for dangerous command")
  assert_true(suggestion ~= nil, "Should provide suggestion for dangerous command")

  -- Commands with suggestions
  valid, err, suggestion = utils.validation.validate_gdb_command_with_suggestions("print")
  assert_true(valid, "Should accept incomplete print command")
  assert_true(suggestion ~= nil, "Should provide suggestion for incomplete command")
end

-- Test comprehensive input validation
function tests.test_comprehensive_validation()
  -- Test address input
  local result = utils.validation.validate_input("address", "0x1234")
  assert_true(result.valid, "Should validate address input")
  assert_equal("0x1234", result.normalized, "Should normalize address")

  -- Test expression input
  result = utils.validation.validate_input("expression", "variable")
  assert_true(result.valid, "Should validate expression input")
  assert_equal("variable", result.normalized, "Should normalize expression")

  -- Test hex input
  result = utils.validation.validate_input("hex", "FF")
  assert_true(result.valid, "Should validate hex input")
  assert_equal("0xFF", result.normalized, "Should normalize hex")

  -- Test command input
  result = utils.validation.validate_input("command", "print var")
  assert_true(result.valid, "Should validate command input")
  assert_equal("print var", result.normalized, "Should normalize command")

  -- Test unknown input type
  result = utils.validation.validate_input("unknown", "value")
  assert_true(not result.valid, "Should reject unknown input type")
  assert_true(result.error ~= nil, "Should have error for unknown type")
end

-- Run all tests
print("Running termdebug-enhanced validation tests...\n")

for name, test_fn in pairs(tests) do
  run_test(name, test_fn)
end

print(string.format("\nResults: %d passed, %d failed", passed, failed))

if failed > 0 then
  os.exit(1)
end