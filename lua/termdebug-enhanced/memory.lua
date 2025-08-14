---@class MemoryState
---@field address string|nil Current memory address
---@field size number Number of bytes to display
---@field variable string|nil Variable name if applicable

---@class termdebug-enhanced.memory
---@field view_memory_at_cursor function View memory at cursor position
---@field show_memory function Display memory in hex viewer
---@field navigate_memory function Navigate memory by offset
---@field edit_memory_at_cursor function Edit memory/variable at cursor
local M = {}

local utils = require("termdebug-enhanced.utils")

---@type number|nil
local memory_win = nil
---@type number|nil
local memory_buf = nil

-- Helper function to get config safely
---@return MemoryConfig
local function get_config()
  local ok, main = pcall(require, "termdebug-enhanced")
  if ok and main.config and main.config.memory_viewer then
    return main.config.memory_viewer
  end
  -- Return default config if not initialized
  return {
    width = 80,
    height = 20,
    format = "hex",
    bytes_per_line = 16
  }
end

-- Clean up memory window resources
---@return nil
local function cleanup_memory_window()
  if memory_win and vim.api.nvim_win_is_valid(memory_win) then
    pcall(vim.api.nvim_win_close, memory_win, true)
  end
  if memory_buf and vim.api.nvim_buf_is_valid(memory_buf) then
    pcall(vim.api.nvim_buf_delete, memory_buf, { force = true })
  end
  memory_win = nil
  memory_buf = nil
end



---Create memory viewer window
---@param content string[] Content to display
---@param opts MemoryConfig|nil Window options
---@return number|nil, number|nil Window and buffer handles
local function create_memory_window(content, opts)
  opts = opts or {}

  -- Close existing window if any
  cleanup_memory_window()

  -- Create buffer for content
  memory_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(memory_buf, 0, -1, false, content)

  -- Calculate window size
  local height = opts.height or 20

  -- Create split window
  vim.cmd("botright " .. height .. "split")
  memory_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(memory_win, memory_buf)

  -- Set buffer options (using modern API)
  vim.bo[memory_buf].bufhidden = "wipe"
  vim.bo[memory_buf].buftype = "nofile"
  vim.bo[memory_buf].swapfile = false
  vim.bo[memory_buf].modifiable = false
  vim.api.nvim_buf_set_name(memory_buf, "Memory Viewer")

  -- Add syntax highlighting
  vim.bo[memory_buf].filetype = "xxd"

  -- Add keybindings for the memory window
  local keymaps = {
    ["q"] = function() cleanup_memory_window() end,
    ["<Esc>"] = function() cleanup_memory_window() end,
    ["r"] = function() M.refresh_memory() end,
    ["e"] = function() M.edit_memory_interactive() end,
    ["+"] = function() M.navigate_memory(16) end,
    ["-"] = function() M.navigate_memory(-16) end,
    ["<PageDown>"] = function() M.navigate_memory(256) end,
    ["<PageUp>"] = function() M.navigate_memory(-256) end,
  }

  for key, func in pairs(keymaps) do
    vim.api.nvim_buf_set_keymap(memory_buf, "n", key, "", {
      callback = func,
      noremap = true,
      silent = true
    })
  end

  -- Add help text at the top
  local help_text = {
    "── Memory Viewer ──────────────────────────────────────────────",
    "  q/<Esc>: close | r: refresh | e: edit | +/-: navigate | PgUp/PgDn: page",
    "───────────────────────────────────────────────────────────────",
    ""
  }
  vim.api.nvim_buf_set_lines(memory_buf, 0, 0, false, help_text)

  return memory_win, memory_buf
end

-- Store current memory view state
---@type MemoryState
local current_memory = {
  address = nil,
  size = 256,
  variable = nil
}

---View memory at cursor position
---Shows memory contents for variable/address under cursor
---@return nil
function M.view_memory_at_cursor()
  local word = vim.fn.expand("<cexpr>")
  if word == "" then
    word = vim.fn.expand("<cword>")
  end
  
  if word == "" then
    -- Ask for address
    word = vim.fn.input("Memory address or variable: ")
    if word == "" then
      return
    end
  end
  
  current_memory.variable = word

  -- Get address of variable or use direct address
  if word:match("^0x%x+") or word:match("^%d+") then
    -- Direct address
    current_memory.address = word
    M.show_memory(current_memory.address, current_memory.size)
  else
    -- Variable name - get its address first
    utils.async_gdb_response("print &" .. word, function(response, error)
      if error then
        vim.notify("Could not get address: " .. error, vim.log.levels.ERROR)
        return
      end

      -- Extract address from response
      local addr = nil
      for _, line in ipairs(response) do
        addr = line:match("0x%x+")
        if addr then
          break
        end
      end

      if addr then
        current_memory.address = addr
        M.show_memory(addr, current_memory.size)
      else
        vim.notify("Could not get address for: " .. word, vim.log.levels.ERROR)
      end
    end, { timeout = 2000 })
    return
  end
end

