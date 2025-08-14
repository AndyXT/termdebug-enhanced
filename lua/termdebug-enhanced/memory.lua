---@class MemoryState
---@field address string|nil Current memory address
---@field size number Number of bytes to display
---@field variable string|nil Variable name if applicable

---@class MemoryError
---@field type string Error type (invalid_address, access_denied, gdb_unavailable, timeout)
---@field message string Human-readable error message
---@field address string|nil The address that caused the error

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
---@return table
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

-- Validate memory address
---@param addr string Address to validate
---@return boolean valid, string|nil error_msg
local function validate_address(addr)
  if not addr or addr == "" then
    return false, "Empty address"
  end
  
  local trimmed = vim.trim(addr)
  if trimmed == "" then
    return false, "Address contains only whitespace"
  end

  -- Check for hex address format
  if trimmed:match("^0x%x+$") then
    return true, nil
  end

  -- Check for decimal address
  if trimmed:match("^%d+$") then
    return true, nil
  end

  -- Check for variable name (basic validation)
  if trimmed:match("^[%a_][%w_]*$") then
    return true, nil
  end

  return false, "Invalid address format. Use hex (0x1234), decimal (1234), or variable name"
end

-- Validate hex value for memory editing
---@param hex_str string Hex value to validate
---@return boolean valid, string|nil error_msg
local function validate_hex_value(hex_str)
  if not hex_str or hex_str == "" then
    return false, "Empty hex value"
  end
  
  local trimmed = vim.trim(hex_str)
  if trimmed == "" then
    return false, "Hex value contains only whitespace"
  end

  -- Remove 0x prefix if present
  local hex_part = trimmed:gsub("^0x", "")

  -- Check if it's valid hex
  if not hex_part:match("^%x+$") then
    return false, "Invalid hex format. Use hex digits (0-9, A-F)"
  end

  -- Check reasonable length (1-8 hex digits for 32-bit values)
  if #hex_part > 8 then
    return false, "Hex value too long (max 8 digits for 32-bit)"
  end

  return true, nil
end

-- Check if GDB is available for memory operations
---@return boolean available, string|nil error_msg
local function check_memory_gdb_availability()
  if vim.fn.exists(':Termdebug') == 0 then
    return false, "Termdebug not available. Run :packadd termdebug"
  end

  if not vim.g.termdebug_running then
    return false, "Debug session not active. Start debugging first"
  end

  return true, nil
end

-- Create error display for memory operations
---@param error_info MemoryError Error information
---@return string[] Formatted error content
local function create_memory_error_content(error_info)
  local content = {
    "❌ Memory Error",
    string.rep("─", 50),
  }
  
  if error_info.address then
    table.insert(content, "Address: " .. error_info.address)
    table.insert(content, "")
  end
  
  table.insert(content, "Error: " .. error_info.message)
  
  -- Add helpful hints based on error type
  if error_info.type == "invalid_address" then
    table.insert(content, "")
    table.insert(content, "💡 Hint: Check address format (0x1234 or variable name)")
  elseif error_info.type == "access_denied" then
    table.insert(content, "")
    table.insert(content, "💡 Hint: Address may be protected or invalid")
  elseif error_info.type == "gdb_unavailable" then
    table.insert(content, "")
    table.insert(content, "💡 Hint: Start debugging session first")
  elseif error_info.type == "timeout" then
    table.insert(content, "")
    table.insert(content, "💡 Hint: Memory operation timed out")
  end
  
  return content
end

-- Clean up memory window resources
---@return nil
local function cleanup_memory_window()
  if memory_win and vim.api.nvim_win_is_valid(memory_win) then
    local ok, err = pcall(vim.api.nvim_win_close, memory_win, true)
    if not ok then
      vim.notify("Failed to close memory window: " .. tostring(err), vim.log.levels.WARN)
    end
  end
  if memory_buf and vim.api.nvim_buf_is_valid(memory_buf) then
    local ok, err = pcall(vim.api.nvim_buf_delete, memory_buf, { force = true })
    if not ok then
      vim.notify("Failed to delete memory buffer: " .. tostring(err), vim.log.levels.WARN)
    end
  end
  memory_win = nil
  memory_buf = nil
end



