-- Debug script to test popup functionality
-- Run with: nvim -l debug_popup_test.lua

-- Set up minimal vim environment
vim.o.compatible = false

-- Mock vim.notify to capture debug messages
local debug_messages = {}
local original_notify = vim.notify
vim.notify = function(msg, level)
  table.insert(debug_messages, {msg = msg, level = level or vim.log.levels.INFO})
  print(string.format("[%s] %s", level and vim.log.levels[level] or "INFO", msg))
end

-- Mock vim.schedule to run immediately
vim.schedule = function(fn)
  fn()
end

-- Mock vim.defer_fn to run immediately
vim.defer_fn = function(fn, delay)
  fn()
end

-- Mock vim.api functions for testing
local mock_buffers = {}
local mock_windows = {}
local next_buf_id = 1
local next_win_id = 1

vim.api.nvim_create_buf = function(listed, scratch)
  local buf_id = next_buf_id
  next_buf_id = next_buf_id + 1
  mock_buffers[buf_id] = {
    listed = listed,
    scratch = scratch,
    lines = {},
    valid = true
  }
  print("Created buffer: " .. buf_id)
  return buf_id
end

vim.api.nvim_buf_is_valid = function(buf)
  return mock_buffers[buf] and mock_buffers[buf].valid
end

vim.api.nvim_buf_set_lines = function(buf, start, finish, strict, lines)
  if mock_buffers[buf] then
    mock_buffers[buf].lines = lines
    print("Set buffer " .. buf .. " lines: " .. vim.inspect(lines))
  end
end

vim.api.nvim_open_win = function(buf, enter, config)
  local win_id = next_win_id
  next_win_id = next_win_id + 1
  mock_windows[win_id] = {
    buf = buf,
    config = config,
    valid = true
  }
  print("Created window: " .. win_id .. " for buffer: " .. buf)
  print("Window config: " .. vim.inspect(config))
  return win_id
end

vim.api.nvim_win_is_valid = function(win)
  return mock_windows[win] and mock_windows[win].valid
end

vim.api.nvim_win_close = function(win, force)
  if mock_windows[win] then
    mock_windows[win].valid = false
    print("Closed window: " .. win)
  end
end

vim.api.nvim_buf_delete = function(buf, opts)
  if mock_buffers[buf] then
    mock_buffers[buf].valid = false
    print("Deleted buffer: " .. buf)
  end
end

-- Mock other required functions
vim.api.nvim_create_autocmd = function() end
vim.api.nvim_buf_set_keymap = function() end
vim.bo = setmetatable({}, {
  __index = function() return {} end,
  __newindex = function() end
})
vim.wo = setmetatable({}, {
  __index = function() return {} end,
  __newindex = function() end
})

-- Mock vim.split
vim.split = function(str, sep)
  local result = {}
  for line in str:gmatch("[^\n]+") do
    table.insert(result, line)
  end
  return result
end

-- Mock vim.trim
vim.trim = function(str)
  return str:match("^%s*(.-)%s*$")
end

-- Mock vim.inspect
vim.inspect = function(obj)
  if type(obj) == "table" then
    local parts = {}
    for k, v in pairs(obj) do
      table.insert(parts, tostring(k) .. "=" .. tostring(v))
    end
    return "{" .. table.concat(parts, ", ") .. "}"
  end
  return tostring(obj)
end

-- Mock vim.log.levels
vim.log = {
  levels = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4
  }
}

-- Test the evaluate module
print("Testing popup creation...")

-- Mock the main plugin config
package.loaded["termdebug-enhanced"] = {
  config = {
    popup = { border = "rounded", width = 60, height = 10 }
  }
}

-- Mock utils module
package.loaded["termdebug-enhanced.utils"] = {
  async_gdb_response = function(cmd, callback, opts)
    print("Mock GDB command: " .. cmd)
    -- Simulate successful response
    vim.defer_fn(function()
      callback({"$1 = 42"}, nil)
    end, 10)
  end,
  extract_value = function(lines)
    if lines and #lines > 0 then
      local value = lines[1]:match("%$%d+ = (.+)")
      print("Extracted value: " .. (value or "nil"))
      return value
    end
    return nil
  end,
  track_resource = function() end,
  untrack_resource = function() end
}

-- Mock vim.fn functions
vim.fn = vim.fn or {}
vim.fn.exists = function(cmd)
  if cmd == ":Termdebug" then return 1 end
  return 0
end
vim.fn.expand = function(expr)
  if expr == "<cexpr>" then return "test_var" end
  if expr == "<cword>" then return "test_var" end
  return ""
end

-- Mock vim.g
vim.g = vim.g or {}
vim.g.termdebug_running = true

-- Now test the evaluate module
local evaluate = require("termdebug-enhanced.evaluate")

print("\n=== Testing evaluate_under_cursor ===")
evaluate.evaluate_under_cursor()

-- Wait a bit for async operations
local count = 0
while count < 5 do
  count = count + 1
  -- Check if popup was created
  local popup_created = false
  for win_id, win_data in pairs(mock_windows) do
    if win_data.valid then
      popup_created = true
      print("Found active window: " .. win_id)
      print("Window buffer: " .. win_data.buf)
      if mock_buffers[win_data.buf] then
        print("Buffer content: " .. vim.inspect(mock_buffers[win_data.buf].lines))
      end
    end
  end
  
  if popup_created then
    print("SUCCESS: Popup window was created!")
    break
  else
    print("Waiting for popup... (" .. count .. "/5)")
  end
end

print("\n=== Debug Messages ===")
for i, msg in ipairs(debug_messages) do
  print(i .. ": " .. msg.msg)
end

print("\n=== Mock State ===")
print("Buffers created: " .. (next_buf_id - 1))
print("Windows created: " .. (next_win_id - 1))

print("\nTest completed.")