---Show memory contents in hex viewer
---@param address string Memory address to display
---@param size number Number of bytes to show
function M.show_memory(address, size)
  if not address then
    vim.notify("No address specified", vim.log.levels.ERROR)
    return
  end

  local config = get_config()
  local format = config.format or "hex"

  -- Send memory examination command
  local cmd
  if format == "hex" then
    cmd = string.format("x/%dxb %s", size, address)
  elseif format == "decimal" then
    cmd = string.format("x/%ddb %s", size, address)
  else -- binary
    cmd = string.format("x/%dtb %s", size, address)
  end

  -- Use async response handler
  utils.async_gdb_response(cmd, function(response, error)
    if error then
      vim.notify("Could not read memory: " .. error, vim.log.levels.ERROR)
      return
    end

    if #response > 0 then
      -- Add header
      local formatted = {
        string.format("Memory at %s (%d bytes):", address, size),
        string.rep("─", 70),
      }

      -- Add memory lines
      for _, line in ipairs(response) do
        table.insert(formatted, line)
      end

      create_memory_window(formatted, config)
    else
      vim.notify("Could not read memory at: " .. address, vim.log.levels.ERROR)
    end
  end, { timeout = 3000, max_lines = 100 })
end

-- Helper to parse address strings
---@param addr_str string|number Address string or number
---@return number|nil Parsed address as number
local function parse_address(addr_str)
  if type(addr_str) == "number" then
    return addr_str
  end

  if addr_str:match("^0x") then
    local hex = addr_str:match("^0x(%x+)")
    return hex and tonumber(hex, 16) or nil
  end

  return tonumber(addr_str)
end

---Navigate memory view by offset
---@param offset number Byte offset to navigate (positive or negative)
---@return nil
function M.navigate_memory(offset)
  if not current_memory.address then
    vim.notify("No memory view active", vim.log.levels.WARN)
    return
  end

  -- Calculate new address
  local addr_num = parse_address(current_memory.address)

  if addr_num then
    addr_num = addr_num + offset
    current_memory.address = string.format("0x%x", addr_num)
    M.show_memory(current_memory.address, current_memory.size)
  end
end

---Refresh current memory view
---@return nil
function M.refresh_memory()
  if current_memory.address then
    M.show_memory(current_memory.address, current_memory.size)
  else
    vim.notify("No memory view active", vim.log.levels.WARN)
  end
end

---Edit memory or variable at cursor position
---Prompts for new value and updates memory/variable
---@return nil
function M.edit_memory_at_cursor()
  local word = vim.fn.expand("<cexpr>")
  if word == "" then
    word = vim.fn.expand("<cword>")
  end

  if word == "" then
    word = vim.fn.input("Variable or address to edit: ")
    if word == "" then
      return
    end
  end

  -- Check if it's an address or variable
  if word:match("^0x%x+") or word:match("^%d+") then
    -- Memory address - ask for bytes
    local bytes = vim.fn.input("Enter bytes (hex, space-separated): ")
    if bytes ~= "" then
      -- Convert to set command
      local byte_list = {}
      for byte in bytes:gmatch("%x+") do
        table.insert(byte_list, "0x" .. byte)
      end

      for i, byte in ipairs(byte_list) do
        local addr = string.format("(char*)(%s)+%d", word, i-1)
        utils.async_gdb_response(string.format("set *%s = %s", addr, byte), function() end)
      end

      -- Refresh memory view if active
      if current_memory.address then
        vim.defer_fn(function()
          M.refresh_memory()
        end, 100)
      end
    end
  else
    -- Variable - ask for new value
    local value = vim.fn.input("Set " .. word .. " = ")
    if value ~= "" then
      utils.async_gdb_response("set variable " .. word .. " = " .. value, function(_response, error)
        if not error then
          -- Show updated value
          utils.async_gdb_response("print " .. word, function(r, e)
            if not e then
              local val = utils.extract_value(r)
              if val then
                vim.notify(word .. " = " .. val)
              end
            end
          end)
        end
      end)
    end
  end
end

-- Validate hex value
---@param byte_str string Hex byte string
---@return boolean True if valid hex byte
local function validate_hex_byte(byte_str)
  return byte_str:match("^%x%x?$") ~= nil
end

---Interactive memory editor for current view
---Allows editing memory at specific offset from current address
---@return nil
function M.edit_memory_interactive()
  if not current_memory.address then
    vim.notify("No memory view active", vim.log.levels.WARN)
    return
  end
  
  local offset = vim.fn.input("Offset from " .. current_memory.address .. ": ")
  if offset == "" then
    offset = "0"
  end
  
  local value = vim.fn.input("Value (hex): 0x")
  if value ~= "" and validate_hex_byte(value) then
    local addr = string.format("(char*)(%s)+%s", current_memory.address, offset)
    utils.async_gdb_response(string.format("set *%s = 0x%s", addr, value), function(response, error)
      if not error then
        vim.notify("Memory updated at offset " .. offset)
      end
    end)
    
    vim.defer_fn(function()
      M.refresh_memory()
    end, 100)
  end
end

-- Cleanup function for module
---@return nil
function M.cleanup_all_windows()
  cleanup_memory_window()
end

return M