---Create memory viewer window
---@param content string[] Content to display
---@param opts table|nil Window options
---@param is_error boolean|nil Whether this is an error display
---@return number|nil, number|nil Window and buffer handles
local function create_memory_window(content, opts, is_error)
  opts = opts or {}
  is_error = is_error or false

  -- Close existing window if any
  cleanup_memory_window()

  -- Create buffer for content
  local buf_ok, buf = pcall(vim.api.nvim_create_buf, false, true)
  if not buf_ok then
    vim.notify("Failed to create memory buffer: " .. tostring(buf), vim.log.levels.ERROR)
    return nil, nil
  end
  memory_buf = buf

  local content_ok, content_err = pcall(vim.api.nvim_buf_set_lines, memory_buf, 0, -1, false, content or {})
  if not content_ok then
    vim.notify("Failed to set memory buffer content: " .. tostring(content_err), vim.log.levels.ERROR)
    cleanup_memory_window()
    return nil, nil
  end

  -- Calculate window size
  local height = opts.height or 20

  -- Create split window with error handling
  local split_ok, split_err = pcall(vim.cmd, "botright " .. height .. "split")
  if not split_ok then
    vim.notify("Failed to create memory window: " .. tostring(split_err), vim.log.levels.ERROR)
    cleanup_memory_window()
    return nil, nil
  end

  memory_win = vim.api.nvim_get_current_win()
  
  local set_buf_ok, set_buf_err = pcall(vim.api.nvim_win_set_buf, memory_win, memory_buf)
  if not set_buf_ok then
    vim.notify("Failed to set memory window buffer: " .. tostring(set_buf_err), vim.log.levels.ERROR)
    cleanup_memory_window()
    return nil, nil
  end

  -- Set buffer options (using modern API with error handling)
  pcall(function()
    vim.bo[memory_buf].bufhidden = "wipe"
    vim.bo[memory_buf].buftype = "nofile"
    vim.bo[memory_buf].swapfile = false
    vim.bo[memory_buf].modifiable = false
  end)
  
  pcall(vim.api.nvim_buf_set_name, memory_buf, is_error and "Memory Error" or "Memory Viewer")

  -- Add syntax highlighting
  pcall(function()
    vim.bo[memory_buf].filetype = is_error and "text" or "xxd"
  end)

  if not is_error then
    -- Add keybindings for the memory window (only for non-error windows)
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
      pcall(vim.api.nvim_buf_set_keymap, memory_buf, "n", key, "", {
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
    pcall(vim.api.nvim_buf_set_lines, memory_buf, 0, 0, false, help_text)
  else
    -- For error windows, just add close keybindings
    local error_keymaps = {
      ["q"] = function() cleanup_memory_window() end,
      ["<Esc>"] = function() cleanup_memory_window() end,
    }
    
    for key, func in pairs(error_keymaps) do
      pcall(vim.api.nvim_buf_set_keymap, memory_buf, "n", key, "", {
        callback = func,
        noremap = true,
        silent = true
      })
    end
  end

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
  -- Check GDB availability first
  local available, availability_error = check_memory_gdb_availability()
  if not available then
    local error_content = create_memory_error_content({
      type = "gdb_unavailable",
      message = availability_error,
      address = nil
    })
    local config = get_config()
    create_memory_window(error_content, config, true)
    return
  end

  local word = vim.fn.expand("<cexpr>")
  if word == "" then
    word = vim.fn.expand("<cword>")
  end
  
  if word == "" then
    -- Ask for address with error handling
    local input_ok, input_word = pcall(vim.fn.input, "Memory address or variable: ")
    if not input_ok then
      vim.notify("Failed to get input", vim.log.levels.ERROR)
      return
    end
    word = input_word
    if word == "" then
      return
    end
  end
  
  -- Validate the address/variable
  local valid, validation_error = validate_address(word)
  if not valid then
    local error_content = create_memory_error_content({
      type = "invalid_address",
      message = validation_error,
      address = word
    })
    local config = get_config()
    create_memory_window(error_content, config, true)
    return
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
        local error_content = create_memory_error_content({
          type = "access_denied",
          message = "Could not get address: " .. error,
          address = word
        })
        local config = get_config()
        create_memory_window(error_content, config, true)
        return
      end

      -- Extract address from response
      local addr = nil
      if response and #response > 0 then
        for _, line in ipairs(response) do
          addr = line:match("0x%x+")
          if addr then
            break
          end
        end
      end

      if addr then
        current_memory.address = addr
        M.show_memory(addr, current_memory.size)
      else
        local error_content = create_memory_error_content({
          type = "access_denied",
          message = "Could not get address for variable (may not be in scope)",
          address = word
        })
        local config = get_config()
        create_memory_window(error_content, config, true)
      end
    end, { timeout = 3000 })
    return
  end
end

---Show memory contents in hex viewer
---@param address string Memory address to display
---@param size number Number of bytes to show
function M.show_memory(address, size)
  if not address then
    local error_content = create_memory_error_content({
      type = "invalid_address",
      message = "No address specified",
      address = nil
    })
    local config = get_config()
    create_memory_window(error_content, config, true)
    return
  end

  -- Validate address
  local valid, validation_error = validate_address(address)
  if not valid then
    local error_content = create_memory_error_content({
      type = "invalid_address",
      message = validation_error,
      address = address
    })
    local config = get_config()
    create_memory_window(error_content, config, true)
    return
  end

  -- Check GDB availability
  local available, availability_error = check_memory_gdb_availability()
  if not available then
    local error_content = create_memory_error_content({
      type = "gdb_unavailable",
      message = availability_error,
      address = address
    })
    local config = get_config()
    create_memory_window(error_content, config, true)
    return
  end

  local config = get_config()
  local format = config.format or "hex"
  size = size or current_memory.size

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
      local error_type = "access_denied"
      local error_msg = error
      
      -- Categorize error types
      if error:match("[Tt]imeout") then
        error_type = "timeout"
        error_msg = "Memory read timeout - address may be invalid"
      elseif error:match("[Ii]nvalid") or error:match("[Cc]annot access") then
        error_type = "access_denied"
        error_msg = "Cannot access memory at address (may be protected or invalid)"
      end
      
      local error_content = create_memory_error_content({
        type = error_type,
        message = error_msg,
        address = address
      })
      create_memory_window(error_content, config, true)
      return
    end

    if response and #response > 0 then
      -- Check if response indicates an error
      local response_text = table.concat(response, " ")
      if response_text:match("[Cc]annot access") or 
         response_text:match("[Ii]nvalid") or
         response_text:match("[Ee]rror") then
        local error_content = create_memory_error_content({
          type = "access_denied",
          message = "Cannot access memory: " .. response_text,
          address = address
        })
        create_memory_window(error_content, config, true)
        return
      end

      -- Add header
      local formatted = {
        string.format("✓ Memory at %s (%d bytes):", address, size),
        string.rep("─", 70),
      }

      -- Add memory lines
      for _, line in ipairs(response) do
        table.insert(formatted, line)
      end

      create_memory_window(formatted, config, false)
    else
      local error_content = create_memory_error_content({
        type = "access_denied",
        message = "No memory data returned (address may be invalid)",
        address = address
      })
      create_memory_window(error_content, config, true)
    end
  end, { timeout = 5000, max_lines = 100 })
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

  -- Calculate new address with error handling
  local addr_num = parse_address(current_memory.address)

  if addr_num then
    local new_addr = addr_num + offset
    
    -- Check for address underflow
    if new_addr < 0 then
      vim.notify("Cannot navigate to negative address", vim.log.levels.WARN)
      return
    end
    
    current_memory.address = string.format("0x%x", new_addr)
    M.show_memory(current_memory.address, current_memory.size)
  else
    local error_content = create_memory_error_content({
      type = "invalid_address",
      message = "Cannot parse current address for navigation",
      address = current_memory.address
    })
    local config = get_config()
    create_memory_window(error_content, config, true)
  end
