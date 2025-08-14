---Unit tests for termdebug-enhanced.evaluate module
---Run with: nvim -l tests/test_evaluate.lua

-- Mock the utils module before requiring evaluate
package.loaded["termdebug-enhanced.utils"] = {
  async_gdb_response = function(cmd, callback, _opts)
    -- Mock response based on command
    if cmd:match("^print") then
      callback({ "$1 = 42" }, nil)
    else
      callback(nil, "Unknown command")
    end
  end,
  extract_value = function(lines)
    if lines and #lines > 0 then
      return lines[1]:match("%$%d+ = (.+)")
    end
    return nil
  end,
  find_gdb_buffer = function() return 1 end,
}

-- Mock the main module config
package.loaded["termdebug-enhanced"] = {
  config = {
    popup = { border = "rounded", width = 60, height = 10 }
  }
}

local evaluate = require("termdebug-enhanced.evaluate")

-- Test framework
local tests = {}
local passed = 0
local failed = 0

local function assert_true(value, message)
  if not value then
    error((message or "Expected true, got: ") .. vim.inspect(value))
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

-- Test: evaluate_custom with valid expression
function tests.test_evaluate_custom()
  local popup_created = false
  local popup_content = {}

  -- Mock the floating window creation
  local orig_buf_set_lines = vim.api.nvim_buf_set_lines
  vim.api.nvim_buf_set_lines = function(buf, _start, _finish, _strict, lines)
    if buf ~= 0 then -- Not current buffer
      popup_created = true
      popup_content = lines
    end
    return orig_buf_set_lines(buf, _start, _finish, _strict, lines)
  end

  -- Test evaluation
  evaluate.evaluate_custom("test_var")

  -- Wait for async callback
  vim.wait(100, function() return popup_created end, 10)

  assert_true(popup_created, "Should create popup window")
  assert_true(popup_content ~= nil, "Should have popup content")

  -- Check content includes expression and value
  local content = table.concat(popup_content, "\n")
  assert_true(content:match("test_var"), "Should show expression")
  assert_true(content:match("42"), "Should show value")

  -- Restore original function
  vim.api.nvim_buf_set_lines = orig_buf_set_lines
end

-- Test: evaluate_under_cursor with no word
function tests.test_evaluate_no_word()
  -- Mock expand to return empty
  local orig_expand = vim.fn.expand
  vim.fn.expand = function(_expr)
    return ""
  end

  local notified = false
  local orig_notify = vim.notify
  vim.notify = function(msg, _level)
    if msg:match("No expression") then
      notified = true
    end
  end

  evaluate.evaluate_under_cursor()

  assert_true(notified, "Should notify when no expression")

  -- Restore
  vim.fn.expand = orig_expand
  vim.notify = orig_notify
end

-- Test: evaluate_selection with valid selection
function tests.test_evaluate_selection()
  -- Mock visual selection
  local orig_getpos = vim.fn.getpos
  vim.fn.getpos = function(mark)
    if mark == "'<" then
      return { 0, 1, 5, 0 }  -- Start at line 1, col 5
    elseif mark == "'>" then
      return { 0, 1, 10, 0 } -- End at line 1, col 10
    end
    return orig_getpos(mark)
  end

  local orig_buf_get_lines = vim.api.nvim_buf_get_lines
  vim.api.nvim_buf_get_lines = function(buf, start, finish, _strict)
    if buf == 0 and start == 0 and finish == 1 then
      return { "    test_expr    " } -- Line with selection
    end
    return orig_buf_get_lines(buf, start, finish, _strict)
  end

  local popup_created = false
  vim.api.nvim_buf_set_lines = function(buf, _start, _finish, _strict, _lines)
    if buf ~= 0 then
      popup_created = true
    end
    return {}
  end

  evaluate.evaluate_selection()

  -- Wait for async
  vim.wait(100, function() return popup_created end, 10)

  assert_true(popup_created, "Should create popup for selection")

  -- Restore
  vim.fn.getpos = orig_getpos
  vim.api.nvim_buf_get_lines = orig_buf_get_lines
end

-- Run all tests
print("Running termdebug-enhanced.evaluate tests...\n")

for name, test_fn in pairs(tests) do
  run_test(name, test_fn)
end

print(string.format("\nResults: %d passed, %d failed", passed, failed))

if failed > 0 then
  os.exit(1)
end