end

---Refresh current memory view
---@return nil
function M.refresh_memory()
  if current_memory.address then
    M.show_memory(current_memory.address, current_memory.size)
  else
    local error_content = create_memory_error_content({
      type = "invalid_address",
      message = "No memory view active to refresh",
      address = nil
    })
    local config = get_config()
    create_memory_window(error_content, config, true)
  end
end

---Edit memory or variable at cursor position
---Prompts for new value and updates memory/variable
---@return nil
function M.edit_memory_at_cursor()
  -- Check GDB availability first
  local available, availability_error = check_memory_gdb_availability()
  if not available then
    vim.notify(availability_error, vim.log.levels.ERROR)
    return
  end

  local word = vim.fn.expand("<cexpr>")
  if word == "" then
    word = vim.fn.expand("<cword>")
  end

  if word == "" then
    local input_ok, input_word = pcall(vim.fn.input, "Variable or address to edit: ")
    if not input_ok then
      vim.notify("Failed to get input", vim.log.levels.ERROR)
      return
    end
    word = input_word
    if word == "" then
      return
    end
  end

  -- Validate the address/variable
  local valid, validation_error = validate_address(word)
  if not valid then
    vim.notify("Invalid address/variable: " .. validation_error, vim.log.levels.ERROR)
    return
  end

  -- Check if it's an address or variable
  if word:match("^0x%x+") or word:match("^%d+") then
    -- Memory address - ask for bytes
    local bytes_ok, bytes = pcall(vim.fn.input, "Enter bytes (hex, space-separated): ")
    if not bytes_ok then
      vim.notify("Failed to get hex input", vim.log.levels.ERROR)
      return
    end
    
    if bytes ~= "" then
      -- Validate and convert to set commands
      local byte_list = {}
      local validation_failed = false
      
      for byte in bytes:gmatch("%S+") do
        local hex_valid, hex_error = validate_hex_value(byte)
        if not hex_valid then
          vim.notify("Invalid hex value '" .. byte .. "': " .. hex_error, vim.log.levels.ERROR)
          validation_failed = true
          break
        end
        table.insert(byte_list, "0x" .. byte:gsub("^0x", ""))
      end
      
      if not validation_failed and #byte_list > 0 then
        local completed_operations = 0
        local total_operations = #byte_list
        local has_error = false
        
        for i, byte in ipairs(byte_list) do
          local addr = string.format("(char*)(%s)+%d", word, i-1)
          utils.async_gdb_response(string.format("set *%s = %s", addr, byte), function(response, error)
            completed_operations = completed_operations + 1
            
            if error then
              has_error = true
              vim.notify("Failed to set byte at offset " .. (i-1) .. ": " .. error, vim.log.levels.ERROR)
            end
            
            -- When all operations complete, refresh if no errors
            if completed_operations == total_operations then
              if not has_error then
                vim.notify("Memory updated successfully", vim.log.levels.INFO)
                -- Refresh memory view if active
                if current_memory.address then
                  vim.defer_fn(function()
                    M.refresh_memory()
                  end, 200)
                end
              end
            end
          end)
        end
      end
    end
  else
    -- Variable - ask for new value
    local value_ok, value = pcall(vim.fn.input, "Set " .. word .. " = ")
    if not value_ok then
      vim.notify("Failed to get value input", vim.log.levels.ERROR)
      return
    end
    
    if value ~= "" then
      utils.async_gdb_response("set variable " .. word .. " = " .. value, function(response, error)
        if error then
          vim.notify("Failed to set variable: " .. error, vim.log.levels.ERROR)
        else
          -- Show updated value
          utils.async_gdb_response("print " .. word, function(r, e)
            if not e and r then
              local val = utils.extract_value(r)
              if val then
                vim.notify(word .. " = " .. val, vim.log.levels.INFO)
              else
                vim.notify("Variable " .. word .. " updated", vim.log.levels.INFO)
              end
            else
              vim.notify("Variable " .. word .. " updated (verification failed)", vim.log.levels.WARN)
            end
          end)
        end
      end)
    end
  end
end

---Interactive memory editor for current view
---Allows editing memory at specific offset from current address
---@return nil
function M.edit_memory_interactive()
  if not current_memory.address then
    local error_content = create_memory_error_content({
      type = "invalid_address",
      message = "No memory view active for editing",
      address = nil
    })
    local config = get_config()
    create_memory_window(error_content, config, true)
    return
  end
  
  -- Check GDB availability
  local available, availability_error = check_memory_gdb_availability()
  if not available then
    vim.notify(availability_error, vim.log.levels.ERROR)
    return
  end
  
  local offset_ok, offset = pcall(vim.fn.input, "Offset from " .. current_memory.address .. ": ")
  if not offset_ok then
    vim.notify("Failed to get offset input", vim.log.levels.ERROR)
    return
  end
  
  if offset == "" then
    offset = "0"
  end
  
  -- Validate offset (should be a number)
  if not offset:match("^%-?%d+$") then
    vim.notify("Invalid offset format. Use a number (e.g., 0, 16, -8)", vim.log.levels.ERROR)
    return
  end
  
  local value_ok, value = pcall(vim.fn.input, "Value (hex): 0x")
  if not value_ok then
    vim.notify("Failed to get value input", vim.log.levels.ERROR)
    return
  end
  
  if value ~= "" then
    -- Validate hex value
    local hex_valid, hex_error = validate_hex_value("0x" .. value)
    if not hex_valid then
      vim.notify("Invalid hex value: " .. hex_error, vim.log.levels.ERROR)
      return
    end
    
    local addr = string.format("(char*)(%s)+%s", current_memory.address, offset)
    utils.async_gdb_response(string.format("set *%s = 0x%s", addr, value), function(response, error)
      if error then
        vim.notify("Failed to update memory at offset " .. offset .. ": " .. error, vim.log.levels.ERROR)
      else
        vim.notify("Memory updated at offset " .. offset, vim.log.levels.INFO)
        -- Refresh memory view
        vim.defer_fn(function()
          M.refresh_memory()
        end, 200)
      end
    end)
  end
end

-- Cleanup function for module
---@return nil
function M.cleanup_all_windows()
  cleanup_memory_window()
end

return M